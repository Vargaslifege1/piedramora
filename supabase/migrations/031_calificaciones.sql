-- ============================================================================
-- 031 - Calificaciones de pedidos + medios puntos de fidelidad
-- ============================================================================
-- Reglas de negocio:
--   - Se califica un pedido ENTREGADO, una sola vez, de forma definitiva
--     (unique sobre calificaciones.pedido_id). Sin edicion ni reenvio.
--   - Plazo: 7 dias desde pedidos.entregado_en.
--   - Estrellas 1 a 5 de la COMIDA (obligatorio) y de la ENTREGA (solo si la
--     modalidad es delivery), mas comentario opcional de hasta 500 caracteres.
--   - Premio: calificar suma 0,5 de fidelidad, una sola vez por pedido, SIEMPRE
--     (aunque la nota sea mala), pero solo si el pedido ya conto para la
--     fidelidad (pedidos.fidelidad_contado) y el programa esta activo. El medio
--     punto va al telefono del pedido.
--   - Privacidad: nadie lee calificaciones salvo el dueno (todas) y el
--     encargado (solo su sucursal). Ninguna policy ni RPC las devuelve a anon.
--   - El cliente se identifica con el id del pedido (uuid), nunca con el
--     telefono. Rate limit por IP / pedido / global.
--
-- Prerequisitos: 017 (es_dueno, sucursal_admin), 019 (fidelidad), 021
-- (pedidos.entregado_en). Las migraciones 001 a 030 NO se modifican.
--
-- Modelo de puntos (medios puntos):
--   H = 2 * clientes.fidelidad_pedidos + clientes.fidelidad_calificaciones
--   (un pedido entregado suma 2 medios; una calificacion suma 1 medio).
--   fidelidad_pedidos NO cambia de significado (lo usan el CRM y la 023).
--   Los premios ya no salen por igualdad exacta sino por CRUCE de umbral:
--   el nivel "en" de la vuelta k vale T = 2 * (k * ciclo + en) medios y se
--   premia cuando H_antes < T <= H_despues. premios.umbral_medios + un unique
--   parcial (telefono, tipo, umbral_medios) impiden duplicados. Clientes que
--   hoy estan en pleno ciclo: fidelidad_calificaciones = 0, o sea H = 2 * n,
--   exactamente el estado actual; no hace falta backfill.
--
-- Que hace esta migracion:
--   1. clientes.fidelidad_calificaciones y premios.umbral_medios (+ unique).
--   2. pm_fidelidad_premiar(): genera premios por cruce de umbral (interna).
--   3. pm_fidelidad_acreditar(): REESCRITA para usar medios y cruce de umbral
--      (la unica diferencia con 019 es el bloque de conteo/premio).
--   4. mi_progreso_fidelidad(): REESCRITA para devolver medios puntos.
--      Mantiene las claves de 019/023 y agrega medios_en_ciclo / faltan_medios.
--   5. Tabla calificaciones (RLS: dueno o encargado de la sucursal, solo lectura).
--   6. calificacion_intentos + pm_calificacion_antispam() (interna).
--   7. pedido_para_calificar(p_pedido_id)  -> anon/authenticated.
--   8. calificar_pedido(...)               -> anon/authenticated.
--   9. stats_calificaciones(desde, hasta, sucursal) -> authenticated
--      (dueno o encargado; promedios y totales calculados en el servidor).
--
-- LIMITACIONES CONOCIDAS:
--   - Si el dueno corrige un pedido calificado a 'cancelado', el medio punto
--     ya dado no se retira (igual que el resto de la fidelidad, ver 019).
--   - Un ciclo de 1 pedido (config.ciclo = 1) con un nivel en 1 no esta
--     soportado con calificaciones: dos premios del mismo tipo del mismo
--     pedido chocarian con premios_origen_tipo_uidx (019). La config actual
--     usa ciclo 10.
--   - Si el cliente borro sus datos (borrar_mis_datos) y ya no existe su fila
--     en clientes, la calificacion se guarda igual pero no suma medio punto
--     (calificar_pedido devuelve puntos_ganados = 0 y pedido_para_calificar
--     devuelve suma_fidelidad = false).
--
-- ANTES DE APLICAR (obligatorio):
--   1) BACKUP de la base.
--   2) Guardar las definiciones actuales de las dos funciones que esta
--      migracion reescribe, ejecutando esta consulta de LECTURA:
--
--        select p.oid::regprocedure as funcion,
--               pg_get_functiondef(p.oid) as definicion
--          from pg_proc p
--          join pg_namespace n on n.oid = p.pronamespace
--         where n.nspname = 'public'
--           and p.proname in ('pm_fidelidad_acreditar', 'mi_progreso_fidelidad');
--
--      (Tambien estan copiadas completas, como comentario, mas abajo.)
--
-- Idempotente: se puede ejecutar mas de una vez.
--
-- ============================================================================
-- DEFINICIONES ACTUALES (para revertir). Copia literal de:
--   pm_fidelidad_acreditar  -> 019_fidelidad_premios.sql, seccion 4
--   mi_progreso_fidelidad   -> 023_normalizar_telefonos.sql (version vigente)
-- Para revertir: descomentar y ejecutar estos dos CREATE OR REPLACE. Los
-- permisos se conservan (create or replace no los toca). Las columnas y tablas
-- nuevas pueden quedar: no estorban.
-- ============================================================================
--
-- ---- pm_fidelidad_acreditar (019) ----
--
-- create or replace function public.pm_fidelidad_acreditar(p public.pedidos)
-- returns void
-- language plpgsql
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_cfg jsonb;
--   v_ciclo integer;
--   v_cli public.clientes%rowtype;
--   v_n integer;
--   v_pos integer;
--   v_nivel jsonb;
-- begin
--   v_cfg := public.pm_fidelidad_config();
--   if v_cfg is null then
--     return;
--   end if;
--
--   -- Solo pedidos sincronizados y que llegan al minimo (sobre el subtotal de
--   -- productos, antes de descuentos y sin envio).
--   if p.sincronizado is not distinct from false then
--     return;
--   end if;
--   if p.subtotal < (v_cfg ->> 'pedido_minimo')::numeric then
--     return;
--   end if;
--
--   -- Cada pedido suma como maximo una vez. Si no se actualiza ninguna fila,
--   -- el pedido ya estaba contado.
--   update public.pedidos
--      set fidelidad_contado = true
--    where id = p.id
--      and not fidelidad_contado;
--   if not found then
--     return;
--   end if;
--
--   -- Bloqueo de la fila del cliente: serializa entregas simultaneas.
--   -- (La fila ya existe: el trigger la crea/actualiza antes de llamar aca.)
--   select * into v_cli
--     from public.clientes
--    where telefono = p.cliente_telefono
--    for update;
--   if not found then
--     raise exception 'Cliente inexistente para fidelidad.';
--   end if;
--
--   update public.clientes
--      set fidelidad_pedidos = fidelidad_pedidos + 1
--    where telefono = p.cliente_telefono
--   returning fidelidad_pedidos into v_n;
--
--   v_ciclo := (v_cfg ->> 'ciclo')::integer;
--   v_pos := ((v_n - 1) % v_ciclo) + 1;
--
--   for v_nivel in
--     select e.value
--       from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
--      where (e.value ->> 'en')::integer = v_pos
--   loop
--     insert into public.premios (
--       telefono, tipo, valor, producto_id, tope_en_pesos,
--       vencimiento, pedido_origen_id
--     ) values (
--       p.cliente_telefono,
--       v_nivel ->> 'tipo',
--       case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
--            then (v_nivel ->> 'valor')::numeric end,
--       case when v_nivel ->> 'tipo' = 'producto_gratis'
--            then v_nivel ->> 'producto_id' end,
--       case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
--                  and jsonb_typeof(v_nivel -> 'tope_en_pesos') = 'number'
--            then (v_nivel ->> 'tope_en_pesos')::numeric end,
--       now() + make_interval(days => (v_nivel ->> 'dias_vencimiento')::integer),
--       p.id
--     )
--     on conflict (pedido_origen_id, tipo) do nothing;
--   end loop;
-- end;
-- $$;
--
-- ---- mi_progreso_fidelidad (023, version vigente) ----
--
-- create or replace function public.mi_progreso_fidelidad(p_telefono text)
-- returns jsonb
-- language plpgsql
-- volatile
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_tel text;
--   v_cfg jsonb;
--   v_ciclo integer;
--   v_n integer;
--   v_pos integer;
--   v_sig jsonb;
--   v_faltan integer;
-- begin
--   v_tel := public.pm_normalizar_telefono(p_telefono);
--
--   if v_tel is null or not public.pm_fidelidad_antispam(v_tel) then
--     return jsonb_build_object(
--       'ok', false,
--       'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
--   end if;
--
--   v_cfg := public.pm_fidelidad_config();
--   if v_cfg is null then
--     return jsonb_build_object(
--       'ok', true, 'activo', false, 'pedidos_en_ciclo', 0,
--       'faltan_para_proximo', null, 'proximo_premio', null);
--   end if;
--
--   v_ciclo := (v_cfg ->> 'ciclo')::integer;
--
--   select coalesce(
--            (select c.fidelidad_pedidos from public.clientes c where c.telefono = v_tel), 0)
--     into v_n;
--   v_pos := v_n % v_ciclo;
--
--   -- Proximo nivel dentro del ciclo; si no queda ninguno, el primero del ciclo siguiente.
--   select e.value into v_sig
--     from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
--    where (e.value ->> 'en')::integer > v_pos
--    order by (e.value ->> 'en')::integer
--    limit 1;
--
--   if v_sig is not null then
--     v_faltan := (v_sig ->> 'en')::integer - v_pos;
--   else
--     select e.value into v_sig
--       from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
--      order by (e.value ->> 'en')::integer
--      limit 1;
--     v_faltan := v_ciclo - v_pos + (v_sig ->> 'en')::integer;
--   end if;
--
--   return jsonb_build_object(
--     'ok', true,
--     'activo', true,
--     'pedidos_en_ciclo', v_pos,
--     'faltan_para_proximo', v_faltan,
--     'proximo_premio', jsonb_build_object(
--       'tipo', v_sig ->> 'tipo',
--       'valor', case when v_sig ->> 'tipo' = 'descuento_porcentaje'
--                     then (v_sig ->> 'valor')::numeric end,
--       'producto', case when v_sig ->> 'tipo' = 'producto_gratis'
--                        then public.pm_fidelidad_nombre_producto(v_sig ->> 'producto_id') end
--     )
--   );
-- exception when others then
--   return jsonb_build_object(
--     'ok', false,
--     'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
-- end;
-- $$;
--
-- ============================================================================

-- ============================================================================
-- 0. Verificacion de prerequisitos
-- ============================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'pedidos'
                    and column_name = 'entregado_en') then
    raise exception '031: falta pedidos.entregado_en (migracion 021).';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'clientes'
                    and column_name = 'fidelidad_pedidos') then
    raise exception '031: falta clientes.fidelidad_pedidos (migracion 019).';
  end if;
  if to_regprocedure('public.pm_fidelidad_config()') is null
     or to_regprocedure('public.sucursal_admin()') is null
     or to_regprocedure('public.es_dueno()') is null then
    raise exception '031: faltan funciones de 017/019.';
  end if;
