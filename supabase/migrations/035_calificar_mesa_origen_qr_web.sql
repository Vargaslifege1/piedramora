-- ============================================================================
-- 035 - Boton "Calificanos": origen de la calificacion de mesa (qr | web) y
--       reglas de punto segun el origen
-- ============================================================================
-- Reglas de punto de calificar_mesa:
--   - Origen QR = el link trae la clave valida de esa sucursal
--     (?mesa=<sucursal>&k=<clave>, validada contra qr_claves_mesa). Suma medio
--     punto a CUALQUIER telefono (si es nuevo se crea su fila en clientes, como
--     en 033/034). Vuelve a sumar desde el dia D+2.
--   - Origen web = sin clave o con clave invalida (se trata igual que sin clave,
--     nunca da error ni se le avisa al cliente). Suma medio punto SOLO si el
--     telefono tiene al menos un pedido entregado (y fila en clientes) y vuelve
--     a sumar desde el dia D+7. Si no cumple, la calificacion se guarda igual
--     con puntos_medios = 0 y SIN crear fila en clientes.
--   - D = dia (fecha calendario de America/Argentina/Buenos_Aires) del ultimo
--     punto de mesa de ese telefono de CUALQUIER origen, asi no se duplica
--     puntos usando los dos caminos. Se mantiene el bloqueo de la fila del
--     cliente (for update).
--   - Cuando no suma punto, la respuesta trae 'motivo': 'sin_pedido',
--     'ventana' (con proximo_punto_desde, yyyy-mm-dd) o 'programa_inactivo'.
--     Tambien trae 'origen'.
--
-- Que hace esta migracion:
--   1. Tabla qr_claves_mesa (RLS activo, sin policies ni grants).
--   2. calificaciones_mesa.origen ('qr' | 'web', default 'qr': las filas de
--      033/034 entraron todas por el QR sin clave).
--   3. calificar_mesa: DROP de la version de 5 parametros y CREATE de la de 6
--      (nuevo p_clave text default null). Mismos security definer,
--      search_path = '' y grants (anon, authenticated). Con create or replace
--      quedarian dos funciones y PostgREST responderia "funcion ambigua".
--   4. stats_calificaciones_mesa: MISMA firma; la lista de filas agrega "origen".
--
-- CARGAR LAS CLAVES (despues de aplicar, desde el SQL Editor de Supabase):
--     openssl rand -hex 16        -- una clave distinta por sucursal
--     insert into public.qr_claves_mesa (sucursal, clave) values
--       ('maestro-quiroga',    '<clave 1>'),
--       ('intendente-lascano', '<clave 2>')
--     on conflict (sucursal) do update
--       set clave = excluded.clave, actualizada_en = now();
--   El QR de cada sucursal apunta a  <sitio>/?mesa=<sucursal>&k=<clave>.
--   Hasta que se carguen, todo califica como origen web (sin error).
--
-- LIMITACION: la clave viaja en el QR; frena a quien califica sin escanear,
-- no a quien le saca una foto al QR. Lo acota la regla de 1 punto cada 2 dias.
--
-- Prerequisitos: 033 y 034 aplicadas. Las migraciones 001 a 034 NO se modifican.
--
-- IMPORTANTE: hacer BACKUP antes de aplicar. Idempotente (se puede ejecutar
-- mas de una vez).
--
-- ROLLBACK: descomentar y ejecutar, en este orden:
--   a) drop function if exists public.calificar_mesa(text, text, integer, integer, text, text);
--   b) la definicion de la 034 (5 parametros) de abajo;
--   c) la definicion de stats_calificaciones_mesa de la 033 de abajo;
--   d) opcional: quitar la columna origen y la tabla qr_claves_mesa (ver el
--      final del archivo).
-- ============================================================================
--
-- ---- Definicion de la 034: calificar_mesa de 5 parametros ------------------
--
-- create or replace function public.calificar_mesa(
--   p_sucursal text,
--   p_telefono text,
--   p_comida integer,
--   p_atencion integer,
--   p_comentario text default null
-- )
-- returns jsonb
-- language plpgsql
-- volatile
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   c_dias constant integer := 2;   -- 034: un punto cada 2 dias calendario (hora Argentina)
--   c_zona constant text := 'America/Argentina/Buenos_Aires';
--   v_suc text := nullif(btrim(coalesce(p_sucursal, '')), '');
--   v_tel text;
--   v_com text;
--   v_cfg jsonb;
--   v_ciclo integer;
--   v_cli public.clientes%rowtype;
--   v_h0 integer := 0;
--   v_medios smallint := 0;
--   v_gen integer := 0;
--   v_h integer;
--   v_pos integer;
--   v_sig jsonb;
--   v_meta integer;
--   v_prox jsonb := null;
--   v_ultima date;
--   v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
--   v_desde date := null;
-- begin
--   v_tel := public.pm_normalizar_telefono(p_telefono);
--
--   if not public.pm_calificacion_mesa_antispam(
--        'mesa:' || coalesce(v_suc, '?') || ':' || coalesce(v_tel, '?')) then
--     return jsonb_build_object('ok', false, 'estado', 'limite',
--       'mensaje', 'Probá de nuevo en unos minutos.');
--   end if;
--
--   begin
--     if v_suc is null or v_suc not in ('maestro-quiroga', 'intendente-lascano') then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'No encontramos esa sucursal.');
--     end if;
--     if v_tel is null then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'Revisá el teléfono: tiene que ser un celular de Argentina con código de área.');
--     end if;
--     if p_comida is null or p_comida not between 1 and 5 then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'Elegí de 1 a 5 estrellas para la comida.');
--     end if;
--     if p_atencion is null or p_atencion not between 1 and 5 then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'Elegí de 1 a 5 estrellas para la atención.');
--     end if;
--     v_com := nullif(btrim(coalesce(p_comentario, '')), '');
--     if v_com is not null and char_length(v_com) > 500 then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'El comentario puede tener hasta 500 caracteres.');
--     end if;
--
--     v_cfg := public.pm_fidelidad_config();
--
--     if v_cfg is not null then
--       -- Crea la fila de fidelidad si no existe (mismo camino que registrar_cliente).
--       insert into public.clientes (
--         telefono, nombre, acepta_promos, registrado_en, origen
--       ) values (
--         v_tel, 'Cliente de mesa', false, now(), 'registro'
--       )
--       on conflict (telefono) do nothing;
--
--       -- Bloqueo de la fila: serializa envios simultaneos del mismo telefono, asi
--       -- el chequeo de los 2 dias de abajo no se puede saltear con dos pedidos
--       -- en paralelo.
--       select * into v_cli
--         from public.clientes
--        where telefono = v_tel
--        for update;
--
--       if found then
--         v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;
--
--         -- Dia (fecha calendario AR) de la ultima calificacion de mesa con punto.
--         select (max(m.creado_en) at time zone c_zona)::date
--           into v_ultima
--           from public.calificaciones_mesa m
--          where m.telefono = v_tel
--            and m.puntos_medios = 1;
--
--         -- Si fue el dia D, vuelve a sumar desde el dia D+2, a cualquier hora.
--         if v_ultima is null or v_hoy >= v_ultima + c_dias then
--           update public.clientes
--              set fidelidad_calificaciones = fidelidad_calificaciones + 1
--            where telefono = v_tel;
--
--           -- Sin pedido de origen (null): no choca con premios_origen_tipo_uidx.
--           v_gen := public.pm_fidelidad_premiar(v_tel, v_h0, v_h0 + 1, null, v_cfg);
--           v_medios := 1;
--         else
--           v_desde := v_ultima + c_dias;
--         end if;
--       end if;
--     end if;
--
--     insert into public.calificaciones_mesa (
--       sucursal, telefono, comida, atencion, comentario, puntos_medios
--     ) values (
--       v_suc, v_tel, p_comida, p_atencion, v_com, v_medios
--     );
--
--     -- Progreso del ciclo (misma cuenta que mi_progreso_fidelidad, sin su anti-spam).
--     if v_cfg is not null then
--       v_ciclo := (v_cfg ->> 'ciclo')::integer;
--       v_h := v_h0 + v_medios;
--       v_pos := v_h % (2 * v_ciclo);
--
--       select e.value into v_sig
--         from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
--        where 2 * (e.value ->> 'en')::integer > v_pos
--        order by (e.value ->> 'en')::integer
--        limit 1;
--
--       if v_sig is not null then
--         v_meta := 2 * (v_sig ->> 'en')::integer;
--       else
--         select e.value into v_sig
--           from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
--          order by (e.value ->> 'en')::integer
--          limit 1;
--         v_meta := 2 * v_ciclo + 2 * (v_sig ->> 'en')::integer;
--       end if;
--
--       v_prox := jsonb_build_object(
--         'tipo', v_sig ->> 'tipo',
--         'valor', case when v_sig ->> 'tipo' = 'descuento_porcentaje'
--                       then (v_sig ->> 'valor')::numeric end,
--         'producto', case when v_sig ->> 'tipo' = 'producto_gratis'
--                          then public.pm_fidelidad_nombre_producto(v_sig ->> 'producto_id') end);
--     end if;
--
--     return jsonb_build_object(
--       'ok', true,
--       'estado', 'ok',
--       'sumo_punto', v_medios = 1,
--       'medios_en_ciclo', case when v_cfg is not null then v_pos end,
--       'faltan_medios', case when v_cfg is not null then v_meta - v_pos end,
--       'premio_generado', v_gen > 0,
--       'proximo_premio', v_prox,
--       'proximo_punto_desde', case when v_medios = 0 and v_desde is not null
--                                   then to_char(v_desde, 'YYYY-MM-DD') end);
--   exception
--     when others then
--       -- Se deshace todo el bloque (punto incluido): nunca queda a medias.
--       return jsonb_build_object('ok', false, 'estado', 'error',
--         'mensaje', 'No pudimos guardar tu calificación. Probá de nuevo en unos minutos.');
--   end;
-- end;
-- $$;
--
-- revoke all on function public.calificar_mesa(text, text, integer, integer, text)
--   from public, anon, authenticated;
-- grant execute on function public.calificar_mesa(text, text, integer, integer, text)
--   to anon, authenticated;
--
-- comment on function public.calificar_mesa(text, text, integer, integer, text) is
--   'Califica la visita en mesa por telefono (QR por sucursal). Suma 0,5 de fidelidad si el telefono no recibio punto de mesa en los ultimos 2 dias (cada 2 dias, por fecha en hora Argentina). Todo se decide en el servidor (034)';
--
-- ---- Definicion de la 033: stats_calificaciones_mesa (sin "origen") --------
--
-- create or replace function public.stats_calificaciones_mesa(
--   p_desde timestamptz default null,
--   p_hasta timestamptz default null,
--   p_sucursal text default null,
--   p_limite integer default 50,
--   p_offset integer default 0
-- )
-- returns jsonb
-- language plpgsql
-- stable
-- security definer
-- set search_path = ''
-- as $$
-- declare
--   v_suc text := nullif(btrim(p_sucursal), '');
--   v_mia text;
--   v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
--   v_off integer := greatest(coalesce(p_offset, 0), 0);
--   v_prom_comida numeric;
--   v_prom_atencion numeric;
--   v_total bigint;
--   v_con_com bigint;
--   v_filas jsonb;
-- begin
--   if not public.es_dueno() then
--     v_mia := public.sucursal_admin();
--     if v_mia is null then
--       raise exception 'No tenés permiso para hacer esto.';
--     end if;
--     if v_suc is not null and v_suc <> v_mia then
--       raise exception 'No tenés permiso para hacer esto.';
--     end if;
--     v_suc := v_mia;
--   end if;
--
--   if p_desde is not null and p_hasta is not null
--      and p_hasta - p_desde > interval '731 days' then
--     raise exception 'El período no puede superar los 731 días.';
--   end if;
--
--   select round(avg(m.comida), 2),
--          round(avg(m.atencion), 2),
--          count(*),
--          count(m.comentario)
--     into v_prom_comida, v_prom_atencion, v_total, v_con_com
--     from public.calificaciones_mesa m
--    where (p_desde is null or m.creado_en >= p_desde)
--      and (p_hasta is null or m.creado_en < p_hasta)
--      and (v_suc is null or m.sucursal = v_suc);
--
--   select coalesce(jsonb_agg(to_jsonb(x) order by x.creado_en desc, x.id desc), '[]'::jsonb)
--     into v_filas
--     from (
--       select m.id, m.sucursal, m.telefono, m.comida, m.atencion,
--              m.comentario, m.puntos_medios, m.creado_en
--         from public.calificaciones_mesa m
--        where (p_desde is null or m.creado_en >= p_desde)
--          and (p_hasta is null or m.creado_en < p_hasta)
--          and (v_suc is null or m.sucursal = v_suc)
--        order by m.creado_en desc, m.id desc
--        limit v_lim offset v_off
--     ) x;
--
--   return jsonb_build_object(
--     'desde', p_desde,
--     'hasta', p_hasta,
--     'sucursal', v_suc,
--     'promedio_comida', v_prom_comida,
--     'promedio_atencion', v_prom_atencion,
--     'total', v_total,
--     'con_comentario', v_con_com,
--     'filas', v_filas);
-- end;
-- $$;
--
-- revoke all on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer)
--   from public, anon;
-- grant execute on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer)
--   to authenticated;
--
-- comment on function public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer) is
--   'Promedios, totales y lista de calificaciones de mesa. Dueno: todo o una sucursal; encargado: solo la suya (033).';
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.calificaciones_mesa') is null
     or to_regprocedure('public.pm_calificacion_mesa_antispam(text)') is null
     or to_regprocedure('public.stats_calificaciones_mesa(timestamptz, timestamptz, text, integer, integer)') is null
     or (to_regprocedure('public.calificar_mesa(text, text, integer, integer, text)') is null
         and to_regprocedure('public.calificar_mesa(text, text, integer, integer, text, text)') is null) then
    raise exception '035: faltan las migraciones 033/034 (calificaciones_mesa, calificar_mesa).';
  end if;
