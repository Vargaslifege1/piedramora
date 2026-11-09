-- ============================================================================
-- Piedra Mora - Fase 3A - Cupones en base de datos y RPC
-- Migracion 018
-- ============================================================================
-- IMPORTANTE: hacer backup completo de la base antes de aplicarla.
--
-- Requisitos:
--   - 010, 011 (pedidos, clientes, configuracion y RLS base)
--   - 013 (crear_pedido y pm_calcular_pedido)
--   - 014, 015 (ofertas en todas las categorias y envio por distancia)
--   - 016 (estados y pagos; ya aplicada en la base real)
--   - 017 (es_dueno, agotados por sucursal y pm_calcular_pedido definitiva)
--
-- Objetivo:
--   1. Crear las tablas cupones, cupon_usos y cupon_intentos.
--   2. Aplicar RLS: cupones y cupon_usos solo para el dueno; los intentos
--      no tienen acceso ni para anon ni para authenticated.
--   3. Crear valida_cupon() para que el checkout pueda validar un cupon.
--   4. Recrear crear_pedido() con el parametro opcional p_cupon y la regla
--      de beneficio unico (opcion A: gana el mayor descuento en pesos).
--   5. Agregar pedidos.cupon_codigo y pedidos.descuento_cupon.
--
-- Reglas importantes:
--   - No se toca pm_calcular_pedido(): la version vigente es la de 017.
--   - El descuento del cupon se calcula sobre el subtotal de productos, sin
--     envio, y nunca supera el subtotal.
--   - Los montos fijos se redondean a enteros.
--   - Si el cupon no es acumulable y el descuento por medio de pago es mayor,
--     gana el medio de pago y el cupon NO se consume ni se registra.
--   - Los usos se cuentan con join a pedidos y excluyendo pedidos cancelados.
--   - El telefono se normaliza igual que en 013 (solo digitos, 8 a 15).
--   - "No existe" y "pausado/inactivo" devuelven el mismo mensaje generico.
--
-- Idempotente: se puede ejecutar varias veces sin perder datos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tablas
-- ----------------------------------------------------------------------------
create table if not exists public.cupones (
  id uuid primary key default gen_random_uuid(),

  -- Se guarda normalizado: mayusculas y sin espacios externos.
  codigo text not null,

  tipo text not null,
  valor numeric(12, 2) not null,

  activo boolean not null default true,

  fecha_inicio timestamptz,
  fecha_vencimiento timestamptz,

  -- null = sin limite.
  usos_maximos_total integer,
  usos_por_cliente integer,

  compra_minima numeric(12, 2) not null default 0,
  primera_compra boolean not null default false,

  -- null = vale para todas las sucursales / modalidades.
  sucursales_permitidas text[],
  modalidades_permitidas text[],

  acumulable_con_pago boolean not null default false,

  creado_en timestamptz not null default now(),

  constraint cupones_codigo_normalizado_chk
    check (codigo = upper(btrim(codigo))),
  constraint cupones_codigo_largo_chk
    check (char_length(codigo) between 1 and 40),

  constraint cupones_tipo_chk
    check (tipo in ('porcentaje', 'monto_fijo')),
  constraint cupones_valor_chk
    check (valor > 0),
  constraint cupones_valor_porcentaje_chk
    check (tipo <> 'porcentaje' or valor <= 100),

  constraint cupones_fechas_chk
    check (
      fecha_inicio is null
      or fecha_vencimiento is null
      or fecha_vencimiento >= fecha_inicio
    ),

  constraint cupones_usos_total_chk
    check (usos_maximos_total is null or usos_maximos_total >= 0),
  constraint cupones_usos_cliente_chk
    check (usos_por_cliente is null or usos_por_cliente >= 0),

  constraint cupones_compra_minima_chk
    check (compra_minima >= 0),

  constraint cupones_modalidades_chk
    check (
      modalidades_permitidas is null
      or modalidades_permitidas <@ array['delivery', 'retiro']::text[]
    ),
  constraint cupones_sucursales_chk
    check (
      sucursales_permitidas is null
      or sucursales_permitidas <@ array['maestro-quiroga', 'intendente-lascano']::text[]
    )
);

-- La busqueda se hace con upper(btrim(...)), pero el codigo ya se guarda
-- normalizado, asi que el unique simple alcanza para evitar duplicados.
create unique index if not exists cupones_codigo_uidx
  on public.cupones (codigo);

