-- ============================================================================
-- 025_modalidades_por_dia.sql
-- Modalidades por dia (delivery / retiro) y excepciones de calendario.
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP COMPLETO de la base (Supabase > Database >
-- Backups, o pg_dump). Esta migracion agrega columnas y una tabla, REEMPLAZA
-- pm_turnos (cambia su tipo de retorno), sucursal_estado y crear_pedido
-- (funcion de dinero, misma firma de 16 parametros y mismos grants).
--
-- Prerrequisitos (ya aplicadas): 001-024 (usa es_dueno, sucursal_admin,
-- sucursal_horarios, cierres_especiales, sucursal_estado_manual, pm_en_turno,
-- pm_en_cierre, pm_proxima_apertura y crear_pedido de 024).
-- NO se modifica ninguna migracion anterior, ni las policies de 024, ni
-- pm_calcular_pedido.
--
-- Que hace:
--   1. sucursal_horarios.acepta_delivery / acepta_retiro (default true, al
--      menos una en true). Los turnos existentes quedan con ambas en true.
--   2. excepciones_dia: un dia puntual que REEMPLAZA a la regla semanal de esa
--      fecha (fecha = dia en que EMPIEZA el turno): abierto, solo_delivery,
--      solo_retiro o cerrado, con turno propio (desde/hasta) o el semanal.
--      Si el dia no tiene turno semanal y no se indica horario, se usa
--      config_negocio 'horario_excepcion_default' (seed 20:30 a 00:30).
--   3. pm_turnos ahora devuelve tambien acepta_delivery, acepta_retiro y si el
--      turno viene de una excepcion. Helpers nuevos: pm_modalidades_en,
--      pm_excepcion_vigente, pm_horario_excepcion_default.
--   4. sucursal_estado devuelve ademas acepta_delivery, acepta_retiro y
--      modalidades_hoy ('ambas' | 'solo_delivery' | 'solo_retiro').
--   5. crear_pedido rechaza una modalidad que el turno vigente (o el del dia
--      programado) no acepta.
--
-- Prioridad (de mayor a menor):
--   forzar_cerrado > cierre_especial > excepcion > forzar_abierto > horario semanal
--   - Las excepciones NO anulan cierres_especiales ni forzar_cerrado.
--   - forzar_abierto solo rige si NO hay una excepcion vigente en ese momento
--     (la del dia local, o la de ayer si su turno cruza la medianoche). Con una
--     excepcion vigente manda la excepcion: dentro de su turno abre con SUS
--     modalidades; fuera de el, cierra (incluido el modo 'cerrado').
--   - Sin excepcion, forzar_abierto y la sucursal sin horarios (anti-lockout)
--     abren con ambas modalidades.
--
-- Convenciones (igual que 024):
--   - dia_semana: 0 = domingo ... 6 = sabado. Hora Argentina.
--   - hasta <= desde cruza la medianoche; el turno es [desde, hasta).
--   - Una excepcion con modo 'cerrado' suprime solo los turnos que EMPIEZAN
--     ese dia; un turno del dia anterior que cruce la medianoche sigue hasta
--     su hora (para cortar de verdad el dia entero usar cierres_especiales).
--   - Modalidad del pedido: 'delivery' o retiro (cualquier otro valor se trata
--     como retiro). Turnos encadenados/superpuestos: se acepta una modalidad si
--     alguno de los turnos que cubren ese instante la acepta.
--
-- Reglas de crear_pedido:
--   - Pedido para ahora, sucursal abierta, modalidad no aceptada -> ERROR
--     "Hoy este local solo recibe pedidos para delivery. Elegí delivery." (o
--     "...para retiro. Elegí retiro."). Cerrado se rechaza como en 024.
--   - Programado dentro de un turno de ese dia: el turno debe aceptar la
--     modalidad -> si no, ERROR "El DD/MM este local solo recibe pedidos para
--     delivery. Elegí delivery." (DD/MM = dia en que empieza el turno).
--   - NO se valida modalidad en cierre especial ni con la sucursal en modo
--     manual forzado hoy (casos que 024 ya deja pasar a pendiente).
--
-- Idempotente: se puede volver a correr (columnas/tabla con if not exists,
-- constraint condicional, policies recreadas, funciones con create or replace).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. sucursal_horarios: modalidades aceptadas por turno
-- ----------------------------------------------------------------------------
alter table public.sucursal_horarios
  add column if not exists acepta_delivery boolean not null default true;
alter table public.sucursal_horarios
  add column if not exists acepta_retiro boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'sucursal_horarios_modalidad_chk'
       and conrelid = 'public.sucursal_horarios'::regclass) then
    alter table public.sucursal_horarios
      add constraint sucursal_horarios_modalidad_chk
      check (acepta_delivery or acepta_retiro);
  end if;
