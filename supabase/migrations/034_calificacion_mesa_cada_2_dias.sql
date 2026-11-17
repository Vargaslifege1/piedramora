-- ============================================================================
-- 034 - Calificacion de mesa: un punto cada 2 dias por fecha
-- ============================================================================
-- Cambio unico respecto de calificar_mesa de la 033:
--   - Antes: 1 punto por telefono cada 7 dias (ventana movil de 168 horas).
--   - Ahora: si la ultima calificacion de mesa con puntos_medios = 1 de ese
--     telefono fue el dia D (fecha calendario en America/Argentina/Buenos_Aires),
--     puede volver a sumar desde el dia D+2, a cualquier hora. Dentro de esos 2
--     dias la calificacion se guarda igual con puntos_medios = 0.
--   - La respuesta agrega 'proximo_punto_desde' (yyyy-mm-dd) cuando no sumo
--     punto (null si sumo o si el programa de fidelidad esta inactivo).
--   - Todo lo demas es identico: parametros, return, security definer,
--     search_path y grants. Las tablas, stats_calificaciones_mesa, el trigger y
--     el anti-spam de la 033 no se tocan.
--
-- Prerequisito: 033 aplicada. La 033 NO se modifica.
--
-- IMPORTANTE: hacer BACKUP antes de aplicar. Idempotente: es un solo
-- create or replace (+ comment); se puede ejecutar mas de una vez.
--
-- ROLLBACK: ejecutar la definicion de la 033 que sigue comentada (los grants se
-- conservan con create or replace) y despues el COMMENT de la 033.
-- ============================================================================
--
-- ---- Definicion de la 033 (para volver atras) ------------------------------
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
--   c_dias constant integer := 7;
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
--       -- el chequeo de los 7 dias de abajo no se puede saltear con dos pedidos
--       -- en paralelo.
--       select * into v_cli
--         from public.clientes
--        where telefono = v_tel
--        for update;
--
--       if found then
--         v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;
--
--         if not exists (
--           select 1
--             from public.calificaciones_mesa m
--            where m.telefono = v_tel
--              and m.puntos_medios = 1
--              and m.creado_en > now() - make_interval(days => c_dias)
--         ) then
--           update public.clientes
--              set fidelidad_calificaciones = fidelidad_calificaciones + 1
--            where telefono = v_tel;
--
--           -- Sin pedido de origen (null): no choca con premios_origen_tipo_uidx.
--           v_gen := public.pm_fidelidad_premiar(v_tel, v_h0, v_h0 + 1, null, v_cfg);
--           v_medios := 1;
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
--       'proximo_premio', v_prox);
--   exception
--     when others then
--       -- Se deshace todo el bloque (punto incluido): nunca queda a medias.
--       return jsonb_build_object('ok', false, 'estado', 'error',
--         'mensaje', 'No pudimos guardar tu calificación. Probá de nuevo en unos minutos.');
--   end;
-- end;
-- $$;
--
-- comment on function public.calificar_mesa(text, text, integer, integer, text) is
--   'Califica la visita en mesa por telefono (QR por sucursal). Suma 0,5 de fidelidad si el telefono no recibio punto de mesa en 7 dias. Todo se decide en el servidor (033)';
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure('public.calificar_mesa(text, text, integer, integer, text)') is null
     or to_regclass('public.calificaciones_mesa') is null then
    raise exception '034: falta la migracion 033 (calificar_mesa).';
  end if;
end
$$;

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
  c_dias constant integer := 2;   -- 034: un punto cada 2 dias calendario (hora Argentina)
  c_zona constant text := 'America/Argentina/Buenos_Aires';
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
  v_ultima date;
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_desde date := null;
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
      -- el chequeo de los 2 dias de abajo no se puede saltear con dos pedidos
      -- en paralelo.
      select * into v_cli
        from public.clientes
       where telefono = v_tel
       for update;

      if found then
        v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;

        -- Dia (fecha calendario AR) de la ultima calificacion de mesa con punto.
        select (max(m.creado_en) at time zone c_zona)::date
          into v_ultima
          from public.calificaciones_mesa m
         where m.telefono = v_tel
           and m.puntos_medios = 1;

        -- Si fue el dia D, vuelve a sumar desde el dia D+2, a cualquier hora.
        if v_ultima is null or v_hoy >= v_ultima + c_dias then
          update public.clientes
             set fidelidad_calificaciones = fidelidad_calificaciones + 1
           where telefono = v_tel;

          -- Sin pedido de origen (null): no choca con premios_origen_tipo_uidx.
          v_gen := public.pm_fidelidad_premiar(v_tel, v_h0, v_h0 + 1, null, v_cfg);
          v_medios := 1;
        else
          v_desde := v_ultima + c_dias;
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
      'proximo_premio', v_prox,
      'proximo_punto_desde', case when v_medios = 0 and v_desde is not null
                                  then to_char(v_desde, 'YYYY-MM-DD') end);
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
  'Califica la visita en mesa por telefono (QR por sucursal). Suma 0,5 de fidelidad si el telefono no recibio punto de mesa en los ultimos 2 dias (cada 2 dias, por fecha en hora Argentina). Todo se decide en el servidor (034)';

commit;