comment on table public.cupones is
  'Cupones de descuento. El codigo se guarda en mayusculas y sin espacios externos.';
comment on column public.cupones.tipo is
  'porcentaje = valor es un porcentaje; monto_fijo = valor son pesos.';
comment on column public.cupones.sucursales_permitidas is
  'null = todas las sucursales.';
comment on column public.cupones.modalidades_permitidas is
  'null = todas las modalidades. Valores validos: delivery y retiro.';

create table if not exists public.cupon_usos (
  id uuid primary key default gen_random_uuid(),

  cupon_id uuid not null
    references public.cupones (id) on delete restrict,

  telefono text not null,
  pedido_id uuid not null
    references public.pedidos (id) on delete cascade,

  monto_descontado numeric(12, 2) not null default 0,
  fecha timestamptz not null default now(),

  constraint cupon_usos_telefono_chk
    check (telefono ~ '^[0-9]{8,15}$'),
  constraint cupon_usos_monto_chk
    check (monto_descontado >= 0)
);

create index if not exists cupon_usos_cupon_id_idx
  on public.cupon_usos (cupon_id);
create index if not exists cupon_usos_telefono_idx
  on public.cupon_usos (telefono);
-- Un pedido solo puede tener un cupon asociado.
create unique index if not exists cupon_usos_pedido_id_uidx
  on public.cupon_usos (pedido_id);

comment on table public.cupon_usos is
  'Uso efectivo de un cupon. Solo se registra si el cupon aporto descuento.';

-- Registro interno para el limite anti-spam de valida_cupon.
-- No tiene acceso para anon ni authenticated: solo lo usan las funciones
-- security definer. Los intentos de mas de 1 dia se limpian dentro de la RPC.
create table if not exists public.cupon_intentos (
  id bigint generated by default as identity primary key,

  telefono text,
  ip text,
  codigo text,
  creado_en timestamptz not null default now(),

  constraint cupon_intentos_telefono_chk
    check (telefono is null or telefono ~ '^[0-9]{8,15}$'),
  constraint cupon_intentos_ip_largo_chk
    check (ip is null or char_length(ip) <= 100)
);

create index if not exists cupon_intentos_telefono_fecha_idx
  on public.cupon_intentos (telefono, creado_en desc);
create index if not exists cupon_intentos_ip_fecha_idx
  on public.cupon_intentos (ip, creado_en desc);
create index if not exists cupon_intentos_fecha_idx
  on public.cupon_intentos (creado_en desc);

comment on table public.cupon_intentos is
  'Intentos de validacion de cupones para el limite anti-spam. Sin acceso publico.';

-- ----------------------------------------------------------------------------
-- 2. RLS y permisos de las tablas
-- ----------------------------------------------------------------------------
alter table public.cupones enable row level security;
alter table public.cupon_usos enable row level security;
alter table public.cupon_intentos enable row level security;

revoke all on public.cupones from public, anon, authenticated;
revoke all on public.cupon_usos from public, anon, authenticated;
revoke all on public.cupon_intentos from public, anon, authenticated;

-- El dueno administra cupones y consulta usos. El admin de sucursal no.
grant select, insert, update, delete on public.cupones to authenticated;
grant select, insert, update, delete on public.cupon_usos to authenticated;

drop policy if exists "Cupones lectura dueno" on public.cupones;
create policy "Cupones lectura dueno"
  on public.cupones
  for select
  to authenticated
  using (public.es_dueno());

drop policy if exists "Cupones alta dueno" on public.cupones;
create policy "Cupones alta dueno"
  on public.cupones
  for insert
  to authenticated
  with check (public.es_dueno());

drop policy if exists "Cupones edicion dueno" on public.cupones;
create policy "Cupones edicion dueno"
  on public.cupones
  for update
  to authenticated
  using (public.es_dueno())
  with check (public.es_dueno());

drop policy if exists "Cupones baja dueno" on public.cupones;
create policy "Cupones baja dueno"
  on public.cupones
  for delete
  to authenticated
  using (public.es_dueno());

drop policy if exists "Cupon usos lectura dueno" on public.cupon_usos;
create policy "Cupon usos lectura dueno"
  on public.cupon_usos
  for select
  to authenticated
  using (public.es_dueno());

drop policy if exists "Cupon usos alta dueno" on public.cupon_usos;
create policy "Cupon usos alta dueno"
  on public.cupon_usos
  for insert
  to authenticated
  with check (public.es_dueno());