end $$;

comment on column public.sucursal_horarios.acepta_delivery is
  'El turno acepta pedidos de delivery. Al menos una de las dos modalidades debe ser true.';
comment on column public.sucursal_horarios.acepta_retiro is
  'El turno acepta pedidos para retiro. Al menos una de las dos modalidades debe ser true.';

-- ----------------------------------------------------------------------------
-- 2. excepciones_dia
-- ----------------------------------------------------------------------------
create table if not exists public.excepciones_dia (
  id          bigint generated always as identity primary key,
  sucursal_id text not null,
  fecha       date not null,              -- dia en que EMPIEZA el turno
  modo        text not null,
  desde       time,                       -- null = usar el turno semanal / default
  hasta       time,                       -- hasta <= desde cruza la medianoche
  motivo      text,
  created_at  timestamptz not null default now(),

  constraint excepciones_dia_sucursal_chk
    check (sucursal_id in ('maestro-quiroga', 'intendente-lascano')),
  constraint excepciones_dia_modo_chk
    check (modo in ('abierto', 'solo_delivery', 'solo_retiro', 'cerrado')),
  constraint excepciones_dia_horario_chk
    check ((desde is null) = (hasta is null)),
  constraint excepciones_dia_cerrado_chk
    check (modo <> 'cerrado' or desde is null),
  constraint excepciones_dia_motivo_chk
    check (motivo is null or char_length(motivo) <= 200),
  constraint excepciones_dia_uk
    unique (sucursal_id, fecha)
);

comment on table public.excepciones_dia is
  'Excepcion puntual por sucursal y fecha: REEMPLAZA la regla semanal de ese dia (abierto/solo_delivery/solo_retiro/cerrado). desde/hasta null = turno semanal del dia, o horario_excepcion_default si no tiene. No anula cierres_especiales ni forzar_cerrado.';

-- La unique (sucursal_id, fecha) ya cubre las busquedas por sucursal y dia.
create index if not exists excepciones_dia_fecha_idx
  on public.excepciones_dia (fecha);

alter table public.excepciones_dia enable row level security;

revoke all on public.excepciones_dia from anon, authenticated;
grant select on public.excepciones_dia to anon, authenticated;
grant insert, update, delete on public.excepciones_dia to authenticated;

drop policy if exists "Excepciones lectura publica" on public.excepciones_dia;
create policy "Excepciones lectura publica" on public.excepciones_dia
  for select to anon, authenticated using (true);

drop policy if exists "Excepciones alta admin" on public.excepciones_dia;
create policy "Excepciones alta admin" on public.excepciones_dia
  for insert to authenticated
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Excepciones edicion admin" on public.excepciones_dia;
create policy "Excepciones edicion admin" on public.excepciones_dia
  for update to authenticated
  using (public.es_dueno() or sucursal_id = public.sucursal_admin())
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Excepciones baja admin" on public.excepciones_dia;
create policy "Excepciones baja admin" on public.excepciones_dia
  for delete to authenticated
  using (public.es_dueno() or sucursal_id = public.sucursal_admin());

-- Horario por defecto de una excepcion en un dia sin turno semanal.
insert into public.config_negocio (clave, valor)
values ('horario_excepcion_default', '{"desde":"20:30","hasta":"00:30"}'::jsonb)
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- 3. Funciones auxiliares (internas, sin permisos para anon/authenticated)
-- ----------------------------------------------------------------------------

-- Horario por defecto de las excepciones (lee config; si falta o es invalido,
-- 20:30 a 00:30).
create or replace function public.pm_horario_excepcion_default()
returns table (desde time, hasta time)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(case when x.v ->> 'desde' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                  then (x.v ->> 'desde')::time end, time '20:30'),
    coalesce(case when x.v ->> 'hasta' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                  then (x.v ->> 'hasta')::time end, time '00:30')
  from (select (select c.valor from public.config_negocio c
                 where c.clave = 'horario_excepcion_default') as v) x;
$$;

-- Turnos (intervalos [ini, fin) en timestamptz) que EMPIEZAN entre dos fechas
-- locales (inclusive), ya resueltas las excepciones:
--   A. dia sin excepcion            -> turnos semanales (con sus modalidades)
--   B. excepcion con desde/hasta    -> un turno propio
--   C. excepcion sin horario        -> turnos semanales del dia, modalidades de la excepcion
--   D. excepcion sin horario y el dia sin turno semanal -> horario por defecto
--   (excepcion 'cerrado' -> ningun turno ese dia)
-- Cambia el tipo de retorno respecto de 024, por eso se dropea primero.
drop function if exists public.pm_turnos(text, date, date);