end
$$;

-- ============================================================================
-- 1. Claves de QR por sucursal
-- ============================================================================
-- RLS activo, SIN policies y SIN grants: nadie la lee por la API. Solo la lee
-- calificar_mesa (security definer). Se carga a mano desde el SQL Editor.
create table if not exists public.qr_claves_mesa (
  sucursal text primary key,
  clave text not null,
  actualizada_en timestamptz not null default now(),

  constraint qr_claves_mesa_sucursal_chk
    check (sucursal in ('maestro-quiroga', 'intendente-lascano')),
  constraint qr_claves_mesa_clave_chk
    check (char_length(clave) between 8 and 100)
);

comment on table public.qr_claves_mesa is
  'Clave secreta del QR de mesa por sucursal (035). Sin acceso por la API: solo la lee calificar_mesa.';

alter table public.qr_claves_mesa enable row level security;
revoke all on public.qr_claves_mesa from public, anon, authenticated;

-- ============================================================================
-- 2. calificaciones_mesa.origen
-- ============================================================================
-- Las filas existentes (033/034) entraron todas por el QR, sin clave: quedan 'qr'.
alter table public.calificaciones_mesa
  add column if not exists origen text not null default 'qr';

alter table public.calificaciones_mesa
  drop constraint if exists calificaciones_mesa_origen_chk;