drop policy if exists "Cupon usos edicion dueno" on public.cupon_usos;
create policy "Cupon usos edicion dueno"
  on public.cupon_usos
  for update
  to authenticated
  using (public.es_dueno())
  with check (public.es_dueno());

drop policy if exists "Cupon usos baja dueno" on public.cupon_usos;
create policy "Cupon usos baja dueno"
  on public.cupon_usos
  for delete
  to authenticated
  using (public.es_dueno());

-- cupon_intentos queda con RLS activo y sin policies ni grants:
-- nadie fuera del dueno de las funciones puede leerlo ni escribirlo.

-- ----------------------------------------------------------------------------
-- 3. Columnas de cupon en pedidos
-- ----------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists cupon_codigo text;

alter table public.pedidos
  add column if not exists descuento_cupon numeric(12, 2) not null default 0;

comment on column public.pedidos.cupon_codigo is
  'Codigo del cupon aplicado. null si no se uso cupon.';
comment on column public.pedidos.descuento_cupon is
  'Descuento aportado por el cupon. 0 si gano el descuento por medio de pago.';

-- Lectura de las columnas nuevas para el admin autenticado.
-- No se modifica el grant por columnas de UPDATE de pedidos.
grant select (cupon_codigo, descuento_cupon) on public.pedidos to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Seed del cupon LICHI
-- ----------------------------------------------------------------------------
insert into public.cupones (
  codigo, tipo, valor, activo, compra_minima, primera_compra,
  sucursales_permitidas, modalidades_permitidas, acumulable_con_pago
)
values (
  'LICHI', 'porcentaje', 10, true, 0, false,
  null, null, false
)
on conflict (codigo) do nothing;

-- ----------------------------------------------------------------------------
-- 5. Validacion interna y publica de cupones
-- ----------------------------------------------------------------------------
-- Devuelve tambien datos internos (cupon_id y acumulable) para que
-- crear_pedido los use. valida_cupon() los recorta antes de responder.
create or replace function public.pm_validar_cupon(
  p_codigo      text,
  p_telefono    text,
  p_subtotal    numeric,
  p_sucursal_id text,
  p_modalidad   text,
  p_bloquear    boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_codigo text;
  v_tel text;
  v_cupon public.cupones%rowtype;
  v_subtotal numeric;
  v_descuento numeric := 0;
  v_usos_total integer := 0;
  v_usos_cliente integer := 0;
  v_pedidos_previos integer := 0;
begin
  v_codigo := upper(btrim(coalesce(p_codigo, '')));
  if v_codigo = '' then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'El cupón no es válido.');
  end if;

  -- Misma normalizacion de telefono que usa crear_pedido desde 013.
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  if v_tel !~ '^[0-9]{8,15}$' then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'El teléfono no es válido.');
  end if;

  v_subtotal := greatest(coalesce(p_subtotal, 0), 0);

  -- El bloqueo se usa desde crear_pedido para evitar carreras con
  -- usos_maximos_total y usos_por_cliente.
  if p_bloquear then
    select * into v_cupon
      from public.cupones
     where codigo = v_codigo
     for update;
  else
    select * into v_cupon
      from public.cupones
     where codigo = v_codigo;
  end if;

  -- Mismo mensaje para codigo inexistente e inactivo/pausado.
  if v_cupon.id is null or v_cupon.activo is not true then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'El cupón no es válido.');
  end if;

  if v_cupon.fecha_inicio is not null and now() < v_cupon.fecha_inicio then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón todavía no está vigente.');
  end if;

  if v_cupon.fecha_vencimiento is not null and now() > v_cupon.fecha_vencimiento then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'Este cupón está vencido.');
  end if;

  if v_cupon.modalidades_permitidas is not null
     and (
       p_modalidad is null
       or not (p_modalidad = any (v_cupon.modalidades_permitidas))
     ) then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón no es válido para esta modalidad de entrega.');
  end if;

  if v_cupon.sucursales_permitidas is not null
     and (
       p_sucursal_id is null
       or not (p_sucursal_id = any (v_cupon.sucursales_permitidas))
     ) then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón no es válido para esta sucursal.');
  end if;

  if v_cupon.primera_compra then
    select count(*) into v_pedidos_previos
      from public.pedidos p
     where p.cliente_telefono = v_tel
       and p.estado <> 'cancelado'
       and p.sincronizado is distinct from false;

    if v_pedidos_previos > 0 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Este cupón es solo para la primera compra.');
    end if;
  end if;

  if v_subtotal < v_cupon.compra_minima then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', format(
        'El mínimo de compra es $%s; te faltan $%s.',
        replace(trim(to_char(round(v_cupon.compra_minima), 'FM999,999,999,999')), ',', '.'),
        replace(trim(to_char(round(v_cupon.compra_minima - v_subtotal), 'FM999,999,999,999')), ',', '.')));
  end if;

  -- Usos validos: solo pedidos que no estan cancelados.
  select count(*) into v_usos_total
    from public.cupon_usos u
    join public.pedidos p on p.id = u.pedido_id
   where u.cupon_id = v_cupon.id
     and p.estado <> 'cancelado';

  if v_cupon.usos_maximos_total is not null
     and v_usos_total >= v_cupon.usos_maximos_total then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón ya no tiene usos disponibles.');
  end if;

  select count(*) into v_usos_cliente
    from public.cupon_usos u
    join public.pedidos p on p.id = u.pedido_id
   where u.cupon_id = v_cupon.id
     and u.telefono = v_tel
     and p.estado <> 'cancelado';

  if v_cupon.usos_por_cliente is not null
     and v_usos_cliente >= v_cupon.usos_por_cliente then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Ya usaste este cupón.');
  end if;

  if v_cupon.tipo = 'porcentaje' then
    v_descuento := round(v_subtotal * v_cupon.valor / 100);
  else
    v_descuento := round(v_cupon.valor);
  end if;

  v_descuento := least(greatest(v_descuento, 0), v_subtotal);

  return jsonb_build_object(
    'ok', true,
    'descuento', v_descuento,
    'mensaje', 'Cupón aplicado.',
    'cupon_id', v_cupon.id,
    'acumulable', v_cupon.acumulable_con_pago);