end
$$;

-- ============================================================================
-- 1. Columnas nuevas
-- ============================================================================
alter table public.clientes
  add column if not exists fidelidad_calificaciones integer not null default 0;

alter table public.clientes
  drop constraint if exists clientes_fidelidad_calificaciones_chk;
alter table public.clientes
  add constraint clientes_fidelidad_calificaciones_chk
  check (fidelidad_calificaciones >= 0);

comment on column public.clientes.fidelidad_calificaciones is
  'Calificaciones que sumaron medio punto (031). Puntos en medios = 2 * fidelidad_pedidos + esto.';

alter table public.premios
  add column if not exists umbral_medios integer;

alter table public.premios
  drop constraint if exists premios_umbral_medios_chk;
alter table public.premios
  add constraint premios_umbral_medios_chk
  check (umbral_medios is null or umbral_medios > 0);

comment on column public.premios.umbral_medios is
  'Umbral (en medios puntos) cuyo cruce genero el premio (031). null en premios anteriores a la 031.';

-- Un mismo umbral nunca premia dos veces al mismo telefono y tipo.
create unique index if not exists premios_tel_tipo_umbral_uidx
  on public.premios (telefono, tipo, umbral_medios)
  where umbral_medios is not null;

-- ============================================================================
-- 2. pm_fidelidad_premiar: genera premios por cruce de umbral (interna)
-- ============================================================================
-- Recibe H antes y despues (en medios puntos). Para cada nivel y cada vuelta
-- cuyo umbral T = 2 * (k * ciclo + en) cumple H_antes < T <= H_despues, inserta
-- el premio. Devuelve cuantos premios nuevos se crearon.
-- Cuantos umbrales <= H hay para un nivel: (H - 2en) / (2 ciclo) + 1 si H >= 2en.
create or replace function public.pm_fidelidad_premiar(
  p_tel text,
  p_h0 integer,
  p_h1 integer,
  p_pedido_origen uuid,
  p_cfg jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ciclo integer := (p_cfg ->> 'ciclo')::integer;
  v_nivel jsonb;
  v_en integer;
  v_k0 integer;
  v_k1 integer;
  v_k integer;
  v_t integer;
  v_filas integer;
  v_total integer := 0;
begin
  for v_nivel in select e.value from jsonb_array_elements(p_cfg -> 'niveles') as e(value) loop
    v_en := (v_nivel ->> 'en')::integer;
    v_k0 := case when p_h0 >= 2 * v_en then (p_h0 - 2 * v_en) / (2 * v_ciclo) + 1 else 0 end;
    v_k1 := case when p_h1 >= 2 * v_en then (p_h1 - 2 * v_en) / (2 * v_ciclo) + 1 else 0 end;

    for v_k in v_k0 .. v_k1 - 1 loop
      v_t := 2 * (v_k * v_ciclo + v_en);

      insert into public.premios (
        telefono, tipo, valor, producto_id, tope_en_pesos,
        vencimiento, pedido_origen_id, umbral_medios
      ) values (
        p_tel,
        v_nivel ->> 'tipo',
        case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
             then (v_nivel ->> 'valor')::numeric end,
        case when v_nivel ->> 'tipo' = 'producto_gratis'
             then v_nivel ->> 'producto_id' end,
        case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
                   and jsonb_typeof(v_nivel -> 'tope_en_pesos') = 'number'
             then (v_nivel ->> 'tope_en_pesos')::numeric end,
        now() + make_interval(days => (v_nivel ->> 'dias_vencimiento')::integer),
        p_pedido_origen,
        v_t
      )
      on conflict (telefono, tipo, umbral_medios) where umbral_medios is not null
      do nothing;

      get diagnostics v_filas = row_count;
      v_total := v_total + v_filas;
    end loop;
  end loop;

  return v_total;
end;
$$;

revoke all on function public.pm_fidelidad_premiar(text, integer, integer, uuid, jsonb)
  from public, anon, authenticated;

comment on function public.pm_fidelidad_premiar(text, integer, integer, uuid, jsonb) is
  'Genera premios de fidelidad por cruce de umbral en medios puntos (031). Solo uso interno.';

-- ============================================================================
-- 3. pm_fidelidad_acreditar (reescrita): medios puntos y cruce de umbral
-- ============================================================================
-- Igual a 019 salvo el conteo: suma 2 medios (1 pedido) y premia por cruce.
create or replace function public.pm_fidelidad_acreditar(p public.pedidos)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg jsonb;
  v_cli public.clientes%rowtype;
  v_h0 integer;
begin
  v_cfg := public.pm_fidelidad_config();
  if v_cfg is null then
    return;
  end if;

  if p.sincronizado is not distinct from false then
    return;
  end if;
  if p.subtotal < (v_cfg ->> 'pedido_minimo')::numeric then
    return;
  end if;

  -- Cada pedido suma como maximo una vez.
  update public.pedidos
     set fidelidad_contado = true
   where id = p.id
     and not fidelidad_contado;
  if not found then
    return;
  end if;

  -- Bloqueo de la fila del cliente: serializa entregas y calificaciones.
  select * into v_cli
    from public.clientes
   where telefono = p.cliente_telefono
   for update;
  if not found then
    raise exception 'Cliente inexistente para fidelidad.';
  end if;

  v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;

  update public.clientes
     set fidelidad_pedidos = fidelidad_pedidos + 1
   where telefono = p.cliente_telefono;

  perform public.pm_fidelidad_premiar(
    p.cliente_telefono, v_h0, v_h0 + 2, p.id, v_cfg);
end;
$$;

revoke all on function public.pm_fidelidad_acreditar(public.pedidos)
  from public, anon, authenticated;

comment on function public.pm_fidelidad_acreditar(public.pedidos) is
  'Suma un pedido entregado (2 medios) al contador de fidelidad y premia por cruce de umbral (031). Solo desde el trigger.';

-- ============================================================================
-- 4. mi_progreso_fidelidad (reescrita): medios puntos
-- ============================================================================
-- Claves que ya existian: ok, activo, pedidos_en_ciclo, faltan_para_proximo,
-- proximo_premio. Ahora pedidos_en_ciclo y faltan_para_proximo pueden tener
-- ,5. Claves nuevas: medios_en_ciclo y faltan_medios (enteros).
-- Base: version de 023 (telefono normalizado, anti-spam, error generico).
create or replace function public.mi_progreso_fidelidad(p_telefono text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_cfg jsonb;
  v_ciclo integer;
  v_h integer;
  v_pos integer;      -- posicion en el ciclo, en medios puntos
  v_sig jsonb;
  v_meta integer;     -- meta del proximo premio, en medios puntos
  v_faltan integer;   -- medios que faltan
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);

  if v_tel is null or not public.pm_fidelidad_antispam(v_tel) then
    return jsonb_build_object(
      'ok', false,
      'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
  end if;

  v_cfg := public.pm_fidelidad_config();
  if v_cfg is null then
    return jsonb_build_object(
      'ok', true, 'activo', false, 'pedidos_en_ciclo', 0, 'medios_en_ciclo', 0,
      'faltan_para_proximo', null, 'faltan_medios', null, 'proximo_premio', null);
  end if;

  v_ciclo := (v_cfg ->> 'ciclo')::integer;

  select coalesce(
           (select 2 * c.fidelidad_pedidos + c.fidelidad_calificaciones
              from public.clientes c where c.telefono = v_tel), 0)
    into v_h;
  v_pos := v_h % (2 * v_ciclo);

  -- Proximo nivel dentro del ciclo; si no queda ninguno, el primero del ciclo siguiente.
  select e.value into v_sig
    from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
   where 2 * (e.value ->> 'en')::integer > v_pos
   order by (e.value ->> 'en')::integer
   limit 1;

  if v_sig is not null then
    v_meta := 2 * (v_sig ->> 'en')::integer;
  else
    select e.value into v_sig
      from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
     order by (e.value ->> 'en')::integer
     limit 1;
    v_meta := 2 * v_ciclo + 2 * (v_sig ->> 'en')::integer;
  end if;
  v_faltan := v_meta - v_pos;

  return jsonb_build_object(
    'ok', true,
    'activo', true,
    'pedidos_en_ciclo', v_pos / 2.0,
    'medios_en_ciclo', v_pos,
    'faltan_para_proximo', v_faltan / 2.0,
    'faltan_medios', v_faltan,
    'proximo_premio', jsonb_build_object(
      'tipo', v_sig ->> 'tipo',
      'valor', case when v_sig ->> 'tipo' = 'descuento_porcentaje'
                    then (v_sig ->> 'valor')::numeric end,
      'producto', case when v_sig ->> 'tipo' = 'producto_gratis'
                       then public.pm_fidelidad_nombre_producto(v_sig ->> 'producto_id') end
    )
  );
exception when others then
  return jsonb_build_object(
    'ok', false,
    'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
end;
$$;

revoke all on function public.mi_progreso_fidelidad(text) from public, anon, authenticated;
grant execute on function public.mi_progreso_fidelidad(text) to anon, authenticated;

comment on function public.mi_progreso_fidelidad(text) is
  'Progreso del ciclo de fidelidad (en medios puntos) de un telefono. Anti-spam y error generico (031).';

-- ============================================================================
-- 5. Tabla calificaciones
-- ============================================================================
create table if not exists public.calificaciones (
  id uuid primary key default gen_random_uuid(),

  -- Una sola calificacion por pedido, definitiva.
  pedido_id uuid not null unique
    references public.pedidos (id) on delete cascade,
  -- Copia de pedidos.sucursal_id: simplifica RLS y filtros.
  sucursal_id text not null,

  comida smallint not null,
  -- null cuando la modalidad no es delivery.
  entrega smallint,
  comentario text,
  -- 1 si esta calificacion sumo medio punto de fidelidad, 0 si no.
  puntos_medios smallint not null default 0,
  created_at timestamptz not null default now(),

  constraint calificaciones_comida_chk check (comida between 1 and 5),
  constraint calificaciones_entrega_chk
    check (entrega is null or entrega between 1 and 5),
  constraint calificaciones_comentario_chk
    check (comentario is null or char_length(comentario) between 1 and 500),
  constraint calificaciones_puntos_chk check (puntos_medios in (0, 1))
);

create index if not exists calificaciones_sucursal_fecha_idx
  on public.calificaciones (sucursal_id, created_at desc);
create index if not exists calificaciones_fecha_idx
  on public.calificaciones (created_at desc);

comment on table public.calificaciones is
  'Calificaciones de pedidos entregados (031). Solo las crea calificar_pedido(); solo las lee el dueno o el encargado de la sucursal.';

alter table public.calificaciones enable row level security;

revoke all on public.calificaciones from public, anon, authenticated;
grant select on public.calificaciones to authenticated;

-- Sin policies ni grants de insert/update/delete: nadie escribe directo.
drop policy if exists "Calificaciones lectura admin" on public.calificaciones;
create policy "Calificaciones lectura admin"
  on public.calificaciones
  for select
  to authenticated
  using (
    public.es_dueno()
    or sucursal_id = public.sucursal_admin()
  );

-- ============================================================================
-- 6. Anti-spam
-- ============================================================================
-- Igual que fidelidad_intentos (019): RLS activo, sin policies ni grants.
create table if not exists public.calificacion_intentos (
  id bigint generated by default as identity primary key,

  pedido_id uuid,
  ip text,
  creado_en timestamptz not null default now(),

  constraint calificacion_intentos_ip_largo_chk
    check (ip is null or char_length(ip) <= 100)
);

create index if not exists calificacion_intentos_pedido_fecha_idx
  on public.calificacion_intentos (pedido_id, creado_en desc);
create index if not exists calificacion_intentos_ip_fecha_idx
  on public.calificacion_intentos (ip, creado_en desc);
create index if not exists calificacion_intentos_fecha_idx
  on public.calificacion_intentos (creado_en desc);

comment on table public.calificacion_intentos is
  'Intentos de consultar/enviar calificaciones para el limite anti-spam. Sin acceso publico.';

alter table public.calificacion_intentos enable row level security;
revoke all on public.calificacion_intentos from public, anon, authenticated;

-- Registra el intento y devuelve false si se superaron los limites.
-- Umbrales (ajustables): 20 por pedido y 60 por IP cada 10 minutos,
-- 200 globales cada 5 minutos.
create or replace function public.pm_calificacion_antispam(p_pedido uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ip text;
  v_n integer;
begin
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
  v_ip := left(v_ip, 100);

  delete from public.calificacion_intentos
   where creado_en < now() - interval '1 day';

  select count(*) into v_n
    from public.calificacion_intentos
   where pedido_id = p_pedido and creado_en > now() - interval '10 minutes';
  if v_n >= 20 then
    return false;
  end if;

  if v_ip is not null then
    select count(*) into v_n
      from public.calificacion_intentos
     where ip = v_ip and creado_en > now() - interval '10 minutes';
    if v_n >= 60 then
      return false;
    end if;
  end if;

  select count(*) into v_n
    from public.calificacion_intentos
   where creado_en > now() - interval '5 minutes';
  if v_n >= 200 then
    return false;
  end if;

  insert into public.calificacion_intentos (pedido_id, ip) values (p_pedido, v_ip);
  return true;
end;
$$;

revoke all on function public.pm_calificacion_antispam(uuid) from public, anon, authenticated;

-- ============================================================================
-- 7. pedido_para_calificar
-- ============================================================================
-- Devuelve SOLO un estado y lo minimo para dibujar la pantalla. Nunca devuelve
-- telefono, nombre, direccion ni montos.
--   estado: ok | ya_calificado | vencido | no_entregado | cancelado |
--           no_encontrado | limite
-- Con estado = ok agrega: modalidad, numero_orden, dias_restantes y
-- suma_fidelidad (true solo si el pedido cuenta para fidelidad, el programa
-- esta activo y el cliente existe: o sea, si calificar va a sumar medio punto).
create or replace function public.pedido_para_calificar(p_pedido_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_dias constant integer := 7;
  v_ped public.pedidos%rowtype;
  v_limite timestamptz;
  v_suma boolean;
begin
  if p_pedido_id is null then
    return jsonb_build_object('ok', true, 'estado', 'no_encontrado');
  end if;

  if not public.pm_calificacion_antispam(p_pedido_id) then
    return jsonb_build_object('ok', true, 'estado', 'limite');
  end if;

  select * into v_ped from public.pedidos where id = p_pedido_id;
  if not found then
    return jsonb_build_object('ok', true, 'estado', 'no_encontrado');
  end if;

  if v_ped.estado = 'cancelado' then
    return jsonb_build_object('ok', true, 'estado', 'cancelado');
  end if;
  if v_ped.estado <> 'entregado' then
    return jsonb_build_object('ok', true, 'estado', 'no_entregado');
  end if;

  if exists (select 1 from public.calificaciones where pedido_id = v_ped.id) then
    return jsonb_build_object('ok', true, 'estado', 'ya_calificado');
  end if;

  v_limite := coalesce(v_ped.entregado_en, v_ped.created_at) + make_interval(days => c_dias);
  if now() > v_limite then
    return jsonb_build_object('ok', true, 'estado', 'vencido');
  end if;

  v_suma := v_ped.fidelidad_contado
            and public.pm_fidelidad_config() is not null
            and exists (select 1 from public.clientes c
                         where c.telefono = v_ped.cliente_telefono);

  return jsonb_build_object(
    'ok', true,
    'estado', 'ok',
    'modalidad', v_ped.modalidad,
    'numero_orden', v_ped.numero_orden,
    'dias_restantes', greatest(1, ceil(extract(epoch from (v_limite - now())) / 86400.0)::integer),
    'suma_fidelidad', coalesce(v_suma, false));
exception when others then
  return jsonb_build_object('ok', false, 'estado', 'error');
end;
$$;

revoke all on function public.pedido_para_calificar(uuid) from public, anon, authenticated;
grant execute on function public.pedido_para_calificar(uuid) to anon, authenticated;

comment on function public.pedido_para_calificar(uuid) is
  'Estado de calificacion de un pedido (por id). No devuelve datos personales. Anti-spam (031).';

-- ============================================================================
-- 8. calificar_pedido
-- ============================================================================
-- Devuelve {ok, estado, ...}. Casos:
--   ok=true,  estado='ok'  -> puntos_ganados (0.5 o 0), premio_generado (bool)
--   ok=false, estado en: limite | no_encontrado | cancelado | no_entregado |
--             ya_calificado | vencido | invalido | error   (+ mensaje)
-- Nunca lanza excepciones al cliente. El intento de anti-spam queda registrado
-- aunque la calificacion falle (el trabajo real va en un bloque interno).
create or replace function public.calificar_pedido(
  p_pedido_id uuid,
  p_comida integer,
  p_entrega integer default null,
  p_comentario text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_dias constant integer := 7;
  v_ped public.pedidos%rowtype;
  v_cfg jsonb;
  v_cli public.clientes%rowtype;
  v_com text;
  v_entrega smallint;
  v_h0 integer;
  v_gen integer := 0;
  v_medios smallint := 0;
begin
  if p_pedido_id is null then
    return jsonb_build_object('ok', false, 'estado', 'no_encontrado',
      'mensaje', 'No encontramos ese pedido.');
  end if;

  if not public.pm_calificacion_antispam(p_pedido_id) then
    return jsonb_build_object('ok', false, 'estado', 'limite',
      'mensaje', 'Probá de nuevo en unos minutos.');
  end if;

  begin
    -- Bloqueo del pedido: serializa envios simultaneos para el mismo pedido.
    select * into v_ped from public.pedidos where id = p_pedido_id for update;
    if not found then
      return jsonb_build_object('ok', false, 'estado', 'no_encontrado',
        'mensaje', 'No encontramos ese pedido.');
    end if;

    if v_ped.estado = 'cancelado' then
      return jsonb_build_object('ok', false, 'estado', 'cancelado',
        'mensaje', 'Este pedido no se puede calificar.');
    end if;
    if v_ped.estado <> 'entregado' then
      return jsonb_build_object('ok', false, 'estado', 'no_entregado',
        'mensaje', 'Tu pedido todavía no fue entregado. Calificalo cuando lo recibas.');
    end if;
    if exists (select 1 from public.calificaciones where pedido_id = v_ped.id) then
      return jsonb_build_object('ok', false, 'estado', 'ya_calificado',
        'mensaje', 'Este pedido ya fue calificado. ¡Gracias!');
    end if;
    if now() > coalesce(v_ped.entregado_en, v_ped.created_at) + make_interval(days => c_dias) then
      return jsonb_build_object('ok', false, 'estado', 'vencido',
        'mensaje', 'Pasó el plazo de 7 días para calificar este pedido.');
    end if;

    -- Validacion de datos (el servidor decide; no se corrige en silencio).
    if p_comida is null or p_comida not between 1 and 5 then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'Elegí de 1 a 5 estrellas para la comida.');
    end if;

    if v_ped.modalidad = 'delivery' then
      if p_entrega is null or p_entrega not between 1 and 5 then
        return jsonb_build_object('ok', false, 'estado', 'invalido',
          'mensaje', 'Elegí de 1 a 5 estrellas para la entrega.');
      end if;
      v_entrega := p_entrega;
    else
      v_entrega := null;   -- retiro / mesa: no se pregunta; se ignora lo que llegue
    end if;

    v_com := nullif(btrim(coalesce(p_comentario, '')), '');
    if v_com is not null and char_length(v_com) > 500 then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'El comentario puede tener hasta 500 caracteres.');
    end if;

    -- Medio punto: solo si el pedido ya conto para fidelidad y el programa esta
    -- activo. Mismo orden de bloqueo que la entrega (pedido -> cliente).
    v_cfg := public.pm_fidelidad_config();
    if v_ped.fidelidad_contado and v_cfg is not null then
      select * into v_cli
        from public.clientes
       where telefono = v_ped.cliente_telefono
       for update;
      if found then
        v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;

        update public.clientes
           set fidelidad_calificaciones = fidelidad_calificaciones + 1
         where telefono = v_ped.cliente_telefono;

        v_gen := public.pm_fidelidad_premiar(
          v_ped.cliente_telefono, v_h0, v_h0 + 1, v_ped.id, v_cfg);
        v_medios := 1;
      end if;
    end if;

    insert into public.calificaciones (
      pedido_id, sucursal_id, comida, entrega, comentario, puntos_medios
    ) values (
      v_ped.id, v_ped.sucursal_id, p_comida, v_entrega, v_com, v_medios
    );

    return jsonb_build_object(
      'ok', true,
      'estado', 'ok',
      'puntos_ganados', case when v_medios = 1 then 0.5 else 0 end,
      'premio_generado', v_gen > 0);
  exception
    when unique_violation then
      -- Carrera: otra calificacion del mismo pedido gano. Se deshace todo el bloque.
      return jsonb_build_object('ok', false, 'estado', 'ya_calificado',
        'mensaje', 'Este pedido ya fue calificado. ¡Gracias!');
    when others then
      return jsonb_build_object('ok', false, 'estado', 'error',
        'mensaje', 'No pudimos guardar tu calificación. Probá de nuevo en unos minutos.');
  end;
end;
$$;

revoke all on function public.calificar_pedido(uuid, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.calificar_pedido(uuid, integer, integer, text)
  to anon, authenticated;

comment on function public.calificar_pedido(uuid, integer, integer, text) is
  'Califica un pedido entregado (una vez, 7 dias) y suma 0,5 de fidelidad si corresponde. Todo se decide en el servidor (031).';

-- ============================================================================
-- 9. stats_calificaciones
-- ============================================================================
-- Promedios y totales calculados en el servidor sobre TODAS las calificaciones
-- del filtro (no sobre filas paginadas). Rango [p_desde, p_hasta) sobre
-- calificaciones.created_at (cuando se califico); nulls = sin limite de ese lado.
-- Permisos: el dueno ve todo y puede filtrar por sucursal; el encargado
-- siempre ve solo su sucursal (si pide otra, error).
create or replace function public.stats_calificaciones(
  p_desde timestamptz default null,
  p_hasta timestamptz default null,
  p_sucursal text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_suc text := nullif(btrim(p_sucursal), '');
  v_mia text;
  v_prom_comida numeric;
  v_prom_entrega numeric;
  v_total bigint;
  v_total_entrega bigint;
  v_con_com bigint;
begin
  if not public.es_dueno() then
    v_mia := public.sucursal_admin();
    if v_mia is null then
      raise exception 'No tenés permiso para hacer esto.';
    end if;
    if v_suc is not null and v_suc <> v_mia then
      raise exception 'No tenés permiso para hacer esto.';
    end if;
    v_suc := v_mia;
  end if;

  if p_desde is not null and p_hasta is not null
     and p_hasta - p_desde > interval '731 days' then
    raise exception 'El período no puede superar los 731 días.';
  end if;

  select round(avg(c.comida), 2),
         round(avg(c.entrega), 2),
         count(*),
         count(c.entrega),
         count(c.comentario)
    into v_prom_comida, v_prom_entrega, v_total, v_total_entrega, v_con_com
    from public.calificaciones c
   where (p_desde is null or c.created_at >= p_desde)
     and (p_hasta is null or c.created_at < p_hasta)
     and (v_suc is null or c.sucursal_id = v_suc);

  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'sucursal', v_suc,
    'promedio_comida', v_prom_comida,
    'promedio_entrega', v_prom_entrega,
    'total', v_total,
    'total_entrega', v_total_entrega,
    'con_comentario', v_con_com);
end;
$$;

revoke all on function public.stats_calificaciones(timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.stats_calificaciones(timestamptz, timestamptz, text)
  to authenticated;

comment on function public.stats_calificaciones(timestamptz, timestamptz, text) is
  'Promedios y totales de calificaciones. Dueno: todo o una sucursal; encargado: solo la suya (031).';

-- ============================================================================
-- 10. Pruebas manuales (comentadas; ejecutar en un entorno de prueba)
-- ============================================================================
-- Preparacion: telefono de prueba T; pedidos con subtotal >= 10.000 creados con
-- crear_pedido. "Entregar" = update public.pedidos set estado = 'entregado'
-- where id = '<pedido>' (respetando 'pendiente->confirmado->listo->...').
-- Ver estado: select fidelidad_pedidos, fidelidad_calificaciones
--               from public.clientes where telefono = 'T';
--             select tipo, umbral_medios, pedido_origen_id
--               from public.premios where telefono = 'T' order by creado_en;
--             select public.mi_progreso_fidelidad('T');
-- Calificar: select public.calificar_pedido('<pedido>', 5, 4, 'Muy rico');
--
-- Casos de medios puntos (H = 2*pedidos + calificaciones; umbrales 10 y 20):
--  1) 4 pedidos (H=8), entregar el 5.o                  -> H=10, premio 30% (umbral 10).
--  2) 4 pedidos, calificar 1 viejo (H=9), entregar 5.o  -> H=11, premio 30% (umbral 10).
--  3) 4 ped + 1 calif (4,5), entregar 5.o               -> H=11, premio 30% (antes se perdia).
--  4) 5 pedidos (premio ya dado), calificar             -> H=11, SIN premio nuevo.
--  5) 4,5 y calificar otro: H=9 -> 10                   -> premio 30% al calificar,
--     pedido_origen_id = pedido calificado.
--  6) 9 ped + 1 calif (H=19), calificar otro            -> H=20, Cheeseburger (umbral 20).
--  7) 9 ped + 1 calif (H=19), entregar el 10.o          -> H=21, Cheeseburger (umbral 20).
--  8) 10 pedidos (H=20), entregar el 11.o               -> H=22, sin premio;
--     mi_progreso: medios_en_ciclo = 2, pedidos_en_ciclo = 1.0.
--  9) Segunda vuelta: H=29 -> 31                        -> premio 30% (umbral 30).
-- 10) Doble envio de calificar_pedido para el mismo pedido -> 2.o: ya_calificado,
--     H sube una sola vez.
-- 11) Calificar con pedido sin fidelidad_contado (subtotal < 10.000):
--     ok=true, puntos_ganados = 0; pedido_para_calificar: suma_fidelidad = false.
-- 12) Programa inactivo (config_negocio.fidelidad.activo = false):
--     puntos_ganados = 0, suma_fidelidad = false (restaurar el valor despues).
-- 13) Cliente existente hoy en el ciclo (calificaciones = 0, n pedidos):
--     mi_progreso_fidelidad igual que antes (medios_en_ciclo = 2 * (n % ciclo)).
--
-- Reglas de calificacion:
-- 14) Pedido no entregado -> estado 'no_entregado'; cancelado -> 'cancelado'.
-- 15) Entregado hace 8 dias (update entregado_en por SQL de prueba) -> 'vencido'.
-- 16) Delivery sin p_entrega -> 'invalido'; retiro con p_entrega = 5 -> se
--     guarda entrega = null. p_comida = 0 o 6 -> 'invalido'. Comentario de
--     501 caracteres -> 'invalido'; comentario de espacios -> se guarda null.
-- 17) Pedido inexistente -> 'no_encontrado'. 21+ consultas del mismo pedido en
--     10 minutos -> 'limite'.
--
-- Permisos y privacidad:
-- 18) Como anon: select * from public.calificaciones -> sin acceso.
-- 19) Como encargado de Centro: select -> solo filas de su sucursal;
--     stats_calificaciones(null, null, 'intendente-lascano') -> error de permiso;
--     con null -> solo su sucursal. Como dueno: todas, y filtra por sucursal.
-- 20) Como anon: select public.stats_calificaciones(null, null, null) -> sin
--     permiso de ejecucion. calificacion_intentos: sin acceso para nadie.
-- 21) Verificar que pedido_para_calificar no devuelve telefono, nombre ni montos.

