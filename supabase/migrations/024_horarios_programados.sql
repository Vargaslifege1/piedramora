-- ============================================================================
-- 024_horarios_programados.sql
-- Horarios por sucursal en la base, cierres especiales, estado manual
-- (forzar abierto/cerrado) y pedidos programados.
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP COMPLETO de la base (Supabase > Database >
-- Backups, o pg_dump). Esta migracion agrega tablas, una columna a pedidos y
-- REEMPLAZA crear_pedido (funcion de dinero): se dropea la firma de 15
-- parametros y se crea la de 16.
--
-- Prerrequisitos (ya aplicadas): 010, 011, 013, 017 (es_dueno, sucursal_admin),
-- 018, 019, 020, 021, 023. NO se modifica ninguna migracion anterior ni
-- pm_calcular_pedido (sigue siendo la de 021). El trigger de estados (021) y
-- la fidelidad no se tocan.
--
-- Que hace:
--   1. sucursal_horarios, cierres_especiales, sucursal_estado_manual (con RLS)
--      + seed con los horarios de data/sucursales.json (ambas sucursales:
--      todos los dias 20:30 a 00:30; vie y sab hasta 01:00).
--   2. sucursal_estado(sucursal, ahora): estado abierto/cerrado en jsonb.
--   3. pedidos.programado_para (timestamptz, null). El grant de UPDATE por
--      columnas de pedidos NO cambia (nadie del cliente puede editarla).
--   4. crear_pedido con p_programado_para (16 parametros). Reglas abajo.
--
-- Convenciones:
--   - dia_semana: 0 = domingo ... 6 = sabado (igual que extract(dow)). Es el
--     dia en que EMPIEZA el turno.
--   - Un turno con hasta <= desde cruza la medianoche. Ej.: viernes 20:30 a
--     01:00 sigue vigente el sabado a las 00:10. Un turno dura como maximo
--     24 h (hasta = desde = 24 h).
--   - Corte exacto: el turno es [desde, hasta): a las 00:30:00 ya esta cerrado.
--   - Todo se calcula en America/Argentina/Buenos_Aires.
--   - Un cierre especial cubre dias de calendario completos (00:00 del primer
--     dia a 24:00 del ultimo, hora Argentina) y corta tambien un turno que
--     venga del dia anterior.
--   - Prioridad: forzar_cerrado > cierre_especial > forzar_abierto > horario.
--   - ANTI-LOCKOUT: una sucursal SIN ningun turno cargado se considera
--     abierta (si se borran todos los horarios, la carta no se bloquea).
--     Ademas el dueno siempre puede usar forzar_abierto.
--
-- Reglas de crear_pedido (el precio, descuentos y cupones se calculan al
-- momento de pedir, igual que antes):
--   - Sin p_programado_para: si la sucursal esta abierta, pedido normal; si
--     esta cerrada (cualquier motivo) se rechaza con "Cerrado, abrimos a las
--     HH:MM. Podes programar tu pedido." (o "Cerrado hasta el DD/MM. ...").
--   - Con p_programado_para: debe ser futuro y a no mas de
--     config_negocio 'programar_max_dias' dias (default 15), y caer dentro de
--     un horario de apertura de esa sucursal. Excepcion: si ese dia esta en
--     un cierre especial, o es HOY y la sucursal esta en modo manual forzado,
--     se permite igual; el pedido queda 'pendiente' hasta que el local lo
--     acepte. Se guarda programado_para; el estado sigue 'pendiente'.
--
-- Idempotente: se puede volver a correr (el seed solo inserta si la sucursal
-- no tiene horarios; las policies se recrean; crear_pedido se redefine).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Tablas
-- ----------------------------------------------------------------------------
create table if not exists public.sucursal_horarios (
  id          bigint generated always as identity primary key,
  sucursal_id text     not null,
  dia_semana  smallint not null,
  desde       time     not null,
  hasta       time     not null,

  constraint sucursal_horarios_sucursal_chk
    check (sucursal_id in ('maestro-quiroga', 'intendente-lascano')),
  constraint sucursal_horarios_dia_chk
    check (dia_semana between 0 and 6),
  constraint sucursal_horarios_turno_uk
    unique (sucursal_id, dia_semana, desde)
);

