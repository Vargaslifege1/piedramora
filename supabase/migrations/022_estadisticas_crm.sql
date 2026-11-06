-- ============================================================================
-- 022_estadisticas_crm.sql
-- Estadisticas del negocio y CRM de clientes (solo lectura, solo dueno)
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP de la base (Supabase > Database > Backups,
-- o pg_dump). Esta migracion no toca datos existentes ni funciones previas:
-- solo crea funciones de lectura, indices y una fila de config.
--
-- Prerrequisitos (ya aplicadas): 010 (pedidos, clientes, config_negocio),
-- 017 (es_dueno), 018 (cupones, cupon_usos), 019 (premios, fidelidad),
-- 020 (clientes.apellido / acepta_promos), 021 (sucursales_coords vigente).
-- No se modifica ninguna migracion anterior.
--
-- Funciones publicas (todas SECURITY DEFINER, STABLE, search_path = '',
-- todas empiezan validando es_dueno(); execute solo para authenticated):
--   1. stats_resumen(p_desde, p_hasta, p_sucursal)            -> jsonb
--   2. stats_cupones_fidelidad(p_desde, p_hasta, p_sucursal)  -> jsonb
--   3. crm_clientes(p_buscar, p_orden, p_dir, p_segmento, p_limite, p_offset) -> jsonb
--   4. crm_cliente_ficha(p_telefono)                          -> jsonb
--   5. crm_exportar(p_segmento, p_solo_promos)                -> tabla (max 5000)
--   6. crm_inactivos_promos(p_limite)                         -> tabla
--
-- Helpers internos (sin ningun grant, solo los llaman las funciones de arriba):
--   pm_num, pm_variacion_pct, pm_stats_sucursal_ok, pm_crm_umbrales,
--   pm_crm_segmento.
--
-- Criterios comunes
--   - Dias y horas en America/Argentina/Buenos_Aires.
--   - Rango [p_desde, p_hasta) sobre pedidos.created_at. Maximo 731 dias.
--     Si p_hasta <= p_desde el periodo es vacio (todo en 0, sin error).
--   - p_sucursal null = todas. Si la sucursal no existe en config_negocio
--     'sucursales_coords' los resultados salen vacios (no error).
--   - Pedidos con sincronizado = false se ignoran siempre.
--   - Facturacion = suma de pedidos.total de pedidos 'entregado'.
--     "pedidos" = entregados; ademas se informan cancelados e ingresados
--     (todos los estados) del mismo periodo.
--   - Productos: salen de items_snapshot por producto_id (estable) y los
--     items con regalo = true NO suman cantidad ni ingresos (se cuentan aparte).
--     "ingresos" de un producto = suma de items_snapshot[].subtotal (importe
--     final de la linea, con variacion y adicionales).
--   - Ninguna funcion escribe datos. Lo unico que se escribe es el seed de
--     config_negocio 'crm_segmentos' (ON CONFLICT DO NOTHING).
--
-- Idempotente: se puede correr mas de una vez.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Config de segmentos del CRM (seed; el dueno puede ajustarla despues)
-- ----------------------------------------------------------------------------
insert into public.config_negocio (clave, valor)
values (
  'crm_segmentos',
  '{"frecuente_min": 5, "ocasional_min": 2, "inactivo_dias": 30}'::jsonb
)
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- 1. Indices (IF NOT EXISTS)
-- ----------------------------------------------------------------------------
-- Ya existentes desde 010 y que alcanzan para lo nuevo:
--   pedidos (estado, created_at desc), pedidos (created_at desc),
--   clientes (ultima_visita desc).  Por eso NO se duplican.
-- Nuevos, con uso concreto:
--   * (sucursal_id, created_at): filtro por sucursal + rango de fechas.
create index if not exists pedidos_sucursal_created_at_idx
  on public.pedidos (sucursal_id, created_at);

--   * (cliente_telefono, created_at desc): ultimos 20 pedidos de la ficha.
create index if not exists pedidos_telefono_created_at_idx
  on public.pedidos (cliente_telefono, created_at desc);

--   * premios por fecha de creacion y de canje (estadisticas de fidelidad).
create index if not exists premios_creado_en_idx
  on public.premios (creado_en);
create index if not exists premios_usado_en_idx
  on public.premios (usado_en)
  where usado;

-- ----------------------------------------------------------------------------
-- 2. Helpers internos (sin permisos para nadie salvo el dueno de la funcion)
-- ----------------------------------------------------------------------------