-- ============================================================================
-- 11. ROLLBACK (comentado; ejecutar a mano solo si hace falta)
-- ============================================================================
-- begin;
--   -- 1) Restaurar pm_fidelidad_acreditar y mi_progreso_fidelidad con las
--   --    definiciones comentadas en la cabecera de esta migracion.
--   drop function if exists public.stats_calificaciones(timestamptz, timestamptz, text);
--   drop function if exists public.calificar_pedido(uuid, integer, integer, text);
--   drop function if exists public.pedido_para_calificar(uuid);
--   drop function if exists public.pm_calificacion_antispam(uuid);
--   drop function if exists public.pm_fidelidad_premiar(text, integer, integer, uuid, jsonb);
--   drop table if exists public.calificacion_intentos;
--   drop table if exists public.calificaciones;
--   drop index if exists public.premios_tel_tipo_umbral_uidx;
--   alter table public.premios drop constraint if exists premios_umbral_medios_chk;
--   alter table public.premios drop column if exists umbral_medios;
--   alter table public.clientes drop constraint if exists clientes_fidelidad_calificaciones_chk;
--   alter table public.clientes drop column if exists fidelidad_calificaciones;
-- commit;
-- (Si ya hay clientes con medios puntos, restaurar las funciones viejas hace
--  que dejen de verse esos medios y los premios vuelvan a salir por igualdad.)