comment on table public.sucursal_horarios is
  'Turnos de atencion por sucursal y dia (0=domingo..6=sabado, dia en que empieza el turno). hasta <= desde cruza la medianoche. Varios turnos por dia permitidos.';

create table if not exists public.cierres_especiales (
  id          bigint generated always as identity primary key,
  sucursal_id text,                       -- null = todas las sucursales
  desde       date not null,
  hasta       date not null,
  motivo      text,
  created_at  timestamptz not null default now(),

  constraint cierres_especiales_sucursal_chk
    check (sucursal_id is null or sucursal_id in ('maestro-quiroga', 'intendente-lascano')),
  constraint cierres_especiales_fechas_chk
    check (hasta >= desde),
  constraint cierres_especiales_motivo_chk
    check (motivo is null or char_length(motivo) <= 200)
);

comment on table public.cierres_especiales is
  'Cierres por dias de calendario completos (desde..hasta inclusive, hora Argentina). sucursal_id null = todas.';

create table if not exists public.sucursal_estado_manual (
  sucursal_id    text primary key,
  modo           text not null default 'automatico',
  actualizado_en timestamptz not null default now(),

  constraint sucursal_estado_manual_sucursal_chk
    check (sucursal_id in ('maestro-quiroga', 'intendente-lascano')),
  constraint sucursal_estado_manual_modo_chk
    check (modo in ('automatico', 'forzar_abierto', 'forzar_cerrado'))
);

comment on table public.sucursal_estado_manual is
  'Interruptor manual por sucursal: automatico (usa horarios), forzar_abierto o forzar_cerrado.';

-- Indices (la unique de horarios ya cubre sucursal+dia)
create index if not exists cierres_especiales_sucursal_fechas_idx
  on public.cierres_especiales (sucursal_id, desde, hasta);
create index if not exists cierres_especiales_fechas_idx
  on public.cierres_especiales (desde, hasta);

-- ----------------------------------------------------------------------------
-- 2. RLS: lectura publica; escritura dueno / admin de su sucursal
-- ----------------------------------------------------------------------------
alter table public.sucursal_horarios enable row level security;
alter table public.cierres_especiales enable row level security;
alter table public.sucursal_estado_manual enable row level security;

revoke all on public.sucursal_horarios, public.cierres_especiales, public.sucursal_estado_manual
  from anon, authenticated;
grant select on public.sucursal_horarios, public.cierres_especiales, public.sucursal_estado_manual
  to anon, authenticated;
grant insert, update, delete on public.sucursal_horarios to authenticated;
grant insert, update, delete on public.cierres_especiales to authenticated;
grant insert, update, delete on public.sucursal_estado_manual to authenticated;

-- sucursal_horarios
drop policy if exists "Horarios lectura publica" on public.sucursal_horarios;
create policy "Horarios lectura publica" on public.sucursal_horarios
  for select to anon, authenticated using (true);

drop policy if exists "Horarios alta admin" on public.sucursal_horarios;
create policy "Horarios alta admin" on public.sucursal_horarios
  for insert to authenticated
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Horarios edicion admin" on public.sucursal_horarios;
create policy "Horarios edicion admin" on public.sucursal_horarios
  for update to authenticated
  using (public.es_dueno() or sucursal_id = public.sucursal_admin())
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Horarios baja admin" on public.sucursal_horarios;
create policy "Horarios baja admin" on public.sucursal_horarios
  for delete to authenticated
  using (public.es_dueno() or sucursal_id = public.sucursal_admin());