-- Texto -> numeric sin romper si el valor del snapshot es raro (null si no es numero).
create or replace function public.pm_num(p_texto text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case when p_texto ~ '^-?[0-9]+(\.[0-9]+)?$' then p_texto::numeric end;
$$;

-- Variacion porcentual actual vs anterior. null si el anterior es 0 o falta.
create or replace function public.pm_variacion_pct(p_actual numeric, p_anterior numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_anterior is null or p_anterior = 0 or p_actual is null then null
    else round((p_actual - p_anterior) / p_anterior * 100, 1)
  end;
$$;

-- true si p_sucursal es null (todas) o existe como clave en sucursales_coords.
create or replace function public.pm_stats_sucursal_ok(p_sucursal text)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_coords jsonb;
begin
  if p_sucursal is null then
    return true;
  end if;
  select valor into v_coords
    from public.config_negocio
   where clave = 'sucursales_coords';
  return coalesce(jsonb_typeof(v_coords) = 'object' and (v_coords ? p_sucursal), false);
end;
$$;

-- Umbrales de segmentacion validados. Si la config falta o es invalida
-- devuelve los defaults completos (no mezcla valores buenos con malos).
create or replace function public.pm_crm_umbrales()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v jsonb;
  c_default constant jsonb :=
    '{"frecuente_min": 5, "ocasional_min": 2, "inactivo_dias": 30}'::jsonb;
  v_frec integer;
  v_ocas integer;
  v_inac integer;
begin
  select valor into v from public.config_negocio where clave = 'crm_segmentos';

  -- coalesce(..., false): una clave faltante da null y debe contar como invalida.
  if not coalesce(
       v is not null and jsonb_typeof(v) = 'object'
       and jsonb_typeof(v -> 'frecuente_min') = 'number'
       and jsonb_typeof(v -> 'ocasional_min') = 'number'
       and jsonb_typeof(v -> 'inactivo_dias') = 'number'
       and (v ->> 'frecuente_min') ~ '^[0-9]{1,4}$'
       and (v ->> 'ocasional_min') ~ '^[0-9]{1,4}$'
       and (v ->> 'inactivo_dias') ~ '^[0-9]{1,4}$', false) then
    return c_default;
  end if;

  v_frec := (v ->> 'frecuente_min')::integer;
  v_ocas := (v ->> 'ocasional_min')::integer;
  v_inac := (v ->> 'inactivo_dias')::integer;

  if v_ocas < 1 or v_frec <= v_ocas or v_inac < 1 or v_inac > 3650 then
    return c_default;
  end if;

  return jsonb_build_object(
    'frecuente_min', v_frec,
    'ocasional_min', v_ocas,
    'inactivo_dias', v_inac);
exception when others then
  return c_default;
end;
$$;

-- Segmento de un cliente. Orden de prioridad:
--   registrado (0 pedidos entregados) > inactivo > frecuente > ocasional > nuevo
-- "inactivo" gana sobre frecuente/ocasional/nuevo: la ultima visita es mas
-- vieja que inactivo_dias.
create or replace function public.pm_crm_segmento(
  p_pedidos integer,
  p_ultima timestamptz,
  p_umbrales jsonb
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when coalesce(p_pedidos, 0) <= 0 then 'registrado'
    when p_ultima is not null
         and p_ultima < now() - make_interval(days => (p_umbrales ->> 'inactivo_dias')::integer)
      then 'inactivo'
    when p_pedidos >= (p_umbrales ->> 'frecuente_min')::integer then 'frecuente'
    when p_pedidos >= (p_umbrales ->> 'ocasional_min')::integer then 'ocasional'
    else 'nuevo'
  end;
$$;

revoke all on function public.pm_num(text) from public, anon, authenticated;
revoke all on function public.pm_variacion_pct(numeric, numeric) from public, anon, authenticated;
revoke all on function public.pm_stats_sucursal_ok(text) from public, anon, authenticated;
revoke all on function public.pm_crm_umbrales() from public, anon, authenticated;
revoke all on function public.pm_crm_segmento(integer, timestamptz, jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. stats_resumen
-- ----------------------------------------------------------------------------
-- Devuelve:
--   desde, hasta, sucursal,
--   facturacion, pedidos (entregados), cancelados, ingresados,
--   ticket_promedio, envio_cobrado, regalos (unidades regaladas, aparte),
--   anterior: {desde, hasta, facturacion, pedidos, ticket_promedio}
--             (periodo inmediato anterior de igual duracion),
--   variacion: {facturacion_pct, pedidos_pct, ticket_pct} (null si el anterior es 0),
--   ventas_por_dia:  [{dia 'YYYY-MM-DD', pedidos, facturacion}]  (dias sin ventas en 0),
--   ventas_por_hora: [{hora 0..23, pedidos, facturacion}]        (24 filas siempre),
--   metodos_pago:    [{metodo, pedidos, facturacion}],
--   modalidades:     [{modalidad, pedidos, facturacion}],
--   top_productos:   [{producto_id, nombre, cantidad, ingresos}] (10, sin regalos).
create or replace function public.stats_resumen(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_sucursal text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_tz constant text := 'America/Argentina/Buenos_Aires';
  v_suc text := nullif(btrim(p_sucursal), '');
  v_ok boolean;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_ant_desde timestamptz;
  v_dia_ini date;
  v_dia_fin date;

  v_fact numeric := 0;
  v_ped bigint := 0;
  v_canc bigint := 0;
  v_ing bigint := 0;
  v_envio numeric := 0;
  v_fact_ant numeric := 0;
  v_ped_ant bigint := 0;
  v_ticket numeric := 0;
  v_ticket_ant numeric := 0;

  v_por_dia jsonb;
  v_por_hora jsonb;
  v_pagos jsonb;
  v_modal jsonb;
  v_top jsonb;
  v_regalos numeric;
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  if p_desde is null or p_hasta is null then
    raise exception 'Indicá el período (desde y hasta).';
  end if;

  v_desde := p_desde;
  v_hasta := greatest(p_hasta, p_desde);   -- periodo invertido = vacio
  if v_hasta - v_desde > interval '731 days' then
    raise exception 'El período no puede superar los 731 días.';
  end if;

  v_ok := public.pm_stats_sucursal_ok(v_suc);
  v_ant_desde := v_desde - (v_hasta - v_desde);

  -- Totales del periodo actual
  select coalesce(sum(p.total) filter (where p.estado = 'entregado'), 0),
         count(*) filter (where p.estado = 'entregado'),
         count(*) filter (where p.estado = 'cancelado'),
         count(*),
         coalesce(sum(p.costo_envio) filter (where p.estado = 'entregado'), 0)
    into v_fact, v_ped, v_canc, v_ing, v_envio
    from public.pedidos p
   where v_ok
     and p.created_at >= v_desde and p.created_at < v_hasta
     and (v_suc is null or p.sucursal_id = v_suc)
     and p.sincronizado is distinct from false;

  -- Periodo anterior de igual duracion: [v_ant_desde, v_desde)
  select coalesce(sum(p.total), 0), count(*)
    into v_fact_ant, v_ped_ant
    from public.pedidos p
   where v_ok
     and p.estado = 'entregado'
     and p.created_at >= v_ant_desde and p.created_at < v_desde
     and (v_suc is null or p.sucursal_id = v_suc)
     and p.sincronizado is distinct from false;

  v_ticket := case when v_ped > 0 then round(v_fact / v_ped, 2) else 0 end;
  v_ticket_ant := case when v_ped_ant > 0 then round(v_fact_ant / v_ped_ant, 2) else 0 end;

  -- Rango de dias locales para la serie completa
  v_dia_ini := (v_desde at time zone c_tz)::date;
  if v_hasta <= v_desde then
    v_dia_fin := v_dia_ini - 1;   -- serie vacia
  else
    v_dia_fin := ((v_hasta - interval '1 microsecond') at time zone c_tz)::date;
  end if;

  with b as (
    select p.created_at, p.total, p.metodo_pago, p.modalidad, p.items_snapshot
      from public.pedidos p
     where v_ok
       and p.estado = 'entregado'
       and p.created_at >= v_desde and p.created_at < v_hasta
       and (v_suc is null or p.sucursal_id = v_suc)
       and p.sincronizado is distinct from false
  ),
  items as (
    select i.value as item
      from b
     cross join lateral jsonb_array_elements(b.items_snapshot) as i(value)
  )
  select
    -- ventas por dia (todos los dias del rango, con 0)
    (select coalesce(jsonb_agg(jsonb_build_object(
              'dia', to_char(d.dia, 'YYYY-MM-DD'),
              'pedidos', coalesce(x.n, 0),
              'facturacion', coalesce(x.f, 0)) order by d.dia), '[]'::jsonb)
       from (select v_dia_ini + g as dia
               from generate_series(0, v_dia_fin - v_dia_ini) as g) d
       left join (select (b.created_at at time zone c_tz)::date as dia,
                         count(*) as n, sum(b.total) as f
                    from b group by 1) x on x.dia = d.dia),
    -- ventas por hora (0-23 siempre)
    (select jsonb_agg(jsonb_build_object(
              'hora', h.hora,
              'pedidos', coalesce(x.n, 0),
              'facturacion', coalesce(x.f, 0)) order by h.hora)
       from generate_series(0, 23) as h(hora)
       left join (select extract(hour from b.created_at at time zone c_tz)::integer as hora,
                         count(*) as n, sum(b.total) as f
                    from b group by 1) x on x.hora = h.hora),
    -- metodos de pago
    (select coalesce(jsonb_agg(jsonb_build_object(
              'metodo', q.metodo, 'pedidos', q.n, 'facturacion', q.f)
              order by q.f desc, q.metodo), '[]'::jsonb)
       from (select b.metodo_pago as metodo, count(*) as n, sum(b.total) as f
               from b group by 1) q),
    -- modalidades
    (select coalesce(jsonb_agg(jsonb_build_object(
              'modalidad', q.modalidad, 'pedidos', q.n, 'facturacion', q.f)
              order by q.f desc, q.modalidad), '[]'::jsonb)
       from (select b.modalidad as modalidad, count(*) as n, sum(b.total) as f
               from b group by 1) q),
    -- top 10 productos (sin regalos)
    (select coalesce(jsonb_agg(jsonb_build_object(
              'producto_id', t.producto_id, 'nombre', t.nombre,
              'cantidad', t.cantidad, 'ingresos', t.ingresos)
              order by t.cantidad desc, t.ingresos desc, t.producto_id), '[]'::jsonb)
       from (select it.item ->> 'producto_id' as producto_id,
                    max(it.item ->> 'nombre') as nombre,
                    sum(coalesce(public.pm_num(it.item ->> 'cantidad'), 0)) as cantidad,
                    sum(coalesce(public.pm_num(it.item ->> 'subtotal'), 0)) as ingresos
               from items it
              where coalesce(it.item ->> 'regalo', 'false') <> 'true'
                and it.item ->> 'producto_id' is not null
              group by 1
              order by 3 desc, 4 desc, 1
              limit 10) t),
    -- regalos (aparte)
    (select coalesce(sum(coalesce(public.pm_num(it.item ->> 'cantidad'), 1)), 0)
       from items it
      where it.item ->> 'regalo' = 'true')
  into v_por_dia, v_por_hora, v_pagos, v_modal, v_top, v_regalos;

  return jsonb_build_object(
    'desde', v_desde,
    'hasta', v_hasta,
    'sucursal', v_suc,
    'facturacion', v_fact,
    'pedidos', v_ped,
    'cancelados', v_canc,
    'ingresados', v_ing,
    'ticket_promedio', v_ticket,
    'envio_cobrado', v_envio,
    'regalos', v_regalos,
    'anterior', jsonb_build_object(
      'desde', v_ant_desde,
      'hasta', v_desde,
      'facturacion', v_fact_ant,
      'pedidos', v_ped_ant,
      'ticket_promedio', v_ticket_ant),
    'variacion', jsonb_build_object(
      'facturacion_pct', public.pm_variacion_pct(v_fact, v_fact_ant),
      'pedidos_pct', public.pm_variacion_pct(v_ped, v_ped_ant),
      'ticket_pct', public.pm_variacion_pct(v_ticket, v_ticket_ant)),
    'ventas_por_dia', v_por_dia,
    'ventas_por_hora', v_por_hora,
    'metodos_pago', v_pagos,
    'modalidades', v_modal,
    'top_productos', v_top);
end;
$$;

comment on function public.stats_resumen(timestamptz, timestamptz, text) is
  'Resumen de ventas del periodo [desde, hasta) para el dueno. Solo lectura. Ver cabecera de 022.';

-- ----------------------------------------------------------------------------
-- 4. stats_cupones_fidelidad
-- ----------------------------------------------------------------------------
-- Devuelve:
--   cupones: [{codigo, usos, ventas_generadas, descuento_otorgado}]
--            (pedidos NO cancelados; ventas_generadas = suma de pedidos.total)
--   fidelidad: {
--     premios_generados, premios_generados_por_tipo: {tipo: n},
--     premios_canjeados,
--     descuento_premios_porcentaje   (suma de pedidos.descuento de pedidos no
--                                     cancelados que canjearon un premio %),
--     regalos,                       (unidades de producto gratis, no cancelados)
--     regalos_costo_estimado,        (null si ningun regalo trae precio_regular
--                                     de la variacion SIMPLE en el snapshot)
--     regalos_sin_costo              (regalos sin costo conocido)
--   }
-- Nota: hoy el snapshot del regalo guarda precio_regular = 0, asi que el costo
-- sale null hasta que el snapshot incluya el precio de la variacion SIMPLE.
create or replace function public.stats_cupones_fidelidad(
  p_desde timestamptz,
  p_hasta timestamptz,
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
  v_ok boolean;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_cupones jsonb;
  v_gen bigint := 0;
  v_gen_tipo jsonb;
  v_canj bigint := 0;
  v_desc_pct numeric := 0;
  v_reg numeric := 0;
  v_reg_costo numeric;
  v_reg_sin bigint := 0;
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  if p_desde is null or p_hasta is null then
    raise exception 'Indicá el período (desde y hasta).';
  end if;

  v_desde := p_desde;
  v_hasta := greatest(p_hasta, p_desde);
  if v_hasta - v_desde > interval '731 days' then
    raise exception 'El período no puede superar los 731 días.';
  end if;

  v_ok := public.pm_stats_sucursal_ok(v_suc);

  -- Cupones (excluye cancelados)
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', q.codigo,
           'usos', q.usos,
           'ventas_generadas', q.ventas,
           'descuento_otorgado', q.descuento) order by q.usos desc, q.codigo), '[]'::jsonb)
    into v_cupones
    from (select c.codigo,
                 count(*) as usos,
                 coalesce(sum(p.total), 0) as ventas,
                 coalesce(sum(u.monto_descontado), 0) as descuento
            from public.cupon_usos u
            join public.cupones c on c.id = u.cupon_id
            join public.pedidos p on p.id = u.pedido_id
           where v_ok
             and p.estado <> 'cancelado'
             and p.created_at >= v_desde and p.created_at < v_hasta
             and (v_suc is null or p.sucursal_id = v_suc)
             and p.sincronizado is distinct from false
           group by c.codigo) q;

  -- Premios generados (por fecha de creacion; sucursal = la del pedido que lo origino)
  select count(*),
         coalesce(jsonb_object_agg(t.tipo, t.n) filter (where t.tipo is not null), '{}'::jsonb)
    into v_gen, v_gen_tipo
    from (select pr.tipo, count(*) over (partition by pr.tipo) as n
            from public.premios pr
            left join public.pedidos o on o.id = pr.pedido_origen_id
           where v_ok
             and pr.creado_en >= v_desde and pr.creado_en < v_hasta
             and (v_suc is null or o.sucursal_id = v_suc)) t;

  -- Premios canjeados (por fecha de canje; sucursal = la del pedido donde se uso)
  select count(*)
    into v_canj
    from public.premios pr
    left join public.pedidos c on c.id = pr.pedido_id
   where v_ok
     and pr.usado
     and pr.usado_en >= v_desde and pr.usado_en < v_hasta
     and (v_suc is null or c.sucursal_id = v_suc);

  -- Descuento otorgado por premios de porcentaje
  select coalesce(sum(p.descuento), 0)
    into v_desc_pct
    from public.pedidos p
    join public.premios pr on pr.id = p.premio_id
   where v_ok
     and pr.tipo = 'descuento_porcentaje'
     and p.estado <> 'cancelado'
     and p.created_at >= v_desde and p.created_at < v_hasta
     and (v_suc is null or p.sucursal_id = v_suc)
     and p.sincronizado is distinct from false;

  -- Regalos (producto gratis) y costo estimado con el precio_regular de la
  -- variacion SIMPLE si esta en el snapshot; si no, ese regalo no tiene costo.
  select coalesce(sum(r.cant), 0),
         sum(r.cant * r.costo_unit),
         count(*) filter (where r.costo_unit is null)
    into v_reg, v_reg_costo, v_reg_sin
    from (select coalesce(public.pm_num(i.value ->> 'cantidad'), 1) as cant,
                 case
                   when i.value -> 'variacion' is null
                        or jsonb_typeof(i.value -> 'variacion') = 'null'
                        or upper(btrim(coalesce(i.value #>> '{variacion,nombre}', ''))) = 'SIMPLE'
                   then nullif(coalesce(
                          public.pm_num(i.value #>> '{variacion,precio_regular}'),
                          public.pm_num(i.value ->> 'precio_regular')), 0)
                 end as costo_unit
            from public.pedidos p
           cross join lateral jsonb_array_elements(p.items_snapshot) as i(value)
           where v_ok
             and p.estado <> 'cancelado'
             and p.created_at >= v_desde and p.created_at < v_hasta
             and (v_suc is null or p.sucursal_id = v_suc)
             and p.sincronizado is distinct from false
             and i.value ->> 'regalo' = 'true') r;

  return jsonb_build_object(
    'desde', v_desde,
    'hasta', v_hasta,
    'sucursal', v_suc,
    'cupones', v_cupones,
    'fidelidad', jsonb_build_object(
      'premios_generados', v_gen,
      'premios_generados_por_tipo', v_gen_tipo,
      'premios_canjeados', v_canj,
      'descuento_premios_porcentaje', v_desc_pct,
      'regalos', v_reg,
      'regalos_costo_estimado', v_reg_costo,
      'regalos_sin_costo', v_reg_sin));
end;
$$;

comment on function public.stats_cupones_fidelidad(timestamptz, timestamptz, text) is
  'Rendimiento de cupones y fidelidad en [desde, hasta) para el dueno. Solo lectura.';

-- ----------------------------------------------------------------------------
-- 5. crm_clientes
-- ----------------------------------------------------------------------------
-- p_buscar: nombre, apellido, "nombre apellido" o telefono (ilike; % _ \ se
--           escapan, se buscan literales).
-- p_orden : 'pedidos' | 'gasto' | 'ultima_visita' (lista blanca; otro valor =
--           'ultima_visita'). p_dir: 'asc' | 'desc' (otro valor = 'desc').
--           No hay SQL dinamico: el orden sale de CASE fijos.
-- p_segmento: nuevo | ocasional | frecuente | inactivo | registrado | null/'todos'.
-- p_limite: 1..200 (default 50). p_offset >= 0.
-- Devuelve {total, limite, offset, filas:[{telefono, nombre, apellido, pedidos,
--   gasto, ticket_promedio, ultima_visita, dias_sin_pedir, acepta_promos,
--   segmento, fidelidad_pedidos}]}.
-- "pedidos" y "gasto" salen de los contadores de clientes (los mantiene el
-- trigger de pedidos entregados; ver 010/019).
create or replace function public.crm_clientes(
  p_buscar text default null,
  p_orden text default 'ultima_visita',
  p_dir text default 'desc',
  p_segmento text default null,
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
  c_tz constant text := 'America/Argentina/Buenos_Aires';
  v_buscar text := left(nullif(btrim(coalesce(p_buscar, '')), ''), 80);
  v_pat text;
  v_orden text := case when lower(coalesce(p_orden, '')) in ('pedidos', 'gasto', 'ultima_visita')
                       then lower(p_orden) else 'ultima_visita' end;
  v_dir text := case when lower(coalesce(p_dir, '')) = 'asc' then 'asc' else 'desc' end;
  v_seg text := lower(nullif(btrim(coalesce(p_segmento, '')), ''));
  v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
  v_off integer := greatest(coalesce(p_offset, 0), 0);
  v_umbrales jsonb := public.pm_crm_umbrales();
  v_total bigint := 0;
  v_filas jsonb := '[]'::jsonb;
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  if v_seg = 'todos' then
    v_seg := null;
  end if;
  if v_seg is not null
     and v_seg not in ('nuevo', 'ocasional', 'frecuente', 'inactivo', 'registrado') then
    raise exception 'Segmento inválido.';
  end if;

  if v_buscar is not null then
    -- Escapa \ primero, despues % y _ (el escape por defecto de ILIKE es \).
    v_pat := '%' || replace(replace(replace(v_buscar, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with base as (
    select c.telefono,
           c.nombre,
           c.apellido,
           c.cantidad_pedidos_entregados as pedidos,
           c.monto_total_gastado as gasto,
           c.ultima_visita,
           c.acepta_promos,
           c.fidelidad_pedidos,
           public.pm_crm_segmento(c.cantidad_pedidos_entregados, c.ultima_visita, v_umbrales) as segmento
      from public.clientes c
     where v_pat is null
        or c.nombre ilike v_pat
        or coalesce(c.apellido, '') ilike v_pat
        or (c.nombre || ' ' || coalesce(c.apellido, '')) ilike v_pat
        or c.telefono ilike v_pat
  ),
  f as (
    select b.*
      from base b
     where v_seg is null or b.segmento = v_seg
  ),
  o as (
    select f.*,
           row_number() over (
             order by
               case when v_orden = 'pedidos'       and v_dir = 'asc'  then f.pedidos       end asc  nulls last,
               case when v_orden = 'pedidos'       and v_dir = 'desc' then f.pedidos       end desc nulls last,
               case when v_orden = 'gasto'         and v_dir = 'asc'  then f.gasto         end asc  nulls last,
               case when v_orden = 'gasto'         and v_dir = 'desc' then f.gasto         end desc nulls last,
               case when v_orden = 'ultima_visita' and v_dir = 'asc'  then f.ultima_visita end asc  nulls last,
               case when v_orden = 'ultima_visita' and v_dir = 'desc' then f.ultima_visita end desc nulls last,
               f.telefono
           ) as rn
      from f
  )
  select (select count(*) from f),
         coalesce((select jsonb_agg(jsonb_build_object(
                     'telefono', o.telefono,
                     'nombre', o.nombre,
                     'apellido', o.apellido,
                     'pedidos', o.pedidos,
                     'gasto', o.gasto,
                     'ticket_promedio', case when o.pedidos > 0 then round(o.gasto / o.pedidos, 2) else 0 end,
                     'ultima_visita', o.ultima_visita,
                     'dias_sin_pedir', case when o.ultima_visita is null then null
                                            else (now() at time zone c_tz)::date
                                               - (o.ultima_visita at time zone c_tz)::date end,
                     'acepta_promos', o.acepta_promos,
                     'segmento', o.segmento,
                     'fidelidad_pedidos', o.fidelidad_pedidos) order by o.rn)
                     from o
                    where o.rn > v_off and o.rn <= v_off + v_lim), '[]'::jsonb)
    into v_total, v_filas;

  return jsonb_build_object(
    'total', v_total,
    'limite', v_lim,
    'offset', v_off,
    'filas', v_filas);
end;
$$;

comment on function public.crm_clientes(text, text, text, text, integer, integer) is
  'Listado paginado de clientes con segmento para el dueno. Solo lectura.';

-- ----------------------------------------------------------------------------
-- 6. crm_cliente_ficha
-- ----------------------------------------------------------------------------
-- Devuelve null si el cliente no existe. El telefono se normaliza a digitos.
-- {cliente:{...}, fidelidad:{activo, ciclo, pedidos_contados, siguiente_nivel},
--  premios:{vigentes:[...], usados:[... ultimos 20]},
--  pedidos:[... ultimos 20: numero_orden, fecha, estado, total, sucursal, cupon_codigo],
--  favoritos:[... top 5: producto_id, nombre, cantidad]}   (favoritos: entregados, sin regalos)
create or replace function public.crm_cliente_ficha(p_telefono text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_tz constant text := 'America/Argentina/Buenos_Aires';
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g');
  v_umbrales jsonb := public.pm_crm_umbrales();
  v_c public.clientes%rowtype;
  v_cfg jsonb;
  v_sig jsonb;
  v_fid jsonb;
  v_vigentes jsonb;
  v_usados jsonb;
  v_pedidos jsonb;
  v_fav jsonb;
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  if v_tel !~ '^[0-9]{8,15}$' then
    return null;
  end if;

  select * into v_c from public.clientes where telefono = v_tel;
  if not found then
    return null;
  end if;

  -- Progreso de fidelidad (pm_fidelidad_config devuelve null si esta inactivo)
  v_cfg := public.pm_fidelidad_config();
  if v_cfg is null then
    v_fid := jsonb_build_object('activo', false, 'pedidos_contados', v_c.fidelidad_pedidos);
  else
    select jsonb_build_object(
             'en', (n.value ->> 'en')::integer,
             'tipo', n.value ->> 'tipo',
             'valor', n.value -> 'valor',
             'producto_id', n.value ->> 'producto_id',
             'faltan', (n.value ->> 'en')::integer - v_c.fidelidad_pedidos)
      into v_sig
      from jsonb_array_elements(v_cfg -> 'niveles') as n(value)
     where (n.value ->> 'en')::integer > v_c.fidelidad_pedidos
     order by (n.value ->> 'en')::integer
     limit 1;
    v_fid := jsonb_build_object(
      'activo', true,
      'ciclo', (v_cfg ->> 'ciclo')::integer,
      'pedidos_contados', v_c.fidelidad_pedidos,
      'siguiente_nivel', v_sig);
  end if;

  -- Premios vigentes (sin usar y no vencidos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pr.id, 'tipo', pr.tipo, 'valor', pr.valor,
           'producto_id', pr.producto_id, 'tope_en_pesos', pr.tope_en_pesos,
           'vencimiento', pr.vencimiento, 'creado_en', pr.creado_en)
           order by pr.vencimiento), '[]'::jsonb)
    into v_vigentes
    from public.premios pr
   where pr.telefono = v_tel and not pr.usado and pr.vencimiento > now();

  -- Premios usados (ultimos 20)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id, 'tipo', q.tipo, 'valor', q.valor,
           'producto_id', q.producto_id, 'usado_en', q.usado_en)
           order by q.usado_en desc), '[]'::jsonb)
    into v_usados
    from (select pr.id, pr.tipo, pr.valor, pr.producto_id, pr.usado_en
            from public.premios pr
           where pr.telefono = v_tel and pr.usado
           order by pr.usado_en desc nulls last
           limit 20) q;

  -- Ultimos 20 pedidos
  select coalesce(jsonb_agg(jsonb_build_object(
           'numero_orden', q.numero_orden,
           'fecha', q.created_at,
           'estado', q.estado,
           'total', q.total,
           'sucursal', q.sucursal_id,
           'cupon_codigo', q.cupon_codigo) order by q.created_at desc), '[]'::jsonb)
    into v_pedidos
    from (select p.numero_orden, p.created_at, p.estado, p.total, p.sucursal_id, p.cupon_codigo
            from public.pedidos p
           where p.cliente_telefono = v_tel
             and p.sincronizado is distinct from false
           order by p.created_at desc
           limit 20) q;

  -- Top 5 productos favoritos (entregados, sin regalos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'producto_id', t.producto_id, 'nombre', t.nombre, 'cantidad', t.cantidad)
           order by t.cantidad desc, t.producto_id), '[]'::jsonb)
    into v_fav
    from (select i.value ->> 'producto_id' as producto_id,
                 max(i.value ->> 'nombre') as nombre,
                 sum(coalesce(public.pm_num(i.value ->> 'cantidad'), 0)) as cantidad
            from public.pedidos p
           cross join lateral jsonb_array_elements(p.items_snapshot) as i(value)
           where p.cliente_telefono = v_tel
             and p.estado = 'entregado'
             and p.sincronizado is distinct from false
             and coalesce(i.value ->> 'regalo', 'false') <> 'true'
             and i.value ->> 'producto_id' is not null
           group by 1
           order by 3 desc, 1
           limit 5) t;

  return jsonb_build_object(
    'cliente', jsonb_build_object(
      'telefono', v_c.telefono,
      'nombre', v_c.nombre,
      'apellido', v_c.apellido,
      'acepta_promos', v_c.acepta_promos,
      'acepta_promos_en', v_c.acepta_promos_en,
      'registrado_en', v_c.registrado_en,
      'origen', v_c.origen,
      'pedidos', v_c.cantidad_pedidos_entregados,
      'gasto', v_c.monto_total_gastado,
      'ticket_promedio', case when v_c.cantidad_pedidos_entregados > 0
                              then round(v_c.monto_total_gastado / v_c.cantidad_pedidos_entregados, 2)
                              else 0 end,
      'ultima_visita', v_c.ultima_visita,
      'dias_sin_pedir', case when v_c.ultima_visita is null then null
                             else (now() at time zone c_tz)::date
                                - (v_c.ultima_visita at time zone c_tz)::date end,
      'segmento', public.pm_crm_segmento(v_c.cantidad_pedidos_entregados, v_c.ultima_visita, v_umbrales)),
    'fidelidad', v_fid,
    'premios', jsonb_build_object('vigentes', v_vigentes, 'usados', v_usados),
    'pedidos', v_pedidos,
    'favoritos', v_fav);
end;
$$;

comment on function public.crm_cliente_ficha(text) is
  'Ficha completa de un cliente (datos, fidelidad, premios, pedidos, favoritos) para el dueno. Solo lectura.';

-- ----------------------------------------------------------------------------
-- 7. crm_exportar
-- ----------------------------------------------------------------------------
-- Filas para CSV (max 5000), solo los campos necesarios para una campana.
-- p_segmento null/'todos' = todos. p_solo_promos true = solo acepta_promos.
-- OJO frontend: al armar el CSV se debe prefijar ' a los valores que empiecen
-- con = + - @ (ya existe esa proteccion en admin.js).
create or replace function public.crm_exportar(
  p_segmento text default null,
  p_solo_promos boolean default false
)
returns table (
  telefono text,
  nombre text,
  apellido text,
  segmento text,
  pedidos integer,
  gasto_total numeric,
  ultima_visita timestamptz,
  acepta_promos boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_seg text := lower(nullif(btrim(coalesce(p_segmento, '')), ''));
  v_umbrales jsonb := public.pm_crm_umbrales();
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  if v_seg = 'todos' then
    v_seg := null;
  end if;
  if v_seg is not null
     and v_seg not in ('nuevo', 'ocasional', 'frecuente', 'inactivo', 'registrado') then
    raise exception 'Segmento inválido.';
  end if;

  return query
  select q.telefono, q.nombre, q.apellido, q.segmento, q.pedidos,
         q.gasto_total, q.ultima_visita, q.acepta_promos
    from (select c.telefono,
                 c.nombre,
                 c.apellido,
                 public.pm_crm_segmento(c.cantidad_pedidos_entregados, c.ultima_visita, v_umbrales) as segmento,
                 c.cantidad_pedidos_entregados as pedidos,
                 c.monto_total_gastado as gasto_total,
                 c.ultima_visita,
                 c.acepta_promos
            from public.clientes c
           where not coalesce(p_solo_promos, false) or c.acepta_promos) q
   where v_seg is null or q.segmento = v_seg
   order by q.ultima_visita desc nulls last, q.telefono
   limit 5000;
end;
$$;

comment on function public.crm_exportar(text, boolean) is
  'Clientes para exportar a CSV (max 5000) para el dueno. Solo lectura.';

-- ----------------------------------------------------------------------------
-- 8. crm_inactivos_promos
-- ----------------------------------------------------------------------------
-- Inactivos que aceptaron promos, con telefono y nombre (boton de WhatsApp).
-- p_limite: 1..500 (default 100). Los que se perdieron hace menos van primero.
create or replace function public.crm_inactivos_promos(p_limite integer default 100)
returns table (
  telefono text,
  nombre text,
  apellido text,
  pedidos integer,
  ultima_visita timestamptz,
  dias_sin_pedir integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_tz constant text := 'America/Argentina/Buenos_Aires';
  v_lim integer := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_umbrales jsonb := public.pm_crm_umbrales();
begin
  if not public.es_dueno() then
    raise exception 'No tenés permiso para hacer esto.';
  end if;

  return query
  select c.telefono,
         c.nombre,
         c.apellido,
         c.cantidad_pedidos_entregados,
         c.ultima_visita,
         ((now() at time zone c_tz)::date - (c.ultima_visita at time zone c_tz)::date)
    from public.clientes c
   where c.acepta_promos
     and c.telefono is not null
     and nullif(btrim(c.nombre), '') is not null
     and public.pm_crm_segmento(c.cantidad_pedidos_entregados, c.ultima_visita, v_umbrales) = 'inactivo'
   order by c.ultima_visita desc
   limit v_lim;
end;
$$;

comment on function public.crm_inactivos_promos(integer) is
  'Clientes inactivos que aceptan promos (para WhatsApp) para el dueno. Solo lectura.';

-- ----------------------------------------------------------------------------
-- 9. Permisos: solo authenticated (y dentro, solo el dueno por es_dueno())
-- ----------------------------------------------------------------------------
revoke all on function public.stats_resumen(timestamptz, timestamptz, text) from public, anon;
revoke all on function public.stats_cupones_fidelidad(timestamptz, timestamptz, text) from public, anon;
revoke all on function public.crm_clientes(text, text, text, text, integer, integer) from public, anon;
revoke all on function public.crm_cliente_ficha(text) from public, anon;
revoke all on function public.crm_exportar(text, boolean) from public, anon;
revoke all on function public.crm_inactivos_promos(integer) from public, anon;

grant execute on function public.stats_resumen(timestamptz, timestamptz, text) to authenticated;
grant execute on function public.stats_cupones_fidelidad(timestamptz, timestamptz, text) to authenticated;
grant execute on function public.crm_clientes(text, text, text, text, integer, integer) to authenticated;
grant execute on function public.crm_cliente_ficha(text) to authenticated;
grant execute on function public.crm_exportar(text, boolean) to authenticated;
grant execute on function public.crm_inactivos_promos(integer) to authenticated;

-- ============================================================================
-- VERIFICACION DE PERMISOS (correr despues de aplicar; todo comentado)
-- ============================================================================
-- Esperado: anon = false, authenticated = true para las 6 publicas;
-- los 5 helpers dan false para anon y authenticated.
--
--   select f.firma,
--          has_function_privilege('anon', f.firma, 'execute')          as anon,
--          has_function_privilege('authenticated', f.firma, 'execute') as authenticated
--     from (values
--       ('public.stats_resumen(timestamptz,timestamptz,text)'),
--       ('public.stats_cupones_fidelidad(timestamptz,timestamptz,text)'),
--       ('public.crm_clientes(text,text,text,text,integer,integer)'),
--       ('public.crm_cliente_ficha(text)'),
--       ('public.crm_exportar(text,boolean)'),
--       ('public.crm_inactivos_promos(integer)'),
--       ('public.pm_num(text)'),
--       ('public.pm_variacion_pct(numeric,numeric)'),
--       ('public.pm_stats_sucursal_ok(text)'),
--       ('public.pm_crm_umbrales()'),
--       ('public.pm_crm_segmento(integer,timestamptz,jsonb)')
--     ) as f(firma);
--
-- Ojo: en Supabase los privilegios por defecto dan execute a anon, por eso se
-- hace revoke explicito de anon ademas de public.

-- ============================================================================
-- CASOS DE PRUEBA (todo comentado; correr en el SQL Editor a mano)
-- ============================================================================
-- El SQL Editor corre como postgres y auth.jwt() no tiene email, asi que
-- para probar como dueno hay que simular el JWT en una transaccion:
--
--   begin;
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     '{"email":"EMAIL_DEL_DUENO@dominio.com"}', true);
--   -- ... pruebas ...
--   rollback;
--
-- T1. No-dueno rechazado (email que NO es dueno, o sin claims):
--   select set_config('request.jwt.claims', '{"email":"nadie@x.com"}', true);
--   select public.stats_resumen(now() - interval '7 days', now());
--   -- Esperado: ERROR  No tenés permiso para hacer esto.
--   -- Idem con las otras 5 funciones (crm_cliente_ficha('3834000000'), etc.).
--
-- T2. Periodo vacio (sin pedidos, o desde = hasta):
--   select public.stats_resumen('2000-01-01', '2000-01-03');
--   -- Esperado: facturacion 0, pedidos 0, ticket_promedio 0, ventas_por_dia con
--   --   2 dias en 0, ventas_por_hora con 24 filas en 0, listas vacias,
--   --   variacion.* = null (anterior en 0).
--   select public.stats_resumen(now(), now());
--   -- Esperado: ventas_por_dia = [], todo en 0, sin error.
--
-- T3. Sucursal inexistente:
--   select public.stats_resumen(now() - interval '30 days', now(), 'no-existe');
--   select public.stats_cupones_fidelidad(now() - interval '30 days', now(), 'no-existe');
--   -- Esperado: todo en 0 / listas vacias, SIN error.
--
-- T4. No sincronizado excluido:
--   -- Elegir un pedido entregado del periodo y anotar facturacion/pedidos:
--   --   select public.stats_resumen(<rango>) ->> 'facturacion';
--   -- Marcarlo (dentro de la transaccion de prueba, con rol postgres):
--   --   update public.pedidos set sincronizado = false where numero_orden = 'PM-XXXX';
--   -- Esperado: facturacion baja en su total, pedidos baja en 1, ingresados baja en 1.
--   -- (hacer rollback al terminar)
--
-- T5. Cancelado excluido de facturacion y de cupones:
--   -- update public.pedidos set estado = 'cancelado' where numero_orden = 'PM-XXXX';
--   -- (el trigger de 021 valida transiciones; probarlo con un pedido 'pendiente')
--   -- Esperado: facturacion no lo suma; 'cancelados' +1; stats_cupones_fidelidad
--   --   no cuenta su cupon (usos/ventas/descuento).
--
-- T6. Regalos sin ingresos:
--   -- Con un pedido entregado que tenga un item regalo = true (premio de producto
--   -- gratis): en stats_resumen 'regalos' >= 1, y el producto regalado NO suma
--   -- cantidad ni ingresos en top_productos por ese item. Ver ademas:
--   select public.stats_cupones_fidelidad(<rango>) -> 'fidelidad';
--   -- regalos >= 1; regalos_costo_estimado = null mientras el snapshot traiga
--   -- precio_regular = 0 (regalos_sin_costo = regalos).
--
-- T7. Comparacion con periodo anterior en 0:
--   -- Elegir un rango cuyo periodo anterior no tenga pedidos entregados
--   -- (p. ej. desde = fecha del primer pedido):
--   select public.stats_resumen(<primer_pedido>, <primer_pedido> + interval '7 days') -> 'variacion';
--   -- Esperado: facturacion_pct / pedidos_pct / ticket_pct = null (no 0, no error),
--   --   anterior.facturacion = 0.
--   -- Con anterior > 0: variacion = round((act - ant) / ant * 100, 1).
--
-- T8. Busqueda con % y _ (se tratan como literales):
--   select public.crm_clientes('%', null, null, null, 10, 0) ->> 'total';
--   -- Esperado: solo clientes cuyo nombre/apellido/telefono contiene un '%' literal
--   --   (normalmente 0), NO todos los clientes.
--   select public.crm_clientes('_', null, null, null, 10, 0) ->> 'total';
--   -- Esperado: solo los que contienen '_' literal (normalmente 0).
--   select public.crm_clientes('Jo_n', null, null, null, 10, 0) ->> 'total';
--   -- Esperado: NO matchea "Joan" ni "John".
--
-- T9. Orden con lista blanca y paginado:
--   select public.crm_clientes(null, 'gasto; drop table clientes', 'x', null, 5000, -3);
--   -- Esperado: sin error, orden por ultima_visita desc, limite 200, offset 0.
--   select public.crm_clientes(null, 'gasto', 'desc', 'frecuente', 10, 0);
--   select public.crm_clientes(null, null, null, 'otro', 10, 0);   -- ERROR Segmento inválido.
--
-- T10. Segmentos y config invalida:
--   update public.config_negocio set valor = '"basura"' where clave = 'crm_segmentos';
--   select public.pm_crm_umbrales();   -- (como postgres) defaults 5 / 2 / 30
--   -- Restaurar: update public.config_negocio
--   --   set valor = '{"frecuente_min":5,"ocasional_min":2,"inactivo_dias":30}'
--   --   where clave = 'crm_segmentos';
--
-- T11. Ficha / exportar / inactivos:
--   select public.crm_cliente_ficha('3834000000');      -- null si no existe
--   select public.crm_cliente_ficha('(383) 400-0000');  -- normaliza a digitos
--   select * from public.crm_exportar('inactivo', true);
--   select * from public.crm_inactivos_promos(20);
--   -- Esperado: solo acepta_promos = true, segmento inactivo, con telefono y nombre.

-- ============================================================================
-- ROLLBACK (todo comentado; no borra datos de negocio)
-- ============================================================================
--   drop function if exists public.crm_inactivos_promos(integer);
--   drop function if exists public.crm_exportar(text, boolean);
--   drop function if exists public.crm_cliente_ficha(text);
--   drop function if exists public.crm_clientes(text, text, text, text, integer, integer);
--   drop function if exists public.stats_cupones_fidelidad(timestamptz, timestamptz, text);
--   drop function if exists public.stats_resumen(timestamptz, timestamptz, text);
--   drop function if exists public.pm_crm_segmento(integer, timestamptz, jsonb);
--   drop function if exists public.pm_crm_umbrales();
--   drop function if exists public.pm_stats_sucursal_ok(text);
--   drop function if exists public.pm_variacion_pct(numeric, numeric);
--   drop function if exists public.pm_num(text);
--   drop index if exists public.premios_usado_en_idx;
--   drop index if exists public.premios_creado_en_idx;
--   drop index if exists public.pedidos_telefono_created_at_idx;
--   drop index if exists public.pedidos_sucursal_created_at_idx;
--   delete from public.config_negocio where clave = 'crm_segmentos';