end;
$$;

revoke all on function public.pm_validar_cupon(text, text, numeric, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.valida_cupon(
  p_codigo      text,
  p_telefono    text,
  p_subtotal    numeric,
  p_sucursal_id text,
  p_modalidad   text,
  p_metodo_pago text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ip text;
  v_tel text;
  v_intentos_tel integer := 0;
  v_intentos_ip integer := 0;
  v_intentos_global integer := 0;
  v_subtotal numeric;
  v_res jsonb;
  v_desc_cupon numeric := 0;
  v_desc_pago numeric := 0;
  v_pagos jsonb;
  v_pct numeric := 0;
begin
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_subtotal := greatest(coalesce(p_subtotal, 0), 0);

  -- IP del pedido (detras del proxy de Supabase).
  begin
    v_ip := nullif(btrim(split_part(
      coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''),
      ',', 1)), '');
    if v_ip is null then
      v_ip := nullif(btrim(
        current_setting('request.headers', true)::jsonb ->> 'x-real-ip'), '');
    end if;
  exception when others then
    v_ip := null;
  end;

  -- Limpieza de intentos de mas de 1 dia.
  delete from public.cupon_intentos
   where creado_en < now() - interval '1 day';

  -- Limite anti-spam con los mismos umbrales base que crear_pedido,
  -- mas un limite por IP.
  if v_tel ~ '^[0-9]{8,15}$' then
    select count(*) into v_intentos_tel
      from public.cupon_intentos
     where telefono = v_tel
       and creado_en > now() - interval '10 minutes';

    if v_intentos_tel >= 5 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Hiciste varios intentos seguidos. Esperá unos minutos.');
    end if;
  end if;

  if v_ip is not null then
    select count(*) into v_intentos_ip
      from public.cupon_intentos
     where ip = v_ip
       and creado_en > now() - interval '10 minutes';

    if v_intentos_ip >= 20 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Hiciste varios intentos seguidos. Esperá unos minutos.');
    end if;
  end if;

  select count(*) into v_intentos_global
    from public.cupon_intentos
   where creado_en > now() - interval '5 minutes';

  if v_intentos_global >= 40 then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Hay muchos intentos en este momento. Esperá unos minutos.');
  end if;

  insert into public.cupon_intentos (telefono, ip, codigo)
  values (
    case when v_tel ~ '^[0-9]{8,15}$' then v_tel else null end,
    v_ip,
    left(upper(btrim(coalesce(p_codigo, ''))), 40)
  );

  v_res := public.pm_validar_cupon(
    p_codigo, p_telefono, v_subtotal, p_sucursal_id, p_modalidad, false);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'descuento', 0,
      'mensaje', v_res ->> 'mensaje');
  end if;

  v_desc_cupon := coalesce((v_res ->> 'descuento')::numeric, 0);

  -- Descuento por medio de pago, con la misma formula que pm_calcular_pedido.
  select valor into v_pagos
    from public.config_negocio
   where clave = 'descuentos_pago';

  if v_pagos is not null
     and jsonb_typeof(v_pagos -> p_metodo_pago) = 'number' then
    v_pct := least(100, greatest(0, (v_pagos ->> p_metodo_pago)::numeric));
  end if;

  v_desc_pago := round(v_subtotal * v_pct / 100);

  -- Regla de beneficio unico (opcion A).
  if coalesce((v_res ->> 'acumulable')::boolean, false) then
    return jsonb_build_object(
      'ok', true,
      'descuento', least(v_subtotal, v_desc_cupon),
      'mensaje', 'Cupón aplicado.');
  end if;

  if v_desc_cupon >= v_desc_pago then
    return jsonb_build_object(
      'ok', true,
      'descuento', least(v_subtotal, v_desc_cupon),
      'mensaje', 'Cupón aplicado.');
  end if;

  return jsonb_build_object(
    'ok', false,
    'descuento', 0,
    'mensaje', 'Con ese medio de pago ya tenés un descuento mayor; el cupón no se aplica.');