-- cierres_especiales: solo el dueno escribe
drop policy if exists "Cierres lectura publica" on public.cierres_especiales;
create policy "Cierres lectura publica" on public.cierres_especiales
  for select to anon, authenticated using (true);

drop policy if exists "Cierres alta dueno" on public.cierres_especiales;
create policy "Cierres alta dueno" on public.cierres_especiales
  for insert to authenticated with check (public.es_dueno());

drop policy if exists "Cierres edicion dueno" on public.cierres_especiales;
create policy "Cierres edicion dueno" on public.cierres_especiales
  for update to authenticated
  using (public.es_dueno()) with check (public.es_dueno());

drop policy if exists "Cierres baja dueno" on public.cierres_especiales;
create policy "Cierres baja dueno" on public.cierres_especiales
  for delete to authenticated using (public.es_dueno());

-- sucursal_estado_manual: dueno todo; admin de sucursal alta/edicion de la suya
drop policy if exists "Estado manual lectura publica" on public.sucursal_estado_manual;
create policy "Estado manual lectura publica" on public.sucursal_estado_manual
  for select to anon, authenticated using (true);

drop policy if exists "Estado manual alta admin" on public.sucursal_estado_manual;
create policy "Estado manual alta admin" on public.sucursal_estado_manual
  for insert to authenticated
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Estado manual edicion admin" on public.sucursal_estado_manual;
create policy "Estado manual edicion admin" on public.sucursal_estado_manual
  for update to authenticated
  using (public.es_dueno() or sucursal_id = public.sucursal_admin())
  with check (public.es_dueno() or sucursal_id = public.sucursal_admin());

drop policy if exists "Estado manual baja dueno" on public.sucursal_estado_manual;
create policy "Estado manual baja dueno" on public.sucursal_estado_manual
  for delete to authenticated using (public.es_dueno());

-- ----------------------------------------------------------------------------
-- 3. Seed (data/sucursales.json: apertura 20:30, cierre 00:30, vie/sab 01:00,
--    cerradoLunes = false). Solo si la sucursal no tiene ningun horario.
--    dia_semana: 0 dom, 1 lun, ..., 5 vie, 6 sab.
-- ----------------------------------------------------------------------------
insert into public.sucursal_horarios (sucursal_id, dia_semana, desde, hasta)
select s.id, d.dia, time '20:30',
       case when d.dia in (5, 6) then time '01:00' else time '00:30' end
  from (values ('maestro-quiroga'), ('intendente-lascano')) as s(id)
 cross join generate_series(0, 6) as d(dia)
 where not exists (
   select 1 from public.sucursal_horarios h where h.sucursal_id = s.id)
on conflict (sucursal_id, dia_semana, desde) do nothing;

insert into public.sucursal_estado_manual (sucursal_id, modo)
values ('maestro-quiroga', 'automatico'), ('intendente-lascano', 'automatico')
on conflict (sucursal_id) do nothing;

insert into public.config_negocio (clave, valor)
values ('programar_max_dias', '15'::jsonb)
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- 4. Funciones auxiliares (internas: sin permisos para anon/authenticated;
--    las usan las funciones SECURITY DEFINER de abajo)
-- ----------------------------------------------------------------------------

-- Turnos (intervalos [ini, fin) en timestamptz) que EMPIEZAN entre dos fechas
-- locales (inclusive).
create or replace function public.pm_turnos(
  p_sucursal_id text, p_desde date, p_hasta date)