alter table public.calificaciones_mesa
  add constraint calificaciones_mesa_origen_chk check (origen in ('qr', 'web'));

comment on column public.calificaciones_mesa.origen is
  'qr = vino con la clave valida del QR de la sucursal; web = desde el boton Calificanos o con clave invalida (035).';

-- ============================================================================
-- 3. calificar_mesa (6 parametros)
-- ============================================================================
-- Agregar un parametro con create or replace dejaria DOS funciones con el mismo
-- nombre (PostgREST daria "funcion ambigua"), asi que se elimina la de 5.
drop function if exists public.calificar_mesa(text, text, integer, integer, text);

-- Devuelve {ok, estado, ...}:
--   ok=true,  estado='ok' -> origen ('qr'|'web'), sumo_punto (bool),
--     motivo (null si sumo; 'sin_pedido' | 'ventana' | 'programa_inactivo'),
--     proximo_punto_desde (yyyy-mm-dd, solo con motivo 'ventana'),
--     medios_en_ciclo / faltan_medios / proximo_premio (null si no hay
--     progreso para mostrar), premio_generado (bool)
--   ok=false, estado en: limite | invalido | error   (+ mensaje)
-- Reglas del punto:
--   - QR (p_clave valida para esa sucursal): cualquier telefono, incluso nuevo
--     (se crea su fila en clientes). Vuelve a sumar desde el dia D+2.
--   - Web (sin clave o clave invalida; nunca da error): solo si el telefono
--     tiene al menos un pedido entregado y fila en clientes (nunca se crea).
--     Vuelve a sumar desde el dia D+7.
--   - D = dia (fecha de Buenos Aires) del ultimo punto de mesa de ese telefono
--     de CUALQUIER origen.
create or replace function public.calificar_mesa(
  p_sucursal text,
  p_telefono text,
  p_comida integer,
  p_atencion integer,
  p_comentario text default null,
  p_clave text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_zona constant text := 'America/Argentina/Buenos_Aires';
  v_suc text := nullif(btrim(coalesce(p_sucursal, '')), '');
  v_clave text := nullif(btrim(coalesce(p_clave, '')), '');
  v_origen text := 'web';
  v_dias integer;
  v_tel text;
  v_com text;
  v_cfg jsonb;
  v_ciclo integer;
  v_cli public.clientes%rowtype;
  v_tiene_cli boolean := false;
  v_h0 integer := 0;
  v_medios smallint := 0;
  v_gen integer := 0;
  v_h integer;
  v_pos integer;
  v_sig jsonb;
  v_meta integer;
  v_prox jsonb := null;
  v_ultima date;
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_desde date := null;
  v_motivo text := null;
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

    -- Origen: clave valida de ESTA sucursal = qr. Ausente o invalida = web,
    -- sin error y sin avisarle al cliente.
    if v_clave is not null
       and exists (select 1 from public.qr_claves_mesa q
                    where q.sucursal = v_suc and q.clave = v_clave) then
      v_origen := 'qr';
    end if;
    v_dias := case when v_origen = 'qr' then 2 else 7 end;

    v_cfg := public.pm_fidelidad_config();

    if v_cfg is null then
      v_motivo := 'programa_inactivo';
    else
      if v_origen = 'qr' then
        -- Crea la fila de fidelidad si no existe (mismo camino que registrar_cliente).
        insert into public.clientes (
          telefono, nombre, acepta_promos, registrado_en, origen
        ) values (
          v_tel, 'Cliente de mesa', false, now(), 'registro'
        )
        on conflict (telefono) do nothing;
      end if;

      -- Web: sin pedido entregado no hay punto y NO se crea fila en clientes.
      if v_origen = 'web'
         and not exists (select 1 from public.pedidos p
                          where p.cliente_telefono = v_tel and p.estado = 'entregado') then
        v_motivo := 'sin_pedido';
      else
        -- Bloqueo de la fila: serializa envios simultaneos del mismo telefono, asi
        -- el chequeo de la ventana de abajo no se puede saltear con dos envios
        -- en paralelo (ni mezclando QR y web).
        select * into v_cli
          from public.clientes
         where telefono = v_tel
         for update;
        v_tiene_cli := found;

        if not v_tiene_cli then
          -- Solo puede pasar en web (con pedido entregado pero sin fila: borro sus datos).
          v_motivo := 'sin_pedido';
        else
          v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;

          -- Dia (fecha AR) del ultimo punto de mesa, de cualquier origen.
          select (max(m.creado_en) at time zone c_zona)::date
            into v_ultima
            from public.calificaciones_mesa m
           where m.telefono = v_tel
             and m.puntos_medios = 1;

          -- Si fue el dia D, vuelve a sumar desde D+2 (qr) o D+7 (web), a cualquier hora.
          if v_ultima is null or v_hoy >= v_ultima + v_dias then
            update public.clientes
               set fidelidad_calificaciones = fidelidad_calificaciones + 1
             where telefono = v_tel;

            -- Sin pedido de origen (null): no choca con premios_origen_tipo_uidx.
            v_gen := public.pm_fidelidad_premiar(v_tel, v_h0, v_h0 + 1, null, v_cfg);
            v_medios := 1;
          else
            v_motivo := 'ventana';
            v_desde := v_ultima + v_dias;
          end if;
        end if;
      end if;
    end if;

    insert into public.calificaciones_mesa (
      sucursal, telefono, comida, atencion, comentario, puntos_medios, origen
    ) values (
      v_suc, v_tel, p_comida, p_atencion, v_com, v_medios, v_origen
    );

    -- Progreso del ciclo (misma cuenta que mi_progreso_fidelidad, sin su anti-spam).
    -- Solo si hay fila de fidelidad del telefono; si no, no hay progreso que mostrar.
    if v_cfg is not null and v_tiene_cli then
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
      'origen', v_origen,
      'sumo_punto', v_medios = 1,
      'motivo', v_motivo,
      'proximo_punto_desde', case when v_motivo = 'ventana'
                                  then to_char(v_desde, 'YYYY-MM-DD') end,
      'medios_en_ciclo', case when v_cfg is not null and v_tiene_cli then v_pos end,
      'faltan_medios', case when v_cfg is not null and v_tiene_cli then v_meta - v_pos end,
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

revoke all on function public.calificar_mesa(text, text, integer, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.calificar_mesa(text, text, integer, integer, text, text)
  to anon, authenticated;

comment on function public.calificar_mesa(text, text, integer, integer, text, text) is
  'Califica la visita en mesa. Con clave valida del QR (origen qr) suma medio punto cada 2 dias a cualquier telefono; sin clave (origen web) solo si el telefono tiene un pedido entregado, cada 7 dias. Ventana por fecha en hora Argentina contra el ultimo punto de mesa de cualquier origen. Todo se decide en el servidor (035)';

-- ============================================================================
-- 4. stats_calificaciones_mesa: misma firma, la lista agrega "origen"
-- ============================================================================
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
             m.comentario, m.puntos_medios, m.origen, m.creado_en
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
  'Promedios, totales y lista de calificaciones de mesa (con origen qr/web). Dueno: todo o una sucursal; encargado: solo la suya (035).';

commit;

-- ============================================================================
-- ROLLBACK (ver el encabezado: definiciones de la 034 y la 033, comentadas).
-- Orden: 1) drop de la de 6 parametros, 2) recrear la de 5 (034) con su revoke,
-- grant y comment, 3) recrear stats_calificaciones_mesa (033), 4) opcional:
--   alter table public.calificaciones_mesa drop constraint if exists calificaciones_mesa_origen_chk;
--   alter table public.calificaciones_mesa drop column if exists origen;
--   drop table if exists public.qr_claves_mesa;
-- ============================================================================