end;
$$;

revoke all on function public.valida_cupon(text, text, numeric, text, text, text)
  from public, anon, authenticated;
grant execute on function public.valida_cupon(text, text, numeric, text, text, text)
  to anon, authenticated;

comment on function public.valida_cupon(text, text, numeric, text, text, text) is
  'Valida un cupon y devuelve solo {ok, descuento, mensaje}. No expone datos del cupon.';

-- ----------------------------------------------------------------------------
-- 6. crear_pedido con cupon
-- ----------------------------------------------------------------------------
-- La firma cambia al agregar p_cupon. Se elimina la firma anterior de 12
-- argumentos para que PostgREST no vea dos funciones ambiguas.
drop function if exists public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid);

create or replace function public.crear_pedido(
  p_sucursal_id      text,
  p_modalidad        text,
  p_metodo_pago      text,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_items            jsonb,
  p_direccion        text default null,
  p_lat              numeric default null,
  p_lng              numeric default null,
  p_zona_envio       text default null,
  p_notas            text default null,
  p_idempotency_key  uuid default null,
  p_cupon            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ped public.pedidos%rowtype;
  v_calc jsonb;
  v_nombre text;
  v_tel text;
  v_dir text;
  v_notas text;
  v_lat numeric := p_lat;
  v_lng numeric := p_lng;

  v_codigo text;
  v_cupon_res jsonb;
  v_subtotal numeric := 0;
  v_envio numeric := 0;
  v_desc_pago numeric := 0;
  v_desc_cupon numeric := 0;
  v_desc_final numeric := 0;
  v_cupon_aplicado boolean := false;
  v_acumulable boolean := false;
  v_total numeric := 0;
begin
  -- Reintento del mismo pedido: devuelve el que ya existe
  if p_idempotency_key is not null then
    select * into v_ped from public.pedidos where idempotency_key = p_idempotency_key;
    if found then
      return public.pm_pedido_resultado(v_ped);
    end if;
  end if;

  v_nombre := btrim(coalesce(p_cliente_nombre, ''));
  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then
    raise exception 'Ingresá tu nombre.';
  end if;

  v_tel := regexp_replace(coalesce(p_cliente_telefono, ''), '\D', '', 'g');
  if v_tel !~ '^[0-9]{8,15}$' then
    raise exception 'El teléfono no es válido.';
  end if;

  if p_modalidad = 'delivery' then
    v_dir := btrim(coalesce(p_direccion, ''));
    if char_length(v_dir) < 5 or char_length(v_dir) > 300 then
      raise exception 'Falta la dirección de entrega.';
    end if;
    if (v_lat is null) <> (v_lng is null)
       or v_lat not between -90 and 90 or v_lng not between -180 and 180 then
      v_lat := null;
      v_lng := null;
    end if;
  else
    v_dir := null;
    v_lat := null;
    v_lng := null;
  end if;

  v_notas := left(btrim(coalesce(p_notas, '')), 500);

  -- Anti-spam (ajustable): por telefono y global
  if (select count(*) from public.pedidos
       where cliente_telefono = v_tel and created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'Hiciste varios pedidos seguidos. Esperá unos minutos o escribinos por WhatsApp.';
  end if;
  if (select count(*) from public.pedidos
       where created_at > now() - interval '5 minutes') >= 40 then
    raise exception 'Hay muchos pedidos en este momento. Escribinos por WhatsApp.';
  end if;

  v_calc := public.pm_calcular_pedido(
    p_sucursal_id, p_modalidad, p_metodo_pago, p_items, p_zona_envio, v_lat, v_lng);

  v_subtotal := coalesce((v_calc ->> 'subtotal')::numeric, 0);
  v_envio := coalesce((v_calc ->> 'costo_envio')::numeric, 0);
  v_desc_pago := coalesce((v_calc ->> 'descuento')::numeric, 0);
  v_desc_final := v_desc_pago;

  -- Re-validacion del cupon dentro de la misma transaccion.
  -- Se ignora cualquier descuento que venga del cliente.
  v_codigo := upper(btrim(coalesce(p_cupon, '')));

  if v_codigo <> '' then
    v_cupon_res := public.pm_validar_cupon(
      v_codigo, v_tel, v_subtotal, p_sucursal_id, p_modalidad, true);

    if not coalesce((v_cupon_res ->> 'ok')::boolean, false) then
      raise exception '%', v_cupon_res ->> 'mensaje';
    end if;

    v_desc_cupon := coalesce((v_cupon_res ->> 'descuento')::numeric, 0);
    v_acumulable := coalesce((v_cupon_res ->> 'acumulable')::boolean, false);

    if v_acumulable then
      -- Se suman, pero el cupon nunca descuenta mas que lo que queda
      -- despues del descuento por medio de pago.
      v_desc_cupon := least(v_desc_cupon, greatest(v_subtotal - v_desc_pago, 0));
      v_desc_final := v_desc_pago + v_desc_cupon;
      v_cupon_aplicado := v_desc_cupon > 0;
    elsif v_desc_cupon >= v_desc_pago then
      -- Gana el cupon.
      v_desc_final := v_desc_cupon;
      v_cupon_aplicado := v_desc_cupon > 0;
    else
      -- Gana el medio de pago: el cupon no se consume ni se registra.
      v_desc_cupon := 0;
      v_desc_final := v_desc_pago;
      v_cupon_aplicado := false;
    end if;

    v_desc_final := least(v_desc_final, v_subtotal);
  end if;

  v_total := v_subtotal - v_desc_final + v_envio;

  begin
    insert into public.pedidos (
      sucursal_id, modalidad, cliente_nombre, cliente_telefono,
      direccion, lat, lng, zona_envio, items_snapshot,
      subtotal, descuento, costo_envio, total,
      metodo_pago, idempotency_key, notas,
      cupon_codigo, descuento_cupon
    ) values (
      p_sucursal_id, p_modalidad, v_nombre, v_tel,
      v_dir, v_lat, v_lng, v_calc ->> 'zona_envio', v_calc -> 'items',
      v_subtotal, v_desc_final, v_envio, v_total,
      p_metodo_pago, p_idempotency_key, nullif(v_notas, ''),
      case when v_cupon_aplicado then v_codigo else null end,
      case when v_cupon_aplicado then v_desc_cupon else 0 end
    )
    returning * into v_ped;
  exception when unique_violation then
    if p_idempotency_key is not null then
      select * into v_ped from public.pedidos where idempotency_key = p_idempotency_key;
      if found then
        return public.pm_pedido_resultado(v_ped);
      end if;
    end if;
    raise;
  end;

  -- Registrar el uso en la misma transaccion. La fila del cupon quedo
  -- bloqueada con FOR UPDATE hasta el commit, lo que serializa usos
  -- simultaneos sobre el mismo codigo.
  if v_cupon_aplicado then
    insert into public.cupon_usos (
      cupon_id, telefono, pedido_id, monto_descontado
    ) values (
      (v_cupon_res ->> 'cupon_id')::uuid,
      v_tel,
      v_ped.id,
      v_desc_cupon
    );
  end if;

  return public.pm_pedido_resultado(v_ped);
end;
$$;

-- Permisos de crear_pedido: exactamente como en 013, para la nueva firma.
revoke all on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text)
  from public;
grant execute on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text)
  to anon, authenticated;