returns table (ini timestamptz, fin timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select ((d.dia + h.desde) at time zone 'America/Argentina/Buenos_Aires'),
         (((d.dia + case when h.hasta <= h.desde then 1 else 0 end) + h.hasta)
           at time zone 'America/Argentina/Buenos_Aires')
    from generate_series(p_desde::timestamp, p_hasta::timestamp, interval '1 day') as g(ts)
   cross join lateral (select g.ts::date as dia) d
    join public.sucursal_horarios h
      on h.sucursal_id = p_sucursal_id
     and h.dia_semana = extract(dow from d.dia)::int;
$$;

-- true si el instante cae dentro de algun turno (sin mirar cierres).
create or replace function public.pm_en_turno(p_sucursal_id text, p_t timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.pm_turnos(
             p_sucursal_id,
             ((p_t at time zone 'America/Argentina/Buenos_Aires')::date - 1),
             ((p_t at time zone 'America/Argentina/Buenos_Aires')::date)) t
     where t.ini <= p_t and p_t < t.fin);
$$;

-- true si el DIA local del instante esta en un cierre especial.
create or replace function public.pm_en_cierre(p_sucursal_id text, p_t timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.cierres_especiales c
     where (c.sucursal_id is null or c.sucursal_id = p_sucursal_id)
       and (p_t at time zone 'America/Argentina/Buenos_Aires')::date between c.desde and c.hasta);
$$;

-- Proxima apertura estrictamente posterior a p_t (busca hasta 45 dias), o null.
-- Candidatos: inicios de turno fuera de cierre, y fines de cierre que caen
-- dentro de un turno (turno ya empezado que un cierre habia cortado).
create or replace function public.pm_proxima_apertura(p_sucursal_id text, p_t timestamptz)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select min(x.t) from (
    select t.ini as t
      from public.pm_turnos(
             p_sucursal_id,
             ((p_t at time zone 'America/Argentina/Buenos_Aires')::date - 1),
             ((p_t at time zone 'America/Argentina/Buenos_Aires')::date + 45)) t
     where t.ini > p_t
       and not public.pm_en_cierre(p_sucursal_id, t.ini)
    union all
    select (c.hasta + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'
      from public.cierres_especiales c
     where (c.sucursal_id is null or c.sucursal_id = p_sucursal_id)
       and ((c.hasta + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires') > p_t
       and ((c.hasta + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
           < p_t + interval '45 days'
       and public.pm_en_turno(p_sucursal_id,
             (c.hasta + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
       and not public.pm_en_cierre(p_sucursal_id,
             (c.hasta + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  ) x;
$$;

revoke all on function public.pm_turnos(text, date, date) from public, anon, authenticated;
revoke all on function public.pm_en_turno(text, timestamptz) from public, anon, authenticated;
revoke all on function public.pm_en_cierre(text, timestamptz) from public, anon, authenticated;
revoke all on function public.pm_proxima_apertura(text, timestamptz) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. sucursal_estado (publica)
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
begin
  select valor into v_coords from public.config_negocio where clave = 'sucursales_coords';
  if p_sucursal_id is null or v_coords is null or (v_coords -> p_sucursal_id) is null then
    raise exception 'La sucursal no existe.';
  end if;

  select modo into v_modo from public.sucursal_estado_manual where sucursal_id = p_sucursal_id;
  v_modo := coalesce(v_modo, 'automatico');

  if v_modo = 'forzar_cerrado' then
    v_abierto := false;
    v_motivo := 'forzado_cerrado';
    v_prox := public.pm_proxima_apertura(p_sucursal_id, p_ahora);   -- informativo

  elsif public.pm_en_cierre(p_sucursal_id, p_ahora) then
    v_abierto := false;
    v_motivo := 'cierre_especial';
    v_prox := public.pm_proxima_apertura(p_sucursal_id, p_ahora);

  elsif v_modo = 'forzar_abierto' then
    v_abierto := true;
    v_motivo := 'forzado_abierto';

  elsif not exists (select 1 from public.sucursal_horarios where sucursal_id = p_sucursal_id) then
    -- Anti-lockout: sin horarios cargados no se bloquea la sucursal.
    v_abierto := true;
    v_motivo := 'horario';

  elsif public.pm_en_turno(p_sucursal_id, p_ahora) then
    v_abierto := true;
    v_motivo := 'horario';
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

  return jsonb_build_object(
    'abierto', v_abierto,
    'motivo', v_motivo,
    'proxima_apertura', case when v_prox is null then null else
      to_char(v_prox at time zone v_tz, 'YYYY-MM-DD"T"HH24:MI:SS"-03:00"') end,
    'cierra_a', case when v_cierra is null then null else
      to_char(v_cierra at time zone v_tz, 'YYYY-MM-DD"T"HH24:MI:SS"-03:00"') end);
end;
$$;

revoke all on function public.sucursal_estado(text, timestamptz) from public;
grant execute on function public.sucursal_estado(text, timestamptz) to anon, authenticated;

comment on function public.sucursal_estado(text, timestamptz) is
  'Estado de la sucursal en hora Argentina: {abierto, motivo, proxima_apertura, cierra_a}. Prioridad: forzar_cerrado > cierre_especial > forzar_abierto > horario.';

-- ----------------------------------------------------------------------------
-- 6. pedidos.programado_para
-- ----------------------------------------------------------------------------
-- Sin tocar el grant de UPDATE por columnas (016/017): solo crear_pedido
-- (SECURITY DEFINER) la escribe. El SELECT de pedidos ya es a nivel tabla.
alter table public.pedidos add column if not exists programado_para timestamptz;

comment on column public.pedidos.programado_para is
  'Fecha/hora para la que el cliente programo el pedido. Null = pedido para ahora. El estado sigue siendo pendiente hasta que el local lo acepte.';

create index if not exists pedidos_programado_para_idx
  on public.pedidos (sucursal_id, programado_para)
  where programado_para is not null;

-- ----------------------------------------------------------------------------
-- 7. crear_pedido (base: la version ACTUAL de 023, con p_programado_para)
-- ----------------------------------------------------------------------------
drop function if exists public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean);

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
  'Crea un pedido validando precios, cupon, premio y horario en el servidor. Con p_programado_para agenda el pedido (futuro, max programar_max_dias, dentro del horario). Ignora totales y descuentos del cliente.';

commit;

-- ============================================================================
-- CASOS DE PRUEBA (ejecutar a mano; esperado entre parentesis).
-- 2026-11-06 es viernes; Argentina = UTC-3 (-03:00).
-- ============================================================================
-- Estado (sucursal_estado):
-- select public.sucursal_estado('maestro-quiroga', '2026-11-06 20:30:00-03');
--   -- (abierto=true, motivo=horario, cierra_a=2026-11-07T01:00:00-03:00)
-- select public.sucursal_estado('maestro-quiroga', '2026-11-06 20:29:59-03');
--   -- (abierto=false, fuera_de_horario, proxima_apertura=2026-11-06T20:30:00-03:00)
-- -- Turno que cruza la medianoche: jueves 00:10 sigue el turno del miercoles.
-- select public.sucursal_estado('maestro-quiroga', '2026-11-05 00:10:00-03');
--   -- (abierto=true, cierra_a=2026-11-05T00:30:00-03:00)
-- -- 00:30 exacto de un dia de semana: ya cerrado.
-- select public.sucursal_estado('maestro-quiroga', '2026-11-05 00:30:00-03');
--   -- (abierto=false, fuera_de_horario)
-- -- Viernes a la noche, turno hasta 01:00 del sabado: 00:59 abierto, 01:00 cerrado.
-- select public.sucursal_estado('maestro-quiroga', '2026-11-07 00:59:00-03');   -- (abierto=true)
-- select public.sucursal_estado('maestro-quiroga', '2026-11-07 01:00:00-03');   -- (abierto=false)
-- -- Sucursal inexistente:
-- select public.sucursal_estado('no-existe');   -- (ERROR: La sucursal no existe.)
--
-- Cierre especial de varios dias (cubre tambien el turno que viene del dia anterior):
-- insert into public.cierres_especiales (sucursal_id, desde, hasta, motivo)
--   values (null, '2026-12-24', '2026-12-26', 'Prueba');
-- select public.sucursal_estado('maestro-quiroga', '2026-12-25 21:00:00-03');
--   -- (abierto=false, cierre_especial, proxima_apertura=2026-12-27T20:30:00-03:00)
-- select public.sucursal_estado('maestro-quiroga', '2026-12-24 00:10:00-03');
--   -- (abierto=false: cierre_especial; el turno del 23 se corta a medianoche)
-- select public.sucursal_estado('maestro-quiroga', '2026-12-27 20:30:00-03');   -- (abierto=true)
-- delete from public.cierres_especiales where motivo = 'Prueba';
--
-- Forzar cerrado (gana a todo) / forzar abierto (no gana a un cierre especial):
-- update public.sucursal_estado_manual set modo = 'forzar_cerrado' where sucursal_id = 'maestro-quiroga';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-06 21:00:00-03');
--   -- (abierto=false, forzado_cerrado)
-- update public.sucursal_estado_manual set modo = 'forzar_abierto' where sucursal_id = 'maestro-quiroga';
-- select public.sucursal_estado('maestro-quiroga', '2026-11-06 12:00:00-03');
--   -- (abierto=true, forzado_abierto)
-- update public.sucursal_estado_manual set modo = 'automatico' where sucursal_id = 'maestro-quiroga';
--
-- crear_pedido (usar items validos de la carta; p_programado_para en timestamptz):
-- -- Sucursal cerrada y sin programar -> ERROR "Cerrado, abrimos a las 20:30. Podés programar tu pedido."
-- -- Programar a 16 dias -> ERROR "Solo podés programar pedidos hasta 15 días adelante."
-- -- Programar a ~15 dias (un poco menos, para no pasar el limite por los
-- --   segundos que tarda la llamada) a las 21:00 hora Argentina -> OK, estado
-- --   'pendiente'. Ej.: ((current_date + 15) + time '21:00') at time zone
-- --   'America/Argentina/Buenos_Aires' - interval '1 hour' si hace falta.
-- -- Programar en un dia cerrado (cierre especial) a cualquier hora -> OK, queda pendiente.
-- -- Programar a las 15:00 en un dia normal (fuera de horario) -> ERROR "Ese horario está fuera de nuestro horario de atención...".
-- -- Programar en el pasado -> ERROR "La fecha y hora programadas tienen que ser futuras."
-- -- Sucursal 'no-existe' -> ERROR "La sucursal no existe."
-- -- Verificar: select numero_orden, estado, programado_para from public.pedidos order by created_at desc limit 5;
-- -- Reintento con la misma p_idempotency_key devuelve el mismo pedido (sin revalidar horario).
-- Permisos: como admin de maestro-quiroga, update de sucursal_estado_manual de
-- 'intendente-lascano' debe afectar 0 filas; insertar en cierres_especiales debe fallar.

-- ============================================================================
-- ROLLBACK (manual; hacer antes un backup si ya hay pedidos programados)
-- ============================================================================
-- begin;
-- drop function if exists public.crear_pedido(
--   text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz);
-- -- Recrear la firma de 15 parametros: volver a ejecutar crear_pedido de 023
-- -- (bloque "create or replace function public.crear_pedido(" + su revoke/grant de 020).
-- drop function if exists public.sucursal_estado(text, timestamptz);
-- drop function if exists public.pm_proxima_apertura(text, timestamptz);
-- drop function if exists public.pm_en_cierre(text, timestamptz);
-- drop function if exists public.pm_en_turno(text, timestamptz);
-- drop function if exists public.pm_turnos(text, date, date);
-- drop index if exists public.pedidos_programado_para_idx;
-- alter table public.pedidos drop column if exists programado_para;   -- pierde los datos
-- drop table if exists public.sucursal_estado_manual, public.cierres_especiales, public.sucursal_horarios;
-- delete from public.config_negocio where clave = 'programar_max_dias';
-- commit;
