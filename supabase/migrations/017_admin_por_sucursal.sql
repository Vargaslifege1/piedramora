-- ============================================================================
-- Piedra Mora - Fase 1 - Administradores por sucursal
-- Migracion 017
-- ============================================================================
-- IMPORTANTE: hacer backup de la base antes de aplicarla.
--
-- Requisitos:
--   - 001 (admins, es_admin, carta y storage)
--   - 010, 011 (pedidos, zonas, tramos y RLS base)
--   - 013, 014 (crear_pedido y pm_calcular_pedido definitivos)
--   - 015 (envio por distancia, ya aplicado a mano)
--   - 016 (estados y pagos, ya aplicado en la base real)
--
-- Objetivo:
--   1. Agregar rol y sucursal a public.admins.
--   2. Crear es_dueno() y sucursal_admin().
--   3. Aplicar RLS por sucursal en pedidos y en las tablas de envio.
--   4. Dejar carta, config_negocio y Storage en escritura solo para el dueno.
--   5. Agregar agotados_sucursal y hacer que la carta publica y crear_pedido
--      respeten el agotado por sucursal.
--
-- Sucursales reales:
--   - intendente-lascano  (Sucursal Oeste)
--   - maestro-quiroga     (Centro)
--
-- Hallazgos sobre horarios, cierres, formas de entrega y estado manual:
--   - admin.js y main.js solo usan las tablas config_negocio, pedidos,
--     tramos_envio y zonas_envio.
--   - Los horarios y cierres viven en data/sucursales.json (horarios,
--     horarioTexto, cierreNormal, cierreFinde, cerradoLunes) y se calculan
--     en main.js; no hay tabla de Supabase para ellos.
--   - Las formas de entrega estan fijas en el HTML y el pedido guarda
--     pedidos.modalidad ('delivery' o 'retiro'); no hay tabla de formas.
--   - No existe un "estado manual" del negocio en el codigo actual. El estado
--     abierto/cerrado se calcula con los horarios locales.
--   - data/config.json solo contiene negocio y pagos.
--   Por eso esta migracion no crea ni modifica tablas de horarios, cierres,
--   formas de entrega ni estado manual. Si en el futuro pasan a Supabase,
--   necesitaran su propia migracion con sucursal_id y estas mismas politicas.
--
-- Idempotente: se puede ejecutar varias veces. No borra pedidos ni datos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Admins: rol y sucursal
-- ----------------------------------------------------------------------------
alter table public.admins
  add column if not exists rol text;

alter table public.admins
  add column if not exists sucursal_id text;

-- Todos los admins existentes quedan como duenos.
update public.admins
   set rol = 'dueno'
 where rol is null or btrim(rol) = '';

update public.admins
   set sucursal_id = null
 where rol = 'dueno'
   and sucursal_id is not null;

alter table public.admins
  alter column rol set default 'dueno';

alter table public.admins
  alter column rol set not null;

alter table public.admins
  drop constraint if exists admins_rol_chk;

alter table public.admins
  add constraint admins_rol_chk
  check (rol in ('dueno', 'sucursal'));

alter table public.admins
  drop constraint if exists admins_rol_sucursal_chk;

alter table public.admins
  add constraint admins_rol_sucursal_chk
  check (
    (rol = 'dueno' and sucursal_id is null)
    or (
      rol = 'sucursal'
      and sucursal_id is not null
      and sucursal_id in ('maestro-quiroga', 'intendente-lascano')
    )
  );

create index if not exists admins_sucursal_id_idx
  on public.admins (sucursal_id);

-- Los admins se gestionan solo por SQL/Auth (service role o dashboard).
-- No hay pantalla ni acceso directo para anon/authenticated: un admin de
-- sucursal no puede crear admins ni cambiar su propio sucursal_id.
alter table public.admins enable row level security;
revoke all on public.admins from public, anon, authenticated;
grant all on public.admins to service_role;

