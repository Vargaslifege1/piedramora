-- ============================================================================
-- 033 - Calificacion de visita en MESA (QR por sucursal) + medio punto
-- ============================================================================
-- Reglas de negocio:
--   - El cliente que esta en el local escanea un QR (?mesa=<sucursal>) y califica
--     la visita: Comida (1-5, obligatoria), Atencion (1-5, obligatoria) y un
--     comentario opcional (hasta 500). Se identifica con su TELEFONO.
--   - Premio: 1 medio punto de fidelidad, pero solo si ese telefono NO recibio
--     punto por mesa en los ultimos 7 dias (sin importar la sucursal). Si ya lo
--     recibio, la calificacion se guarda igual con puntos_medios = 0.
--   - Si el telefono no tiene fila en clientes, se crea (nombre 'Cliente de
--     mesa', origen 'registro', acepta_promos = false), igual que
--     registrar_cliente (on conflict do nothing).
--   - Privacidad: solo leen el dueno (todas) y el encargado (su sucursal).
--
-- Que hace esta migracion:
--   1. Tabla calificaciones_mesa (RLS solo lectura admin; nadie escribe directo).
--   2. calificacion_intentos: columna nueva "clave" (pedido_id ya es nullable)
--      y pm_calificacion_mesa_antispam(clave) (interna).
--   3. calificar_mesa(sucursal, telefono, comida, atencion, comentario)
--      -> anon/authenticated.
--   4. stats_calificaciones_mesa(desde, hasta, sucursal, limite, offset)
--      -> solo authenticated (dueno o encargado de su sucursal).
--   5. Trigger pm_pedidos_nombre_cliente_mesa (AFTER INSERT en pedidos): si el
--      cliente tiene el nombre placeholder, lo reemplaza por el nombre real del
--      primer pedido.
--
-- NOMBRE PLACEHOLDER 'Cliente de mesa' - que pasa cuando el telefono despues
-- se registra o pide (verificado en el codigo de 010/019/023/027):
--   - Entrega de un pedido (trigger pm_pedidos_actualizar_clientes, 019): hace
--     "set nombre = excluded.nombre" -> ya pisaba el nombre. OK sin cambios.
--   - registrar_cliente (023): si el telefono nunca pidio, pisa nombre y
--     apellido. OK sin cambios.
--   - crear_pedido (027): NO toca clientes.nombre al crear el pedido (solo
--     acepta_promos). Entonces, hasta que el pedido se entrega (o si se
--     cancela), el cliente quedaba como 'Cliente de mesa'; y si despues se
--     registraba con un pedido ya creado, registrar_cliente conservaba el
--     placeholder (v_pidio = true). Se resuelve con el trigger nuevo del punto 5,
--     SIN reescribir crear_pedido ni registrar_cliente (no se toca nada ya
--     aplicado). Solo actua si el nombre actual es exactamente el placeholder.
--
-- Prerequisitos: 017 (es_dueno, sucursal_admin), 019 (fidelidad), 023
-- (pm_normalizar_telefono), 031 (medios puntos, calificacion_intentos,
-- pm_fidelidad_premiar). Las migraciones 001 a 032 NO se modifican.
-- stats_calificaciones (031) NO se modifica.
--
-- LIMITACIONES CONOCIDAS:
--   - Las sucursales validas van fijas en el check de calificaciones_mesa
--     (maestro-quiroga, intendente-lascano). Una sucursal nueva requiere otra
--     migracion.
--   - No se verifica que la persona este realmente en el local: el QR es
--     publico. El limite de 1 punto por telefono por semana y el anti-spam
--     acotan el abuso.
--   - Un cliente de mesa que no tiene programa de fidelidad activo (config
--     null) guarda la calificacion sin punto y sin crear fila en clientes.
--
-- IMPORTANTE: hacer BACKUP antes de aplicar. Idempotente (se puede ejecutar
-- mas de una vez).
--
-- ROLLBACK (al final del archivo, comentado): no hay funciones reescritas, asi
-- que se revierte borrando lo agregado.
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.calificacion_intentos') is null
     or to_regprocedure('public.pm_fidelidad_premiar(text, integer, integer, uuid, jsonb)') is null
     or to_regprocedure('public.pm_normalizar_telefono(text)') is null
     or to_regprocedure('public.pm_fidelidad_config()') is null
     or to_regprocedure('public.pm_fidelidad_nombre_producto(text)') is null
     or to_regprocedure('public.es_dueno()') is null
     or to_regprocedure('public.sucursal_admin()') is null then
    raise exception '033: faltan las migraciones 017/019/023/031.';
  end if;
end
$$;

-- ============================================================================
-- 1. Tabla calificaciones_mesa
-- ============================================================================
create table if not exists public.calificaciones_mesa (
  id uuid primary key default gen_random_uuid(),
  sucursal text not null,
  -- Telefono normalizado (10 digitos), igual que clientes.telefono.
  telefono text not null,
  comida smallint not null,
  atencion smallint not null,
  comentario text,
  -- 1 si esta calificacion sumo medio punto de fidelidad, 0 si no.
  puntos_medios smallint not null default 0,
  creado_en timestamptz not null default now(),

  constraint calificaciones_mesa_sucursal_chk
    check (sucursal in ('maestro-quiroga', 'intendente-lascano')),
  constraint calificaciones_mesa_telefono_chk
    check (telefono ~ '^[0-9]{8,15}$'),
  constraint calificaciones_mesa_comida_chk check (comida between 1 and 5),
  constraint calificaciones_mesa_atencion_chk check (atencion between 1 and 5),
  constraint calificaciones_mesa_comentario_chk
    check (comentario is null or char_length(comentario) between 1 and 500),
  constraint calificaciones_mesa_puntos_chk check (puntos_medios in (0, 1))
);

create index if not exists calificaciones_mesa_sucursal_fecha_idx
  on public.calificaciones_mesa (sucursal, creado_en desc);
create index if not exists calificaciones_mesa_fecha_idx
  on public.calificaciones_mesa (creado_en desc);
-- Ventana de 7 dias: ultima calificacion con punto de un telefono.
create index if not exists calificaciones_mesa_tel_punto_idx
  on public.calificaciones_mesa (telefono, creado_en desc)
  where puntos_medios = 1;

comment on table public.calificaciones_mesa is
  'Calificaciones de visita en mesa por QR (033). Solo las crea calificar_mesa(); solo las lee el dueno o el encargado de la sucursal.';

alter table public.calificaciones_mesa enable row level security;

revoke all on public.calificaciones_mesa from public, anon, authenticated;
grant select on public.calificaciones_mesa to authenticated;

-- Sin policies ni grants de insert/update/delete: nadie escribe directo.
drop policy if exists "Calificaciones mesa lectura admin" on public.calificaciones_mesa;
create policy "Calificaciones mesa lectura admin"
  on public.calificaciones_mesa
  for select
  to authenticated
  using (
    public.es_dueno()
    or sucursal = public.sucursal_admin()
  );

-- ============================================================================
-- 2. Anti-spam de mesa
-- ============================================================================
-- calificacion_intentos.pedido_id ya es NULLABLE (031: "pedido_id uuid"), asi
-- que los intentos de mesa se guardan con pedido_id = null y una clave propia.
-- El anti-spam de pedidos no cambia: filtra por pedido_id y las filas de mesa
-- tienen pedido_id null (nunca coinciden).
alter table public.calificacion_intentos
  add column if not exists clave text;

alter table public.calificacion_intentos
  drop constraint if exists calificacion_intentos_clave_largo_chk;
alter table public.calificacion_intentos
  add constraint calificacion_intentos_clave_largo_chk
  check (clave is null or char_length(clave) <= 100);

create index if not exists calificacion_intentos_clave_fecha_idx
  on public.calificacion_intentos (clave, creado_en desc);

-- Registra el intento y devuelve false si se superaron los limites.
-- Umbrales (ajustables): 10 por clave (sucursal + telefono) y 60 por IP cada
-- 10 minutos, 200 globales cada 5 minutos (la IP y el global se comparten con
-- el anti-spam de pedidos).
create or replace function public.pm_calificacion_mesa_antispam(p_clave text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ip text;
  v_n integer;
  v_clave text := left(p_clave, 100);
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
   where clave = v_clave and creado_en > now() - interval '10 minutes';
  if v_n >= 10 then
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

  insert into public.calificacion_intentos (pedido_id, clave, ip)
  values (null, v_clave, v_ip);
  return true;
end;
$$;

revoke all on function public.pm_calificacion_mesa_antispam(text)
  from public, anon, authenticated;

comment on function public.pm_calificacion_mesa_antispam(text) is
  'Anti-spam de calificaciones de mesa (clave mesa:<sucursal>:<telefono>). Solo uso interno (033).';

-- ============================================================================
-- 3. calificar_mesa
-- ============================================================================
-- Devuelve {ok, estado, ...}:
--   ok=true,  estado='ok' -> sumo_punto (bool), medios_en_ciclo, faltan_medios,
--                            premio_generado (bool), proximo_premio
--                            (medios_en_ciclo / faltan_medios / proximo_premio
--                            son null si el programa de fidelidad esta inactivo)
--   ok=false, estado en: limite | invalido | error   (+ mensaje)
-- Nunca lanza excepciones al cliente. El intento de anti-spam queda registrado
-- aunque la calificacion falle (el trabajo real va en un bloque interno).
create or replace function public.calificar_mesa(
  p_sucursal text,
  p_telefono text,
  p_comida integer,
  p_atencion integer,
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
  v_suc text := nullif(btrim(coalesce(p_sucursal, '')), '');
  v_tel text;
  v_com text;
  v_cfg jsonb;
  v_ciclo integer;
  v_cli public.clientes%rowtype;
  v_h0 integer := 0;
  v_medios smallint := 0;
  v_gen integer := 0;
  v_h integer;
  v_pos integer;
  v_sig jsonb;
  v_meta integer;
  v_prox jsonb := null;
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);

  if not public.pm_calificacion_mesa_antispam(
       'mesa:' || coalesce(v_suc, '?') || ':' || coalesce(v_tel, '?')) then
    return jsonb_build_object('ok', false, 'estado', 'limite',
      'mensaje', 'Probá de nuevo en unos minutos.');
  end if;

  begin
    if v_suc is null or v_suc not in ('maestro-quiroga', 'intendente-lascano') then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'No encontramos esa sucursal.');
    end if;
    if v_tel is null then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'Revisá el teléfono: tiene que ser un celular de Argentina con código de área.');
    end if;
    if p_comida is null or p_comida not between 1 and 5 then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'Elegí de 1 a 5 estrellas para la comida.');
    end if;
    if p_atencion is null or p_atencion not between 1 and 5 then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'Elegí de 1 a 5 estrellas para la atención.');
    end if;
    v_com := nullif(btrim(coalesce(p_comentario, '')), '');
    if v_com is not null and char_length(v_com) > 500 then
      return jsonb_build_object('ok', false, 'estado', 'invalido',
        'mensaje', 'El comentario puede tener hasta 500 caracteres.');
    end if;

    v_cfg := public.pm_fidelidad_config();

    if v_cfg is not null then
      -- Crea la fila de fidelidad si no existe (mismo camino que registrar_cliente).
      insert into public.clientes (
        telefono, nombre, acepta_promos, registrado_en, origen
      ) values (
        v_tel, 'Cliente de mesa', false, now(), 'registro'
      )
      on conflict (telefono) do nothing;

      -- Bloqueo de la fila: serializa envios simultaneos del mismo telefono, asi
      -- el chequeo de los 7 dias de abajo no se puede saltear con dos pedidos
      -- en paralelo.
      select * into v_cli
        from public.clientes
       where telefono = v_tel
       for update;

      if found then
        v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;

        if not exists (
          select 1
            from public.calificaciones_mesa m
           where m.telefono = v_tel
             and m.puntos_medios = 1
             and m.creado_en > now() - make_interval(days => c_dias)
        ) then
          update public.clientes
             set fidelidad_calificaciones = fidelidad_calificaciones + 1
           where telefono = v_tel;

          -- Sin pedido de origen (null): no choca con premios_origen_tipo_uidx.
          v_gen := public.pm_fidelidad_premiar(v_tel, v_h0, v_h0 + 1, null, v_cfg);
          v_medios := 1;
        end if;
      end if;
    end if;

    insert into public.calificaciones_mesa (
      sucursal, telefono, comida, atencion, comentario, puntos_medios
    ) values (
      v_suc, v_tel, p_comida, p_atencion, v_com, v_medios
    );

    -- Progreso del ciclo (misma cuenta que mi_progreso_fidelidad, sin su anti-spam).
    if v_cfg is not null then
      v_ciclo := (v_cfg ->> 'ciclo')::integer;
      v_h := v_h0 + v_medios;
      v_pos := v_h % (2 * v_ciclo);

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

      v_prox := jsonb_build_object(
        'tipo', v_sig ->> 'tipo',
        'valor', case when v_sig ->> 'tipo' = 'descuento_porcentaje'
                      then (v_sig ->> 'valor')::numeric end,
        'producto', case when v_sig ->> 'tipo' = 'producto_gratis'
                         then public.pm_fidelidad_nombre_producto(v_sig ->> 'producto_id') end);
    end if;

    return jsonb_build_object(
      'ok', true,
      'estado', 'ok',
      'sumo_punto', v_medios = 1,
      'medios_en_ciclo', case when v_cfg is not null then v_pos end,
      'faltan_medios', case when v_cfg is not null then v_meta - v_pos end,
      'premio_generado', v_gen > 0,
      'proximo_premio', v_prox);
  exception
    when others then
      -- Se deshace todo el bloque (punto incluido): nunca queda a medias.
      return jsonb_build_object('ok', false, 'estado', 'error',
        'mensaje', 'No pudimos guardar tu calificación. Probá de nuevo en unos minutos.');
  end;