comment on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text) is
  'Crea un pedido validando precios y cupon en el servidor. Ignora descuentos del cliente.';

-- ----------------------------------------------------------------------------
-- 7. Casos de prueba (comentados; ejecutar a mano en un entorno de prueba)
-- ----------------------------------------------------------------------------
-- Nota: reemplazar TELEFONO, SUCURSAL y METODO por datos reales.
--
-- Cupon valido:
--   select public.valida_cupon('LICHI', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = true, descuento = 1000.
--
-- Codigo inexistente y cupon pausado devuelven el mismo mensaje:
--   select public.valida_cupon('NOEXISTE', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   update public.cupones set activo = false where codigo = 'LICHI';
--   select public.valida_cupon('LICHI', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- Ambos: ok = false, mensaje = 'El cupón no es válido.'
--   update public.cupones set activo = true where codigo = 'LICHI';
--
-- Vencido:
--   update public.cupones
--      set fecha_vencimiento = now() - interval '1 day'
--    where codigo = 'LICHI';
--   select public.valida_cupon('LICHI', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = false, mensaje = 'Este cupón está vencido.'
--
-- Mínimo no alcanzado:
--   update public.cupones set compra_minima = 20000 where codigo = 'LICHI';
--   select public.valida_cupon('LICHI', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = false, mensaje con el mínimo y cuánto falta.
--
-- Otro teléfono (usos por cliente):
--   update public.cupones set usos_por_cliente = 1 where codigo = 'LICHI';
--   -- Con un pedido previo del mismo telefono:
--   select public.valida_cupon('LICHI', 'TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = false, mensaje = 'Ya usaste este cupón.'
--
-- Primera compra:
--   update public.cupones
--      set usos_por_cliente = null, primera_compra = true
--    where codigo = 'LICHI';
--   select public.valida_cupon('LICHI', 'TELEFONO_CON_PEDIDOS', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = false, mensaje = 'Este cupón es solo para la primera compra.'
--
-- Agotado (usos máximos totales):
--   update public.cupones
--      set primera_compra = false, usos_maximos_total = 1
--    where codigo = 'LICHI';
--   -- Despues de un uso valido:
--   select public.valida_cupon('LICHI', 'OTRO_TELEFONO', 10000,
--     'maestro-quiroga', 'delivery', 'efectivo');
--   -- ok = false, mensaje = 'Este cupón ya no tiene usos disponibles.'
--
-- Pedido cancelado no cuenta como uso:
--   update public.pedidos set estado = 'cancelado'
--    where id = (select pedido_id from public.cupon_usos
--                 order by fecha desc limit 1);
--   -- El cupon vuelve a tener uso disponible.
--
-- Doble uso simultaneo:
--   -- En dos sesiones distintas, con usos_por_cliente = 1 o
--   -- usos_maximos_total = 1, llamar casi al mismo tiempo:
--   select public.crear_pedido(
--     'maestro-quiroga', 'delivery', 'efectivo', 'Nombre', 'TELEFONO',
--     '[...items...]'::jsonb, 'Direccion', -28.46, -65.78, null, null,
--     gen_random_uuid(), 'LICHI');
--   -- Una sesion debe crear el pedido y la otra debe fallar por
--   -- 'Ya usaste este cupón.' o 'Este cupón ya no tiene usos disponibles.'
--   -- gracias al SELECT ... FOR UPDATE sobre la fila del cupon.

-- ----------------------------------------------------------------------------
-- 8. Rollback manual (comentado; no ejecutar sin backup)
-- ----------------------------------------------------------------------------
-- begin;
--   -- Eliminar la firma nueva de crear_pedido.
--   drop function if exists public.crear_pedido(
--     text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text);
--
--   -- Recrear crear_pedido desde supabase/migrations/013_crear_pedido.sql
--   -- (firma de 12 argumentos) y volver a aplicar sus grants.
--
--   alter table public.pedidos drop column if exists descuento_cupon;
--   alter table public.pedidos drop column if exists cupon_codigo;
--
--   drop function if exists public.valida_cupon(text, text, numeric, text, text, text);
--   drop function if exists public.pm_validar_cupon(text, text, numeric, text, text, boolean);
--
--   drop table if exists public.cupon_usos;
--   drop table if exists public.cupon_intentos;
--   drop table if exists public.cupones;
-- commit;