-- ----------------------------------------------------------------------------
-- 2. Funciones de autorizacion
-- ----------------------------------------------------------------------------
-- es_admin() se mantiene igual que en 001.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admins a
    where lower(trim(a.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );
$$;

revoke all on function public.es_admin() from public;
grant execute on function public.es_admin() to authenticated;

comment on function public.es_admin() is
  'Devuelve true si el email del JWT actual existe en public.admins.';

create or replace function public.es_dueno()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admins a
    where lower(trim(a.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
      and a.rol = 'dueno'
  );
$$;

revoke all on function public.es_dueno() from public;
grant execute on function public.es_dueno() to authenticated;

comment on function public.es_dueno() is
  'Devuelve true si el email del JWT actual es un admin con rol dueno.';

create or replace function public.sucursal_admin()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select a.sucursal_id
  from public.admins a
  where lower(trim(a.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
    and a.rol = 'sucursal'
    and a.sucursal_id is not null
  limit 1;
$$;

revoke all on function public.sucursal_admin() from public;
grant execute on function public.sucursal_admin() to authenticated;

comment on function public.sucursal_admin() is
  'Devuelve el sucursal_id del admin de sucursal del JWT. Null para dueno o si no es admin de sucursal.';

-- Rol y sucursal del admin actual en una sola llamada, sin exponer la tabla.
create or replace function public.mi_rol()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'rol', a.rol,
    'sucursal_id', a.sucursal_id
  )
  from public.admins a
  where lower(trim(a.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  limit 1;
$$;

revoke all on function public.mi_rol() from public;
grant execute on function public.mi_rol() to authenticated;

comment on function public.mi_rol() is
  'Devuelve {rol, sucursal_id} del admin del JWT. Null si el email no es admin.';

-- ----------------------------------------------------------------------------
-- 3. Pedidos: solo dueno o la sucursal del admin
-- ----------------------------------------------------------------------------
grant select on public.pedidos to authenticated;
grant update (estado, pagado, pagado_en) on public.pedidos to authenticated;

drop policy if exists "Pedidos lectura admin" on public.pedidos;
create policy "Pedidos lectura admin"
  on public.pedidos
  for select
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

drop policy if exists "Pedidos edicion admin" on public.pedidos;
create policy "Pedidos edicion admin"
  on public.pedidos
  for update
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  )
  with check (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

-- ----------------------------------------------------------------------------
-- 4. Zonas y tramos de envio
-- ----------------------------------------------------------------------------
-- Lectura: se mantiene la lectura publica de 011 ("Zonas lectura publica" y
-- "Tramos lectura publica"), porque main.js lee estas tablas con anon.
-- Escritura: el dueno edita todo; el admin de sucursal solo puede crear,
-- editar o borrar filas de su propia sucursal. Las filas globales
-- (sucursal_id null) solo las toca el dueno.
-- La lectura publica ya alcanza a los admins: no se crea una politica extra.
drop policy if exists "Zonas lectura admin" on public.zonas_envio;
drop policy if exists "Tramos lectura admin" on public.tramos_envio;

drop policy if exists "Zonas alta admin" on public.zonas_envio;
create policy "Zonas alta admin"
  on public.zonas_envio
  for insert
  to authenticated
  with check (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

drop policy if exists "Zonas edicion admin" on public.zonas_envio;
create policy "Zonas edicion admin"
  on public.zonas_envio
  for update
  to authenticated
  using (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  )
  with check (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

drop policy if exists "Zonas baja admin" on public.zonas_envio;
create policy "Zonas baja admin"
  on public.zonas_envio
  for delete
  to authenticated
  using (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

drop policy if exists "Tramos alta admin" on public.tramos_envio;
create policy "Tramos alta admin"
  on public.tramos_envio
  for insert
  to authenticated
  with check (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

drop policy if exists "Tramos edicion admin" on public.tramos_envio;
create policy "Tramos edicion admin"
  on public.tramos_envio
  for update
  to authenticated
  using (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  )
  with check (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

drop policy if exists "Tramos baja admin" on public.tramos_envio;
create policy "Tramos baja admin"
  on public.tramos_envio
  for delete
  to authenticated
  using (
    public.es_dueno()
    or (sucursal_id is not null and sucursal_id = public.sucursal_admin())
  );

-- ----------------------------------------------------------------------------
-- 5. Carta, configuracion y Storage: escritura solo dueno
-- ----------------------------------------------------------------------------
drop policy if exists "Carta alta admin" on public.carta;
create policy "Carta alta admin"
  on public.carta
  for insert
  to authenticated
  with check (public.es_dueno());

drop policy if exists "Carta edicion admin" on public.carta;
create policy "Carta edicion admin"
  on public.carta
  for update
  to authenticated
  using (public.es_dueno())
  with check (public.es_dueno());

drop policy if exists "Carta baja admin" on public.carta;
create policy "Carta baja admin"
  on public.carta
  for delete
  to authenticated
  using (public.es_dueno());

drop policy if exists "Config alta admin" on public.config_negocio;
create policy "Config alta admin"
  on public.config_negocio
  for insert
  to authenticated
  with check (public.es_dueno());

drop policy if exists "Config edicion admin" on public.config_negocio;
create policy "Config edicion admin"
  on public.config_negocio
  for update
  to authenticated
  using (public.es_dueno())
  with check (public.es_dueno());

drop policy if exists "Config baja admin" on public.config_negocio;
create policy "Config baja admin"
  on public.config_negocio
  for delete
  to authenticated
  using (public.es_dueno());

-- clientes: la lectura pasa de es_admin() a es_dueno(). Los contadores los
-- sigue manteniendo el trigger pm_pedidos_actualizar_clientes().
drop policy if exists "Clientes lectura admin" on public.clientes;
create policy "Clientes lectura admin"
  on public.clientes
  for select
  to authenticated
  using (public.es_dueno());

drop policy if exists "Imagenes alta admin" on storage.objects;
create policy "Imagenes alta admin"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'carta-imagenes'
    and public.es_dueno()
  );

drop policy if exists "Imagenes edicion admin" on storage.objects;
create policy "Imagenes edicion admin"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and public.es_dueno()
  )
  with check (
    bucket_id = 'carta-imagenes'
    and public.es_dueno()
  );

drop policy if exists "Imagenes baja admin" on storage.objects;
create policy "Imagenes baja admin"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and public.es_dueno()
  );

-- ----------------------------------------------------------------------------
-- 6. Agotados por sucursal
-- ----------------------------------------------------------------------------
create table if not exists public.agotados_sucursal (
  producto_id text not null,
  sucursal_id text not null,
  created_at timestamptz not null default now(),

  primary key (producto_id, sucursal_id),

  constraint agotados_sucursal_producto_chk
    check (char_length(btrim(producto_id)) between 1 and 120),

  constraint agotados_sucursal_sucursal_chk
    check (sucursal_id in ('maestro-quiroga', 'intendente-lascano'))
);

create index if not exists agotados_sucursal_sucursal_idx
  on public.agotados_sucursal (sucursal_id);

comment on table public.agotados_sucursal is
  'Productos agotados para una sucursal. La carta publica y crear_pedido deben respetarlo.';

alter table public.agotados_sucursal enable row level security;
revoke all on public.agotados_sucursal from anon;
grant select, insert, update, delete on public.agotados_sucursal to authenticated;

drop policy if exists "Agotados lectura admin" on public.agotados_sucursal;
create policy "Agotados lectura admin"
  on public.agotados_sucursal
  for select
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

drop policy if exists "Agotados alta admin" on public.agotados_sucursal;
create policy "Agotados alta admin"
  on public.agotados_sucursal
  for insert
  to authenticated
  with check (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

drop policy if exists "Agotados edicion admin" on public.agotados_sucursal;
create policy "Agotados edicion admin"
  on public.agotados_sucursal
  for update
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  )
  with check (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

drop policy if exists "Agotados baja admin" on public.agotados_sucursal;
create policy "Agotados baja admin"
  on public.agotados_sucursal
  for delete
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

-- ----------------------------------------------------------------------------
-- 7. Carta publica por sucursal
-- ----------------------------------------------------------------------------
-- Mantiene la forma actual de public.carta.contenido y solo agrega los campos
-- que ya usa el frontend: agotado y agotado_hasta_nuevo_aviso.
create or replace function public.carta_por_sucursal(p_sucursal_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_coords jsonb;
  v_carta jsonb;
  v_productos jsonb;
begin
  select valor into v_coords
    from public.config_negocio
   where clave = 'sucursales_coords';

  if p_sucursal_id is null
     or v_coords is null
     or not (v_coords ? p_sucursal_id) then
    raise exception 'La sucursal no existe.';
  end if;

  select contenido into v_carta
    from public.carta
   where id = 1;

  if v_carta is null or jsonb_typeof(v_carta -> 'productos') <> 'array' then
    raise exception 'La carta no está disponible en este momento.';
  end if;

  select coalesce(jsonb_agg(
           case
             when a.producto_id is not null
               then p.value || jsonb_build_object(
                 'agotado', true,
                 'agotado_hasta_nuevo_aviso', true
               )
             else p.value
           end
           order by p.ord
         ), '[]'::jsonb)
    into v_productos
    from jsonb_array_elements(v_carta -> 'productos') with ordinality as p(value, ord)
    left join public.agotados_sucursal a
      on a.producto_id = (p.value ->> 'id')
     and a.sucursal_id = p_sucursal_id;

  return jsonb_set(v_carta, '{productos}', v_productos, true);
end;
$$;

revoke all on function public.carta_por_sucursal(text) from public;
grant execute on function public.carta_por_sucursal(text) to anon, authenticated;

comment on function public.carta_por_sucursal(text) is
  'Devuelve la carta publica marcando como agotados los productos de agotados_sucursal para la sucursal indicada.';

-- ----------------------------------------------------------------------------
-- 8. crear_pedido: calcular con agotados por sucursal
-- ----------------------------------------------------------------------------
-- Se recrea pm_calcular_pedido partiendo de la ultima definicion real vigente:
--   013 + ajuste de ofertas de 014 + tramos por cuadras de 015.
--   016 no modifica esta funcion.
-- El unico cambio es el bloque de agotados_sucursal.
-- La firma es identica, por lo que crear_pedido sigue funcionando sin cambios.
create or replace function public.pm_calcular_pedido(
  p_sucursal_id text,
  p_modalidad   text,
  p_metodo_pago text,
  p_items       jsonb,
  p_zona_envio  text default null,
  p_lat         numeric default null,
  p_lng         numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ahora timestamptz := now();
  v_hoy text := to_char(timezone('America/Argentina/Buenos_Aires', now()), 'YYYY-MM-DD');
  v_productos jsonb;
  v_pagos jsonb;
  v_coords jsonb;
  v_suc jsonb;
  v_item jsonb;
  v_prod jsonb;
  v_cat text;
  v_cantidad integer;
  v_var_id text;
  v_var jsonb;
  v_var_snap jsonb;
  v_var_precio numeric;
  v_ad_ids jsonb;
  v_ad_id text;
  v_ad jsonb;
  v_ad_vistos text[];
  v_ad_snap jsonb;
  v_ad_total numeric;
  v_regular numeric;
  v_oferta numeric;
  v_base numeric;
  v_en_oferta boolean;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_unit numeric;
  v_subtotal numeric := 0;
  v_items_snap jsonb := '[]'::jsonb;
  v_pct numeric;
  v_descuento numeric;
  v_envio numeric := 0;
  v_zona text := null;
  v_zona_row public.zonas_envio%rowtype;
  v_mpc numeric;
  v_lat0 numeric;
  v_lng0 numeric;
  v_metros double precision;
  v_cuadras integer;
  v_costo_tramo numeric;
begin
  if coalesce(p_modalidad, '') not in ('delivery', 'retiro') then
    raise exception 'Esa modalidad de entrega no está disponible.';
  end if;

  select valor into v_coords from public.config_negocio where clave = 'sucursales_coords';
  v_suc := v_coords -> p_sucursal_id;
  if v_suc is null then
    raise exception 'La sucursal no existe.';
  end if;

  select contenido -> 'productos' into v_productos from public.carta where id = 1;
  if v_productos is null or jsonb_typeof(v_productos) <> 'array' then
    raise exception 'La carta no está disponible en este momento.';
  end if;

  select valor into v_pagos from public.config_negocio where clave = 'descuentos_pago';
  if v_pagos is null or jsonb_typeof(v_pagos -> p_metodo_pago) is distinct from 'number' then
    raise exception 'El medio de pago no es válido.';
  end if;
  v_pct := least(100, greatest(0, (v_pagos ->> p_metodo_pago)::numeric));

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'El pedido está vacío o tiene demasiados productos.';
  end if;

  for v_item in select e.value from jsonb_array_elements(p_items) as e(value) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Hay un producto inválido en el pedido.';
    end if;

    if coalesce(v_item ->> 'cantidad', '') !~ '^[0-9]{1,2}$' then
      raise exception 'Hay una cantidad inválida.';
    end if;
    v_cantidad := (v_item ->> 'cantidad')::integer;
    if v_cantidad < 1 or v_cantidad > 20 then
      raise exception 'Hay una cantidad inválida.';
    end if;

    select e.value into v_prod
      from jsonb_array_elements(v_productos) as e(value)
     where e.value ->> 'id' = (v_item ->> 'producto_id')
     limit 1;
    if v_prod is null then
      raise exception 'Un producto del pedido ya no existe en la carta.';
    end if;
    v_cat := coalesce(v_prod ->> 'categoria', '');

    if v_prod ->> 'agotado' = 'true'
       and (v_prod ->> 'agotado_hasta_nuevo_aviso' = 'true' or v_prod ->> 'agotado_fecha' = v_hoy) then
      raise exception '"%" está agotado.', v_prod ->> 'nombre';
    end if;

    -- Agotado manual para esta sucursal (independiente del agotado de la carta).
    if exists (
      select 1
      from public.agotados_sucursal a
      where a.producto_id = (v_prod ->> 'id')
        and a.sucursal_id = p_sucursal_id
    ) then
      raise exception '"%" está agotado en esta sucursal.', v_prod ->> 'nombre';
    end if;

    if not coalesce((v_prod -> 'sucursales') ? p_sucursal_id, false) then
      raise exception '"%" no está disponible en esta sucursal.', v_prod ->> 'nombre';
    end if;

    -- Precio regular (delivery y retiro usan el precio delivery, como la web)
    v_regular := null;
    if jsonb_typeof(v_prod -> 'precios' -> 'delivery') = 'number' then
      v_regular := (v_prod -> 'precios' ->> 'delivery')::numeric;
    elsif jsonb_typeof(v_prod -> 'precios' -> 'mesa') = 'number' then
      v_regular := (v_prod -> 'precios' ->> 'mesa')::numeric;
    end if;
    if v_regular is null or v_regular <= 0 then
      raise exception '"%" no tiene un precio válido.', v_prod ->> 'nombre';
    end if;

    -- Oferta: solo categoria promo, precio valido, menor al regular y vigente
    v_oferta := null;
    if jsonb_typeof(v_prod -> 'delivery_oferta') = 'number' then
      v_oferta := (v_prod ->> 'delivery_oferta')::numeric;
    elsif jsonb_typeof(v_prod -> 'mesa_oferta') = 'number' then
      v_oferta := (v_prod ->> 'mesa_oferta')::numeric;
    end if;
    v_desde := public.pm_ts_o_null(v_prod ->> 'oferta_desde');
    v_hasta := public.pm_ts_o_null(v_prod ->> 'oferta_hasta');
    v_base := v_regular;
    v_en_oferta := false;
    if v_oferta is not null and v_oferta > 0 and v_oferta < v_regular
       and (v_desde is null or v_ahora >= v_desde)
       and (v_hasta is null or v_ahora <= v_hasta) then
      v_base := v_oferta;
      v_en_oferta := true;
    end if;

    -- Opciones y adicionales
    v_var_id := nullif(btrim(coalesce(v_item ->> 'variacion_id', '')), '');
    v_ad_ids := coalesce(v_item -> 'adicionales_ids', '[]'::jsonb);
    if jsonb_typeof(v_ad_ids) <> 'array' or jsonb_array_length(v_ad_ids) > 10 then
      raise exception 'Los adicionales de "%" no son válidos.', v_prod ->> 'nombre';
    end if;

    if v_cat in ('promo', 'pizza')
       and (v_var_id is not null or jsonb_array_length(v_ad_ids) > 0) then
      raise exception '"%" no admite opciones ni adicionales.', v_prod ->> 'nombre';
    end if;
    if v_cat in ('lomo', 'milanesa') and jsonb_array_length(v_ad_ids) > 0 then
      raise exception '"%" no admite adicionales.', v_prod ->> 'nombre';
    end if;

    v_var := null;
    v_var_snap := null;
    v_var_precio := 0;
    if jsonb_typeof(v_prod -> 'variaciones' -> 'opciones') = 'array'
       and jsonb_array_length(v_prod -> 'variaciones' -> 'opciones') > 0
       and v_cat not in ('promo', 'pizza') then
      if v_var_id is null then
        if v_prod -> 'variaciones' ->> 'obligatorio' = 'true' then
          raise exception 'Falta elegir una opción para "%".', v_prod ->> 'nombre';
        end if;
      else
        select e.value into v_var
          from jsonb_array_elements(v_prod -> 'variaciones' -> 'opciones') as e(value)
         where e.value ->> 'id' = v_var_id
         limit 1;
        if v_var is null then
          raise exception 'La opción elegida de "%" ya no está disponible.', v_prod ->> 'nombre';
        end if;
        v_var_precio := coalesce((v_var ->> 'precio')::numeric, 0);
        v_var_snap := jsonb_build_object(
          'id', v_var ->> 'id', 'nombre', v_var ->> 'nombre', 'precio', v_var_precio);
      end if;
    elsif v_var_id is not null then
      raise exception '"%" no admite opciones.', v_prod ->> 'nombre';
    end if;

    v_ad_total := 0;
    v_ad_snap := '[]'::jsonb;
    v_ad_vistos := '{}';
    for v_ad_id in select e.value from jsonb_array_elements_text(v_ad_ids) as e(value) loop
      if v_ad_id = any(v_ad_vistos) then
        raise exception 'Hay un adicional repetido.';
      end if;
      v_ad_vistos := v_ad_vistos || v_ad_id;

      select e.value into v_ad
        from jsonb_array_elements(
               case when jsonb_typeof(v_prod -> 'adicionales') = 'array'
                    then v_prod -> 'adicionales' else '[]'::jsonb end
             ) as e(value)
       where e.value ->> 'id' = v_ad_id
       limit 1;
      if v_ad is null then
        raise exception 'Un adicional de "%" ya no está disponible.', v_prod ->> 'nombre';
      end if;
      v_ad_total := v_ad_total + coalesce((v_ad ->> 'precio')::numeric, 0);
      v_ad_snap := v_ad_snap || jsonb_build_array(jsonb_build_object(
        'id', v_ad ->> 'id', 'nombre', v_ad ->> 'nombre',
        'precio', coalesce((v_ad ->> 'precio')::numeric, 0)));
    end loop;

    v_unit := v_base + v_var_precio + v_ad_total;
    v_subtotal := v_subtotal + v_unit * v_cantidad;
    v_items_snap := v_items_snap || jsonb_build_array(jsonb_build_object(
      'producto_id', v_prod ->> 'id',
      'nombre', v_prod ->> 'nombre',
      'categoria', v_cat,
      'precio_regular', v_regular,
      'precio_base', v_base,
      'en_oferta', v_en_oferta,
      'variacion', v_var_snap,
      'adicionales', v_ad_snap,
      'cantidad', v_cantidad,
      'precio_unitario', v_unit,
      'subtotal', v_unit * v_cantidad));
  end loop;

  -- El descuento por medio de pago se aplica SOLO a los productos
  v_descuento := round(v_subtotal * v_pct / 100);

  -- Envio
  if p_modalidad = 'delivery' then
    v_zona := coalesce(nullif(btrim(p_zona_envio), ''), 'Zona normal');

    select z.* into v_zona_row
      from public.zonas_envio z
     where z.activa
       and lower(z.nombre) = lower(v_zona)
       and (z.sucursal_id = p_sucursal_id or z.sucursal_id is null)
     order by (z.sucursal_id is null), z.orden
     limit 1;
    if not found then
      raise exception 'La zona de envío elegida no existe.';
    end if;
    v_zona := v_zona_row.nombre;
    v_envio := v_zona_row.costo;

    -- Tramos por cuadras (distancia en linea recta, redondeada hacia arriba)
    if v_zona_row.aplica_tramos and p_lat is not null and p_lng is not null
       and exists (
         select 1 from public.tramos_envio t
          where t.activa and (t.sucursal_id = p_sucursal_id or t.sucursal_id is null)
       ) then
      v_lat0 := (v_suc ->> 'lat')::numeric;
      v_lng0 := (v_suc ->> 'lng')::numeric;
      select coalesce(nullif(c.valor #>> '{}', '')::numeric, 100) into v_mpc
        from public.config_negocio c where c.clave = 'metros_por_cuadra';
      if v_mpc is null or v_mpc <= 0 then v_mpc := 100; end if;

      v_metros := 2 * 6371000 * asin(sqrt(least(1,
          power(sin(radians(p_lat - v_lat0) / 2), 2)
        + cos(radians(v_lat0)) * cos(radians(p_lat))
          * power(sin(radians(p_lng - v_lng0) / 2), 2))));
      v_cuadras := ceil(v_metros / v_mpc::double precision)::integer;

      select t.costo into v_costo_tramo
        from public.tramos_envio t
       where t.activa
         and (t.sucursal_id = p_sucursal_id or t.sucursal_id is null)
         and v_cuadras between t.desde_cuadras and t.hasta_cuadras
       order by (t.sucursal_id is null), t.desde_cuadras
       limit 1;
      if found then
        v_envio := v_costo_tramo;
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'items', v_items_snap,
    'subtotal', v_subtotal,
    'descuento', v_descuento,
    'costo_envio', v_envio,
    'total', v_subtotal - v_descuento + v_envio,
    'zona_envio', v_zona,
    'porcentaje_pago', v_pct);
end;
$$;

revoke all on function public.pm_calcular_pedido(text, text, text, jsonb, text, numeric, numeric)
  from public, anon, authenticated;

comment on function public.pm_calcular_pedido(text, text, text, jsonb, text, numeric, numeric) is
  'Calcula el pedido en el servidor. Rechaza productos agotados para la sucursal.';

-- crear_pedido no se redefine: su firma no cambia y sigue llamando a
-- pm_calcular_pedido(...). Verificar despues de aplicar que siga con permisos
-- para anon y authenticated.

-- ----------------------------------------------------------------------------
-- 9. Verificacion final: debe existir al menos un dueno
-- ----------------------------------------------------------------------------
do $$
declare
  v_duenos integer;
begin
  select count(*) into v_duenos
    from public.admins
   where rol = 'dueno';

  if v_duenos < 1 then
    raise exception 'La migracion 017 no puede quedar sin ningun admin con rol dueno.';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 10. Casos de prueba (comentados, ejecutar a mano en un entorno de prueba)
-- ----------------------------------------------------------------------------
-- Dueno ve todo:
--   set local role authenticated;
--   set local request.jwt.claims = '{"email":"EMAIL_DUENO"}';
--   select sucursal_id, count(*) from public.pedidos group by sucursal_id;
--   -- Debe devolver pedidos de ambas sucursales.
--
-- Admin Lascano no ve ni actualiza pedidos de Maestro Quiroga:
--   set local role authenticated;
--   set local request.jwt.claims = '{"email":"EMAIL_LASCANO"}';
--   select id, sucursal_id from public.pedidos;
--   -- Solo debe devolver intendente-lascano.
--   update public.pedidos set estado = 'confirmado'
--    where sucursal_id = 'maestro-quiroga' returning id;
--   -- Debe afectar 0 filas.
--
-- Admin de sucursal no edita la carta ni config_negocio ni Storage:
--   set local role authenticated;
--   set local request.jwt.claims = '{"email":"EMAIL_LASCANO"}';
--   update public.carta set contenido = contenido where id = 1;
--   update public.config_negocio set valor = valor where clave = 'metros_por_cuadra';
--   -- Ambas deben fallar por RLS.
--
-- Admin de sucursal no crea admins ni cambia su sucursal_id:
--   set local role authenticated;
--   set local request.jwt.claims = '{"email":"EMAIL_LASCANO"}';
--   insert into public.admins (email, rol, sucursal_id)
--   values ('otro@ejemplo.com', 'sucursal', 'maestro-quiroga');
--   update public.admins set sucursal_id = 'maestro-quiroga'
--    where email = 'EMAIL_LASCANO';
--   -- Ambas deben fallar por falta de permisos.
--
-- Agotado por sucursal:
--   insert into public.agotados_sucursal (producto_id, sucursal_id)
--   values ('PRODUCTO_ID', 'intendente-lascano');
--   select public.carta_por_sucursal('intendente-lascano');
--   -- El producto debe aparecer con agotado = true y
--   -- agotado_hasta_nuevo_aviso = true.
--   select public.crear_pedido(...); -- pedido de Lascano: debe fallar
--   select public.crear_pedido(...); -- mismo producto en Maestro Quiroga: debe pasar
--
-- anon no accede a pedidos, clientes, admins ni agotados:
--   set local role anon;
--   select * from public.pedidos;       -- 401 / sin permisos
--   select * from public.clientes;      -- 401 / sin permisos
--   select * from public.admins;        -- 401 / sin permisos
--   select * from public.agotados_sucursal; -- 401 / sin permisos

-- ----------------------------------------------------------------------------
-- 11. Rollback manual (comentado; no ejecutar sin backup)
-- ----------------------------------------------------------------------------
-- begin;
--   -- Restaurar politicas anteriores de 001/011 si se desea volver atras.
--   drop policy if exists "Agotados lectura admin" on public.agotados_sucursal;
--   drop policy if exists "Agotados alta admin" on public.agotados_sucursal;
--   drop policy if exists "Agotados edicion admin" on public.agotados_sucursal;
--   drop policy if exists "Agotados baja admin" on public.agotados_sucursal;
--   drop table if exists public.agotados_sucursal;
--   drop function if exists public.carta_por_sucursal(text);
--
--   -- Recrear pm_calcular_pedido desde 013 + 014 + 015 (sin el chequeo de agotados).
--   -- Ver 013_crear_pedido.sql, 014_ofertas_todas_las_categorias.sql y 015_envio_por_distancia.sql.
--
--   -- Volver las politicas de carta, config y storage a public.es_admin().
--   -- Volver las politicas de pedidos, zonas y tramos a public.es_admin().
--   -- Revocar ejecucion de es_dueno() y sucursal_admin().
--   drop function if exists public.sucursal_admin();
--   drop function if exists public.es_dueno();
--
--   alter table public.admins drop constraint if exists admins_rol_sucursal_chk;
--   alter table public.admins drop constraint if exists admins_rol_chk;
--   drop index if exists public.admins_sucursal_id_idx;
--   alter table public.admins drop column if exists sucursal_id;
--   alter table public.admins drop column if exists rol;
-- commit;