end;
$$;

revoke all on function public.calificar_mesa(text, text, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.calificar_mesa(text, text, integer, integer, text)
  to anon, authenticated;

comment on function public.calificar_mesa(text, text, integer, integer, text) is
  'Califica la visita en mesa por telefono (QR por sucursal). Suma 0,5 de fidelidad si el telefono no recibio punto de mesa en 7 dias. Todo se decide en el servidor (033)';

-- ============================================================================
-- 4. stats_calificaciones_mesa
-- ============================================================================
-- Promedios y totales sobre TODAS las calificaciones del filtro, mas una pagina
-- de filas (mas nuevas primero). Rango [p_desde, p_hasta) sobre creado_en.
-- Permisos: el dueno ve todo y puede filtrar por sucursal; el encargado
-- siempre ve solo su sucursal (si pide otra, error).
-- Devuelve: desde, hasta, sucursal, promedio_comida, promedio_atencion, total,
-- con_comentario, filas [{id, sucursal, telefono, comida, atencion, comentario,
-- puntos_medios, creado_en}].
create or replace function public.stats_calificaciones_mesa(
  p_desde timestamptz default null,
  p_hasta timestamptz default null,
  p_sucursal text default null,
  p_limite integer default 50,
  p_offset integer default 0
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
  v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
  v_off integer := greatest(coalesce(p_offset, 0), 0);
  v_prom_comida numeric;
  v_prom_atencion numeric;
  v_total bigint;
  v_con_com bigint;
  v_filas jsonb;
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

  select round(avg(m.comida), 2),
         round(avg(m.atencion), 2),
         count(*),
         count(m.comentario)
    into v_prom_comida, v_prom_atencion, v_total, v_con_com
    from public.calificaciones_mesa m
   where (p_desde is null or m.creado_en >= p_desde)
     and (p_hasta is null or m.creado_en < p_hasta)
     and (v_suc is null or m.sucursal = v_suc);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.creado_en desc, x.id desc), '[]'::jsonb)
    into v_filas
    from (
      select m.id, m.sucursal, m.telefono, m.comida, m.atencion,
             m.comentario, m.puntos_medios, m.creado_en
        from public.calificaciones_mesa m
       where (p_desde is null or m.creado_en >= p_desde)
         and (p_hasta is null or m.creado_en < p_hasta)
         and (v_suc is null or m.sucursal = v_suc)
       order by m.creado_en desc, m.id desc
       limit v_lim offset v_off
    ) x;

  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'sucursal', v_suc,
    'promedio_comida', v_prom_comida,
    'promedio_atencion', v_prom_atencion,
    'total', v_total,
    'con_comentario', v_con_com,
    'filas', v_filas);
