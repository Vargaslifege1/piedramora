-- ============================================================================
-- 032 - Calificar pedido: la entrega es OPCIONAL en delivery
-- ============================================================================
-- Cambio unico respecto de calificar_pedido de la 031:
--   - En delivery, p_entrega = null es valido y se guarda null (el cliente puede
--     calificar solo la comida). Si viene un valor, debe estar entre 1 y 5; si
--     no, devuelve estado 'invalido'.
--   - En retiro / mesa sigue igual: p_entrega se ignora y se guarda null.
--   - La comida sigue siendo obligatoria (1 a 5). Todo lo demas es identico.
--
-- Efecto en stats_calificaciones (031): sin cambios. promedio_entrega y
-- total_entrega ya ignoran las calificaciones con entrega null.
--
-- Prerequisitos: 031 aplicada (tabla calificaciones y calificar_pedido).
-- Las migraciones 001 a 031 NO se modifican.
--
-- IMPORTANTE: hacer BACKUP antes de aplicar. Idempotente: es un solo
-- create or replace; se puede ejecutar mas de una vez.
--
-- ROLLBACK: ejecutar el CREATE OR REPLACE comentado al final (definicion de la
-- 031). Los permisos se conservan.
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.calificaciones') is null
     or to_regprocedure('public.calificar_pedido(uuid, integer, integer, text)') is null
     or to_regprocedure('public.pm_fidelidad_premiar(text, integer, integer, uuid, jsonb)') is null then
    raise exception '032: falta la migracion 031 (calificaciones / calificar_pedido).';
  end if;
end
$$;

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
      -- La entrega es opcional: null es valido y se guarda null. Si viene un
      -- valor, tiene que estar entre 1 y 5.
      if p_entrega is not null and p_entrega not between 1 and 5 then
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
  'Califica un pedido entregado (una vez, 7 dias) y suma 0,5 de fidelidad si corresponde. Todo se decide en el servidor (031). Entrega opcional en delivery (032).';

commit;

-- ============================================================================
-- ROLLBACK: definicion actual (031) de calificar_pedido. Para revertir,
-- descomentar y ejecutar (los grants se conservan con create or replace).
-- ============================================================================
--
-- create or replace function public.calificar_pedido(
--   p_pedido_id uuid,
--   p_comida integer,
--   p_entrega integer default null,
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
--   v_ped public.pedidos%rowtype;
--   v_cfg jsonb;
--   v_cli public.clientes%rowtype;
--   v_com text;
--   v_entrega smallint;
--   v_h0 integer;
--   v_gen integer := 0;
--   v_medios smallint := 0;
-- begin
--   if p_pedido_id is null then
--     return jsonb_build_object('ok', false, 'estado', 'no_encontrado',
--       'mensaje', 'No encontramos ese pedido.');
--   end if;
--
--   if not public.pm_calificacion_antispam(p_pedido_id) then
--     return jsonb_build_object('ok', false, 'estado', 'limite',
--       'mensaje', 'Probá de nuevo en unos minutos.');
--   end if;
--
--   begin
--     -- Bloqueo del pedido: serializa envios simultaneos para el mismo pedido.
--     select * into v_ped from public.pedidos where id = p_pedido_id for update;
--     if not found then
--       return jsonb_build_object('ok', false, 'estado', 'no_encontrado',
--         'mensaje', 'No encontramos ese pedido.');
--     end if;
--
--     if v_ped.estado = 'cancelado' then
--       return jsonb_build_object('ok', false, 'estado', 'cancelado',
--         'mensaje', 'Este pedido no se puede calificar.');
--     end if;
--     if v_ped.estado <> 'entregado' then
--       return jsonb_build_object('ok', false, 'estado', 'no_entregado',
--         'mensaje', 'Tu pedido todavía no fue entregado. Calificalo cuando lo recibas.');
--     end if;
--     if exists (select 1 from public.calificaciones where pedido_id = v_ped.id) then
--       return jsonb_build_object('ok', false, 'estado', 'ya_calificado',
--         'mensaje', 'Este pedido ya fue calificado. ¡Gracias!');
--     end if;
--     if now() > coalesce(v_ped.entregado_en, v_ped.created_at) + make_interval(days => c_dias) then
--       return jsonb_build_object('ok', false, 'estado', 'vencido',
--         'mensaje', 'Pasó el plazo de 7 días para calificar este pedido.');
--     end if;
--
--     -- Validacion de datos (el servidor decide; no se corrige en silencio).
--     if p_comida is null or p_comida not between 1 and 5 then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'Elegí de 1 a 5 estrellas para la comida.');
--     end if;
--
--     if v_ped.modalidad = 'delivery' then
--       if p_entrega is null or p_entrega not between 1 and 5 then
--         return jsonb_build_object('ok', false, 'estado', 'invalido',
--           'mensaje', 'Elegí de 1 a 5 estrellas para la entrega.');
--       end if;
--       v_entrega := p_entrega;
--     else
--       v_entrega := null;   -- retiro / mesa: no se pregunta; se ignora lo que llegue
--     end if;
--
--     v_com := nullif(btrim(coalesce(p_comentario, '')), '');
--     if v_com is not null and char_length(v_com) > 500 then
--       return jsonb_build_object('ok', false, 'estado', 'invalido',
--         'mensaje', 'El comentario puede tener hasta 500 caracteres.');
--     end if;
--
--     -- Medio punto: solo si el pedido ya conto para fidelidad y el programa esta
--     -- activo. Mismo orden de bloqueo que la entrega (pedido -> cliente).
--     v_cfg := public.pm_fidelidad_config();
--     if v_ped.fidelidad_contado and v_cfg is not null then
--       select * into v_cli
--         from public.clientes
--        where telefono = v_ped.cliente_telefono
--        for update;
--       if found then
--         v_h0 := 2 * v_cli.fidelidad_pedidos + v_cli.fidelidad_calificaciones;
--
--         update public.clientes
--            set fidelidad_calificaciones = fidelidad_calificaciones + 1
--          where telefono = v_ped.cliente_telefono;
--
--         v_gen := public.pm_fidelidad_premiar(
--           v_ped.cliente_telefono, v_h0, v_h0 + 1, v_ped.id, v_cfg);
--         v_medios := 1;
--       end if;
--     end if;
--
--     insert into public.calificaciones (
--       pedido_id, sucursal_id, comida, entrega, comentario, puntos_medios
--     ) values (
--       v_ped.id, v_ped.sucursal_id, p_comida, v_entrega, v_com, v_medios
--     );
--
--     return jsonb_build_object(
--       'ok', true,
--       'estado', 'ok',
--       'puntos_ganados', case when v_medios = 1 then 0.5 else 0 end,
--       'premio_generado', v_gen > 0);
--   exception
--     when unique_violation then
--       -- Carrera: otra calificacion del mismo pedido gano. Se deshace todo el bloque.
--       return jsonb_build_object('ok', false, 'estado', 'ya_calificado',
--         'mensaje', 'Este pedido ya fue calificado. ¡Gracias!');
--     when others then
--       return jsonb_build_object('ok', false, 'estado', 'error',
--         'mensaje', 'No pudimos guardar tu calificación. Probá de nuevo en unos minutos.');
--   end;
-- end;
-- $$;