create function public.pm_turnos(
  p_sucursal_id text, p_desde date, p_hasta date)
returns table (ini timestamptz, fin timestamptz,
               acepta_delivery boolean, acepta_retiro boolean, excepcion boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with dias as (
    select g.ts::date as dia
      from generate_series(p_desde::timestamp, p_hasta::timestamp, interval '1 day') as g(ts)
  ),
  base as (
    -- A. sin excepcion: regla semanal
    select d.dia, h.desde, h.hasta, h.acepta_delivery, h.acepta_retiro, false as excepcion
      from dias d
      join public.sucursal_horarios h
        on h.sucursal_id = p_sucursal_id
       and h.dia_semana = extract(dow from d.dia)::int
     where not exists (
       select 1 from public.excepciones_dia e
        where e.sucursal_id = p_sucursal_id and e.fecha = d.dia)
    union all
    -- B. excepcion con horario propio
    select d.dia, e.desde, e.hasta,
           e.modo <> 'solo_retiro', e.modo <> 'solo_delivery', true
      from dias d
      join public.excepciones_dia e
        on e.sucursal_id = p_sucursal_id and e.fecha = d.dia
     where e.modo <> 'cerrado' and e.desde is not null
    union all
    -- C. excepcion sin horario: turnos semanales de ese dia
    select d.dia, h.desde, h.hasta,
           e.modo <> 'solo_retiro', e.modo <> 'solo_delivery', true
      from dias d
      join public.excepciones_dia e
        on e.sucursal_id = p_sucursal_id and e.fecha = d.dia
      join public.sucursal_horarios h
        on h.sucursal_id = p_sucursal_id
       and h.dia_semana = extract(dow from d.dia)::int
     where e.modo <> 'cerrado' and e.desde is null
    union all
    -- D. excepcion sin horario y sin turno semanal: horario por defecto
    select d.dia, f.desde, f.hasta,
           e.modo <> 'solo_retiro', e.modo <> 'solo_delivery', true
      from dias d
      join public.excepciones_dia e
        on e.sucursal_id = p_sucursal_id and e.fecha = d.dia
     cross join public.pm_horario_excepcion_default() f
     where e.modo <> 'cerrado' and e.desde is null
       and not exists (
         select 1 from public.sucursal_horarios h
          where h.sucursal_id = p_sucursal_id
            and h.dia_semana = extract(dow from d.dia)::int)
  )
  select ((b.dia + b.desde) at time zone 'America/Argentina/Buenos_Aires'),
         (((b.dia + case when b.hasta <= b.desde then 1 else 0 end) + b.hasta)
           at time zone 'America/Argentina/Buenos_Aires'),
         b.acepta_delivery, b.acepta_retiro, b.excepcion
    from base b;
$$;

-- Modalidades que aceptan los turnos que cubren el instante (OR entre turnos
-- superpuestos) y el inicio del primero. Sin turno: devuelve una fila con nulls.
create or replace function public.pm_modalidades_en(p_sucursal_id text, p_t timestamptz)
returns table (acepta_delivery boolean, acepta_retiro boolean, ini timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select bool_or(t.acepta_delivery), bool_or(t.acepta_retiro), min(t.ini)
    from public.pm_turnos(
           p_sucursal_id,
           ((p_t at time zone 'America/Argentina/Buenos_Aires')::date - 1),
           ((p_t at time zone 'America/Argentina/Buenos_Aires')::date)) t
   where t.ini <= p_t and p_t < t.fin;
$$;

-- true si hay una excepcion rigiendo en ese instante: una para el dia local, o
-- un turno de excepcion de ayer que sigue vigente pasada la medianoche.
create or replace function public.pm_excepcion_vigente(p_sucursal_id text, p_t timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
           select 1 from public.excepciones_dia e
            where e.sucursal_id = p_sucursal_id
              and e.fecha = (p_t at time zone 'America/Argentina/Buenos_Aires')::date)
      or exists (
           select 1
             from public.pm_turnos(
                    p_sucursal_id,
                    ((p_t at time zone 'America/Argentina/Buenos_Aires')::date - 1),
                    ((p_t at time zone 'America/Argentina/Buenos_Aires')::date)) t
            where t.excepcion and t.ini <= p_t and p_t < t.fin);
$$;

revoke all on function public.pm_horario_excepcion_default() from public, anon, authenticated;
revoke all on function public.pm_turnos(text, date, date) from public, anon, authenticated;
revoke all on function public.pm_modalidades_en(text, timestamptz) from public, anon, authenticated;
revoke all on function public.pm_excepcion_vigente(text, timestamptz) from public, anon, authenticated;

-- pm_en_turno, pm_en_cierre y pm_proxima_apertura (024) no cambian: solo leen
-- ini/fin de pm_turnos, asi que ya respetan las excepciones.

-- ----------------------------------------------------------------------------
-- 4. sucursal_estado (publica). Base: version de 024 + excepciones + modalidades.
-- ----------------------------------------------------------------------------
create or replace function public.sucursal_estado(
  p_sucursal_id text,
  p_ahora       timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz     constant text := 'America/Argentina/Buenos_Aires';
  v_coords jsonb;
  v_modo   text;
  v_abierto boolean;
  v_motivo text;
  v_prox   timestamptz;
  v_cierra timestamptz;
  v_fin    timestamptz;
  v_sig    timestamptz;
  v_hoy    date := (p_ahora at time zone 'America/Argentina/Buenos_Aires')::date;
  v_exc    boolean;                      -- 025: hay excepcion vigente
  v_acd    boolean := true;              -- 025
  v_acr    boolean := true;              -- 025
  v_m      record;                       -- 025
begin
  select valor into v_coords from public.config_negocio where clave = 'sucursales_coords';
  if p_sucursal_id is null or v_coords is null or (v_coords -> p_sucursal_id) is null then
    raise exception 'La sucursal no existe.';
  end if;

  select modo into v_modo from public.sucursal_estado_manual where sucursal_id = p_sucursal_id;
  v_modo := coalesce(v_modo, 'automatico');

  v_exc := public.pm_excepcion_vigente(p_sucursal_id, p_ahora);       -- 025

  if v_modo = 'forzar_cerrado' then
    v_abierto := false;
    v_motivo := 'forzado_cerrado';
    v_prox := public.pm_proxima_apertura(p_sucursal_id, p_ahora);   -- informativo

  elsif public.pm_en_cierre(p_sucursal_id, p_ahora) then
    v_abierto := false;
    v_motivo := 'cierre_especial';
    v_prox := public.pm_proxima_apertura(p_sucursal_id, p_ahora);

  elsif v_modo = 'forzar_abierto' and not v_exc then                  -- 025: la excepcion gana
    v_abierto := true;
    v_motivo := 'forzado_abierto';

  elsif not v_exc
        and not exists (select 1 from public.sucursal_horarios where sucursal_id = p_sucursal_id) then
    -- Anti-lockout: sin horarios cargados no se bloquea la sucursal.
    v_abierto := true;
    v_motivo := 'horario';

  elsif public.pm_en_turno(p_sucursal_id, p_ahora) then
    v_abierto := true;
    v_motivo := 'horario';
    -- 025: modalidades del turno vigente (semanal o excepcion).
    select * into v_m from public.pm_modalidades_en(p_sucursal_id, p_ahora);
    v_acd := coalesce(v_m.acepta_delivery, true);
    v_acr := coalesce(v_m.acepta_retiro, true);
    -- Fin del turno vigente, encadenando turnos que empiezan justo al terminar.
    select max(t.fin) into v_fin
      from public.pm_turnos(p_sucursal_id, v_hoy - 1, v_hoy) t
     where t.ini <= p_ahora and p_ahora < t.fin;
    loop
      select max(t.fin) into v_sig
        from public.pm_turnos(p_sucursal_id, v_hoy - 1, v_hoy + 3) t
       where t.ini <= v_fin and t.fin > v_fin;
      exit when v_sig is null;
      v_fin := v_sig;
    end loop;
    v_cierra := v_fin;
    -- Un cierre especial que empiece antes corta el turno a medianoche.
    select min(c.desde::timestamp at time zone v_tz) into v_sig
      from public.cierres_especiales c
     where (c.sucursal_id is null or c.sucursal_id = p_sucursal_id)
       and (c.desde::timestamp at time zone v_tz) > p_ahora;
    if v_sig is not null and v_sig < v_cierra then
      v_cierra := v_sig;
    end if;

  else
    v_abierto := false;
    v_motivo := 'fuera_de_horario';
    v_prox := public.pm_proxima_apertura(p_sucursal_id, p_ahora);
  end if;

  -- 025: cerrado -> modalidades de la proxima apertura (sin dato: ambas).
  if not v_abierto and v_prox is not null then
    select * into v_m from public.pm_modalidades_en(p_sucursal_id, v_prox);
    v_acd := coalesce(v_m.acepta_delivery, true);
    v_acr := coalesce(v_m.acepta_retiro, true);
  end if;

  return jsonb_build_object(
    'abierto', v_abierto,
    'motivo', v_motivo,
    'proxima_apertura', case when v_prox is null then null else
      to_char(v_prox at time zone v_tz, 'YYYY-MM-DD"T"HH24:MI:SS"-03:00"') end,
    'cierra_a', case when v_cierra is null then null else
      to_char(v_cierra at time zone v_tz, 'YYYY-MM-DD"T"HH24:MI:SS"-03:00"') end,
    'acepta_delivery', v_acd,
    'acepta_retiro', v_acr,
    'modalidades_hoy', case when v_acd and v_acr then 'ambas'
                            when v_acd then 'solo_delivery'
                            else 'solo_retiro' end);
end;
$$;

revoke all on function public.sucursal_estado(text, timestamptz) from public;
grant execute on function public.sucursal_estado(text, timestamptz) to anon, authenticated;

comment on function public.sucursal_estado(text, timestamptz) is
  'Estado de la sucursal en hora Argentina: {abierto, motivo, proxima_apertura, cierra_a, acepta_delivery, acepta_retiro, modalidades_hoy}. Modalidades del turno vigente (o de la proxima apertura si esta cerrada). Prioridad: forzar_cerrado > cierre_especial > excepcion > forzar_abierto > horario.';

-- ----------------------------------------------------------------------------
-- 5. crear_pedido (base: la version ACTUAL de 024, misma firma de 16 parametros)
--    Cambios marcados con "-- 025". Se redefine con create or replace; el
--    revoke/grant se repite igual que en 024.
-- ----------------------------------------------------------------------------
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
  p_cupon            text default null,
  p_premio_id        uuid default null,
  p_acepta_promos    boolean default null,
  p_programado_para  timestamptz default null     -- 024
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

  v_items jsonb;                            -- 019
  v_premio public.premios%rowtype;          -- 019
  v_premio_aplicado boolean := false;       -- 019

  v_tz constant text := 'America/Argentina/Buenos_Aires';   -- 024
  v_ahora timestamptz := now();                             -- 024
  v_estado jsonb;                                           -- 024
  v_prox timestamptz;                                       -- 024
  v_max_dias integer := 15;                                 -- 024
  v_modo text;                                              -- 024
  v_cuando text;                                            -- 024
  v_acd boolean;                                            -- 025
  v_acr boolean;                                            -- 025
  v_ini timestamptz;                                        -- 025
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

  v_tel := public.pm_normalizar_telefono(p_cliente_telefono);
  if v_tel is null then
    raise exception 'Ingresá código de área y número, sin 0 ni 15 (ej. 3834818271).';
  end if;

  -- 019: un solo beneficio por pedido.
  if p_premio_id is not null and btrim(coalesce(p_cupon, '')) <> '' then
    raise exception 'No podés usar un premio y un cupón en el mismo pedido.';
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

  -- 024: horario de atencion y pedidos programados. sucursal_estado valida
  -- ademas que la sucursal exista ("La sucursal no existe.").
  v_estado := public.sucursal_estado(p_sucursal_id, v_ahora);

  if p_programado_para is null then
    if not coalesce((v_estado ->> 'abierto')::boolean, false) then
      v_prox := (v_estado ->> 'proxima_apertura')::timestamptz;
      if v_estado ->> 'motivo' = 'cierre_especial' and v_prox is not null then
        raise exception 'Cerrado hasta el %. Podés programar tu pedido.',
          to_char(v_prox at time zone v_tz, 'DD/MM');
      elsif v_estado ->> 'motivo' = 'forzado_cerrado' or v_prox is null then
        raise exception 'Cerrado por el momento. Podés programar tu pedido.';
      else
        v_cuando := case
          when (v_prox at time zone v_tz)::date = (v_ahora at time zone v_tz)::date then ''
          when (v_prox at time zone v_tz)::date = (v_ahora at time zone v_tz)::date + 1 then 'mañana '
          else 'el ' || to_char(v_prox at time zone v_tz, 'DD/MM') || ' ' end;
        raise exception 'Cerrado, abrimos %a las %. Podés programar tu pedido.',
          v_cuando, to_char(v_prox at time zone v_tz, 'HH24:MI');
      end if;
    end if;

    -- 025: sucursal abierta -> el turno vigente (semanal o excepcion) tiene que
    -- aceptar la modalidad. En forzado abierto / sin horarios ambas son true.
    if p_modalidad = 'delivery'
       and not coalesce((v_estado ->> 'acepta_delivery')::boolean, true) then
      raise exception 'Hoy este local solo recibe pedidos para retiro. Elegí retiro.';
    elsif p_modalidad is distinct from 'delivery'
       and not coalesce((v_estado ->> 'acepta_retiro')::boolean, true) then
      raise exception 'Hoy este local solo recibe pedidos para delivery. Elegí delivery.';
    end if;
  else
    select case when jsonb_typeof(valor) <> 'number' then 15
                when (valor #>> '{}')::numeric between 1 and 90
                  then floor((valor #>> '{}')::numeric)::integer
                else 15 end
      into v_max_dias
      from public.config_negocio where clave = 'programar_max_dias';
    v_max_dias := coalesce(v_max_dias, 15);

    if p_programado_para <= v_ahora then
      raise exception 'La fecha y hora programadas tienen que ser futuras.';
    end if;
    if p_programado_para > v_ahora + make_interval(days => v_max_dias) then
      raise exception 'Solo podés programar pedidos hasta % días adelante.', v_max_dias;
    end if;

    -- Debe caer en horario de apertura. Se permite igual si ese dia esta en un
    -- cierre especial, o si es hoy y la sucursal esta en modo manual forzado
    -- (queda pendiente hasta que el local lo acepte).
    select modo into v_modo from public.sucursal_estado_manual where sucursal_id = p_sucursal_id;
    if not (
      (public.pm_en_turno(p_sucursal_id, p_programado_para)
         and not public.pm_en_cierre(p_sucursal_id, p_programado_para))
      or public.pm_en_cierre(p_sucursal_id, p_programado_para)
      or (coalesce(v_modo, 'automatico') <> 'automatico'
          and (p_programado_para at time zone v_tz)::date = (v_ahora at time zone v_tz)::date)
      or not exists (select 1 from public.sucursal_horarios where sucursal_id = p_sucursal_id)
    ) then
      raise exception 'Ese horario está fuera de nuestro horario de atención. Elegí otro día u horario.';
    end if;

    -- 025: el turno de ese dia tiene que aceptar la modalidad. No se valida en
    -- cierre especial ni con la sucursal en modo manual forzado hoy (casos que
    -- se dejan pasar a pendiente), ni si no hay turno (sin horarios).
    if not public.pm_en_cierre(p_sucursal_id, p_programado_para)
       and not (coalesce(v_modo, 'automatico') <> 'automatico'
                and (p_programado_para at time zone v_tz)::date = (v_ahora at time zone v_tz)::date) then
      select m.acepta_delivery, m.acepta_retiro, m.ini
        into v_acd, v_acr, v_ini
        from public.pm_modalidades_en(p_sucursal_id, p_programado_para) m;
      if p_modalidad = 'delivery' and v_acd is not null and not v_acd then
        raise exception 'El % este local solo recibe pedidos para retiro. Elegí retiro.',
          to_char(v_ini at time zone v_tz, 'DD/MM');
      elsif p_modalidad is distinct from 'delivery' and v_acr is not null and not v_acr then
        raise exception 'El % este local solo recibe pedidos para delivery. Elegí delivery.',
          to_char(v_ini at time zone v_tz, 'DD/MM');
      end if;
    end if;
  end if;

  v_calc := public.pm_calcular_pedido(
    p_sucursal_id, p_modalidad, p_metodo_pago, p_items, p_zona_envio, v_lat, v_lng);

  v_subtotal := coalesce((v_calc ->> 'subtotal')::numeric, 0);
  v_envio := coalesce((v_calc ->> 'costo_envio')::numeric, 0);
  v_desc_pago := coalesce((v_calc ->> 'descuento')::numeric, 0);
  v_desc_final := v_desc_pago;
  v_items := v_calc -> 'items';             -- 019

  -- 019: canje de premio. Se bloquea la fila del premio hasta el commit, lo
  -- que serializa canjes simultaneos del mismo premio. Solo se acepta si es
  -- del telefono del pedido, no esta usado y no vencio. Con premio se ignoran
  -- el cupon y el descuento por medio de pago.
  if p_premio_id is not null then
    select * into v_premio
      from public.premios
     where id = p_premio_id
       and telefono = v_tel
     for update;
    if not found then
      raise exception 'El premio no es válido.';
    end if;
    if v_premio.usado then
      raise exception 'Este premio ya fue usado.';
    end if;
    if v_premio.vencimiento <= now() then
      raise exception 'Este premio está vencido.';
    end if;

    if v_premio.tipo = 'descuento_porcentaje' then
      -- Sobre el subtotal de productos (sin envio), con tope si existe.
      v_desc_final := round(v_subtotal * v_premio.valor / 100);
      if v_premio.tope_en_pesos is not null then
        v_desc_final := least(v_desc_final, v_premio.tope_en_pesos);
      end if;
      v_desc_final := least(greatest(v_desc_final, 0), v_subtotal);
    else
      -- Producto gratis: item a $0; el subtotal pagado no cambia.
      v_desc_final := 0;
      v_items := v_items || jsonb_build_array(
        public.pm_fidelidad_item_regalo(v_premio.producto_id, p_sucursal_id));
    end if;

    v_premio_aplicado := true;
  end if;

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
      cupon_codigo, descuento_cupon,
      premio_id, programado_para
    ) values (
      p_sucursal_id, p_modalidad, v_nombre, v_tel,
      v_dir, v_lat, v_lng, v_calc ->> 'zona_envio', v_items,
      v_subtotal, v_desc_final, v_envio, v_total,
      p_metodo_pago, p_idempotency_key, nullif(v_notas, ''),
      case when v_cupon_aplicado then v_codigo else null end,
      case when v_cupon_aplicado then v_desc_cupon else 0 end,
      case when v_premio_aplicado then v_premio.id else null end,
      p_programado_para
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

  -- 019: marcar el premio como usado en la misma transaccion (la fila sigue
  -- bloqueada desde el FOR UPDATE).
  if v_premio_aplicado then
    update public.premios
       set usado = true,
           usado_en = now(),
           pedido_id = v_ped.id
     where id = v_premio.id;
  end if;

  -- 020: consentimiento de promos. Solo si viene true; null/false no cambian
  -- nada. Usa v_nombre (ya validado). Si el cliente existe, el on conflict NO
  -- toca nombre ni otras columnas: solo acepta_promos y su fecha.
  if p_acepta_promos is true then
    insert into public.clientes (
      telefono, nombre, acepta_promos, acepta_promos_en, origen
    ) values (
      v_tel, v_nombre, true, now(), 'pedido'
    )
    on conflict (telefono) do update
      set acepta_promos = true,
          acepta_promos_en = case when public.clientes.acepta_promos
                                  then public.clientes.acepta_promos_en
                                  else now() end;
  end if;

  return public.pm_pedido_resultado(v_ped);
end;
$$;

revoke all on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz)
  from public;
grant execute on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz)
  to anon, authenticated;

comment on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz) is
  'Crea un pedido validando precios, cupon, premio, horario y modalidad aceptada por el turno en el servidor. Con p_programado_para agenda el pedido (futuro, max programar_max_dias, dentro del horario). Ignora totales y descuentos del cliente.';

commit;

-- ============================================================================
-- CASOS DE PRUEBA (ejecutar a mano; esperado entre parentesis).
-- 2026-11-06 es viernes; Argentina = UTC-3. Lunes = 2026-11-09,
-- miercoles = 2026-11-11. Usar items validos de la carta en crear_pedido.
-- ============================================================================
-- Preparacion: lunes Maestro solo delivery, Lascano ambas (default).
-- update public.sucursal_horarios set acepta_retiro = false
--  where sucursal_id = 'maestro-quiroga' and dia_semana = 1;
-- select public.sucursal_estado('maestro-quiroga',   '2026-11-09 21:00:00-03');
--   -- (abierto=true, acepta_delivery=true, acepta_retiro=false, modalidades_hoy=solo_delivery)
-- select public.sucursal_estado('intendente-lascano', '2026-11-09 21:00:00-03');
--   -- (abierto=true, ambas, modalidades_hoy=ambas)
-- -- Cerrado el lunes a las 12:00: devuelve las de la proxima apertura (20:30 solo delivery).
-- select public.sucursal_estado('maestro-quiroga', '2026-11-09 12:00:00-03');
--   -- (abierto=false, fuera_de_horario, proxima_apertura=2026-11-09T20:30:00-03:00, solo_delivery)
-- -- Check: update ... set acepta_delivery = false, acepta_retiro = false -> ERROR (sucursal_horarios_modalidad_chk).
--
-- Excepcion de un miercoles abierto con ambas, turno propio 19:00 a 23:00:
-- insert into public.excepciones_dia (sucursal_id, fecha, modo, desde, hasta, motivo)
--   values ('maestro-quiroga', '2026-11-11', 'abierto', '19:00', '23:00', 'Prueba');
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 19:30:00-03');
--   -- (abierto=true, ambas, cierra_a=2026-11-11T23:00:00-03:00)
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 20:00:00-03');   -- (abierto=true: reemplaza al 20:30 semanal)
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 23:00:00-03');   -- (abierto=false)
-- -- Sin desde/hasta usa el turno semanal del dia (20:30 a 00:30):
-- update public.excepciones_dia set modo = 'abierto', desde = null, hasta = null where motivo = 'Prueba';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 19:30:00-03');   -- (abierto=false, abre 20:30)
-- -- Dia sin turno semanal + excepcion sin horario -> default 20:30 a 00:30:
-- --   (borrar los horarios de ese dia en una sucursal de prueba, o cambiar horario_excepcion_default.)
--
-- Excepcion solo_retiro (miercoles, turno semanal):
-- update public.excepciones_dia set modo = 'solo_retiro' where motivo = 'Prueba';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 21:00:00-03');
--   -- (abierto=true, acepta_delivery=false, acepta_retiro=true, modalidades_hoy=solo_retiro)
--
-- Excepcion cerrado:
-- update public.excepciones_dia set modo = 'cerrado' where motivo = 'Prueba';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 21:00:00-03');
--   -- (abierto=false, fuera_de_horario, proxima_apertura=2026-11-12T20:30:00-03:00)
-- -- El turno del martes que cruza la medianoche sigue hasta las 00:30 del miercoles:
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 00:10:00-03');   -- (abierto=true)
--
-- Excepcion que cruza la medianoche (hasta <= desde):
-- update public.excepciones_dia set modo = 'abierto', desde = '22:00', hasta = '02:00' where motivo = 'Prueba';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-12 01:30:00-03');
--   -- (abierto=true, cierra_a=2026-11-12T02:00:00-03:00, motivo=horario)
-- select public.sucursal_estado('maestro-quiroga', '2026-11-12 02:00:00-03');   -- (abierto=false)
--
-- Pedido de retiro rechazado en dia solo_delivery (lunes Maestro; probar con
-- now() dentro del turno, o cambiar temporalmente la hora del turno):
-- select public.crear_pedido('maestro-quiroga', 'retiro', ...);
--   -- (ERROR: Hoy este local solo recibe pedidos para delivery. Elegí delivery.)
-- select public.crear_pedido('maestro-quiroga', 'delivery', ...);   -- (OK)
-- -- Con excepcion solo_retiro vigente, delivery:
--   -- (ERROR: Hoy este local solo recibe pedidos para retiro. Elegí retiro.)
--
-- Programado para un dia solo_delivery (lunes 2026-11-09 21:00, desde el viernes):
-- select public.crear_pedido('maestro-quiroga', 'retiro', ..., p_programado_para => '2026-11-09 21:00:00-03');
--   -- (ERROR: El 09/11 este local solo recibe pedidos para delivery. Elegí delivery.)
-- select public.crear_pedido('maestro-quiroga', 'delivery', ..., p_programado_para => '2026-11-09 21:00:00-03');
--   -- (OK, estado pendiente)
-- -- Lascano el mismo lunes con retiro: OK.
-- -- Programado en un cierre especial: no valida modalidad (OK con cualquiera).
--
-- forzar_cerrado gana a la excepcion:
-- update public.sucursal_estado_manual set modo = 'forzar_cerrado' where sucursal_id = 'maestro-quiroga';
-- update public.excepciones_dia set modo = 'abierto', desde = '19:00', hasta = '23:00' where motivo = 'Prueba';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-11 21:00:00-03');
--   -- (abierto=false, motivo=forzado_cerrado)
-- update public.sucursal_estado_manual set modo = 'automatico' where sucursal_id = 'maestro-quiroga';
-- -- Un cierre especial que cubra el 11/11 tambien gana a la excepcion (motivo=cierre_especial).
-- -- forzar_abierto + excepcion cerrado ese dia -> cierra (la excepcion gana a forzar_abierto).
--
-- Limpieza: delete from public.excepciones_dia where motivo = 'Prueba';
--           update public.sucursal_horarios set acepta_retiro = true
--            where sucursal_id = 'maestro-quiroga' and dia_semana = 1;
-- Permisos: como admin de maestro-quiroga, insertar una excepcion de
-- 'intendente-lascano' debe fallar (RLS); como anon, solo select.

-- ============================================================================
-- ROLLBACK (manual; backup antes si ya hay excepciones cargadas)
-- ============================================================================
-- begin;
-- -- 1. crear_pedido, pm_turnos y sucursal_estado: volver a ejecutar de 024 los
-- --    bloques "pm_turnos" (secc. 4), "sucursal_estado" (secc. 5) y
-- --    "crear_pedido" (secc. 7, create or replace + revoke/grant).
-- --    Antes: drop function if exists public.pm_turnos(text, date, date);
-- drop function if exists public.pm_excepcion_vigente(text, timestamptz);
-- drop function if exists public.pm_modalidades_en(text, timestamptz);
-- drop function if exists public.pm_horario_excepcion_default();
-- drop table if exists public.excepciones_dia;
-- delete from public.config_negocio where clave = 'horario_excepcion_default';
-- alter table public.sucursal_horarios drop constraint if exists sucursal_horarios_modalidad_chk;
-- alter table public.sucursal_horarios drop column if exists acepta_delivery;
-- alter table public.sucursal_horarios drop column if exists acepta_retiro;
-- commit;