end;
$$;

revoke all on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer)
  from public, anon;
grant execute on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer)
  to authenticated;

comment on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer) is
  'Promedios, totales y lista de calificaciones de mesa. Dueno: todo o una sucursal; encargado: solo la suya (033).';

-- ============================================================================
-- 5. Trigger: el nombre real pisa al placeholder 'Cliente de mesa'
-- ============================================================================
-- AFTER INSERT en pedidos. Solo toca clientes cuyo nombre es EXACTAMENTE el
-- placeholder; un cliente con nombre real no se modifica. cliente_nombre ya
-- viene validado (2 a 80) por crear_pedido y por el check de pedidos.
create or replace function public.pm_pedidos_nombre_cliente_mesa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.clientes c
     set nombre = btrim(new.cliente_nombre)
   where c.telefono = new.cliente_telefono
     and c.nombre = 'Cliente de mesa'
     and char_length(btrim(coalesce(new.cliente_nombre, ''))) between 2 and 80
     and btrim(new.cliente_nombre) <> 'Cliente de mesa';
  return new;
end;
$$;

revoke all on function public.pm_pedidos_nombre_cliente_mesa()
  from public, anon, authenticated;

comment on function public.pm_pedidos_nombre_cliente_mesa() is
  'Reemplaza el nombre placeholder "Cliente de mesa" por el del primer pedido del telefono (033).';

drop trigger if exists pm_pedidos_nombre_cliente_mesa_trg on public.pedidos;
create trigger pm_pedidos_nombre_cliente_mesa_trg
  after insert on public.pedidos
  for each row
  execute function public.pm_pedidos_nombre_cliente_mesa();

commit;

-- ============================================================================
-- ROLLBACK (descomentar y ejecutar). No se reescribio ninguna funcion anterior.
-- ============================================================================
--
-- drop trigger if exists pm_pedidos_nombre_cliente_mesa_trg on public.pedidos;
-- drop function if exists public.pm_pedidos_nombre_cliente_mesa();
-- drop function if exists public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer);
-- drop function if exists public.calificar_mesa(text, text, integer, integer, text);
-- drop function if exists public.pm_calificacion_mesa_antispam(text);
-- drop index if exists public.calificacion_intentos_clave_fecha_idx;
-- alter table public.calificacion_intentos drop constraint if exists calificacion_intentos_clave_largo_chk;
-- alter table public.calificacion_intentos drop column if exists clave;
-- drop table if exists public.calificaciones_mesa;
-- -- Los clientes creados con nombre 'Cliente de mesa' y los medios puntos ya
-- -- dados quedan (igual que el resto de la fidelidad).
