-- ============================================================================
-- 021_seguridad_envio_estados.sql
-- Seguridad: envio por coordenadas, transiciones de estado y premio liberado
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP de la base (Supabase > Database > Backups,
-- o pg_dump). Esta migracion recrea una funcion de dinero y agrega un trigger
-- sobre pedidos.
--
-- Prerrequisitos (ya aplicadas): 010, 016, 017 (es_dueno, pm_calcular_pedido),
-- 019 (pm_pedidos_liberar_premio). No se modifica ninguna migracion anterior.
--
-- Que hace:
--   1. pm_calcular_pedido: en delivery, si la zona usa tramos y hay tramos
--      activos, las coordenadas son OBLIGATORIAS y validas; ademas se rechazan
--      coordenadas a mas de 'envio_radio_max_km' (config_negocio, default 30)
--      de la sucursal. Es la version de 017 con SOLO el bloque de envio
--      cambiado (ofertas, agotados_sucursal, variaciones y tramos intactos).
--      Firma identica: crear_pedido, valida_cupon, etc. siguen igual.
--   2. Trigger BEFORE UPDATE OF estado en pedidos que valida las transiciones.
--   3. Columna pedidos.entregado_en (la setea el trigger; sin grant de UPDATE)
--      y pm_pedidos_liberar_premio no libera premios de pedidos que ya
--      estuvieron entregados.
--
-- Idempotente: se puede correr mas de una vez.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. pm_calcular_pedido (017) con envio endurecido
-- ----------------------------------------------------------------------------
-- Config opcional (no hace falta crearla; sin fila vale 30):
--   insert into public.config_negocio (clave, valor)
--   values ('envio_radio_max_km', '30'::jsonb)
--   on conflict (clave) do update set valor = excluded.valor;
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
  v_radio_km numeric;
  v_hay_tramos boolean;
  v_coords_ok boolean;
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

    v_hay_tramos := v_zona_row.aplica_tramos and exists (
      select 1 from public.tramos_envio t
       where t.activa and (t.sucursal_id = p_sucursal_id or t.sucursal_id is null)
    );

    -- 021: coordenadas validas (ambas presentes y dentro de rango).
    v_coords_ok := p_lat is not null and p_lng is not null
                   and p_lat between -90 and 90 and p_lng between -180 and 180;

    -- 021: con tramos activos las coordenadas son obligatorias; si vinieron
    -- pero son invalidas (una sola, o fuera de rango) tambien se rechaza.
    if (v_hay_tramos and not v_coords_ok)
       or ((p_lat is not null or p_lng is not null) and not v_coords_ok) then
      raise exception 'Elegí una dirección del buscador para calcular el envío.';
    end if;

    if v_coords_ok then
      v_lat0 := (v_suc ->> 'lat')::numeric;
      v_lng0 := (v_suc ->> 'lng')::numeric;

      -- Distancia en linea recta (haversine) desde la sucursal, en metros.
      v_metros := 2 * 6371000 * asin(sqrt(least(1,
          power(sin(radians(p_lat - v_lat0) / 2), 2)
        + cos(radians(v_lat0)) * cos(radians(p_lat))
          * power(sin(radians(p_lng - v_lng0) / 2), 2))));

      -- 021: radio maximo de entrega (config_negocio 'envio_radio_max_km', default 30).
      select case when c.valor #>> '{}' ~ '^[0-9]+(\.[0-9]+)?$'
                  then (c.valor #>> '{}')::numeric end
        into v_radio_km
        from public.config_negocio c where c.clave = 'envio_radio_max_km';
      if v_radio_km is null or v_radio_km <= 0 then v_radio_km := 30; end if;
      if v_metros > v_radio_km * 1000 then
        raise exception 'La dirección queda fuera de la zona de entrega (máximo % km de la sucursal).',
          trim_scale(v_radio_km)::text;
      end if;
    end if;

    -- Tramos por cuadras (distancia en linea recta, redondeada hacia arriba)
    if v_hay_tramos and v_coords_ok then
      select coalesce(nullif(c.valor #>> '{}', '')::numeric, 100) into v_mpc
        from public.config_negocio c where c.clave = 'metros_por_cuadra';
      if v_mpc is null or v_mpc <= 0 then v_mpc := 100; end if;

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
  'Calcula el pedido en el servidor. Rechaza agotados por sucursal; en delivery con tramos exige coordenadas validas dentro del radio maximo (021).';

-- ----------------------------------------------------------------------------
-- 2. pedidos.entregado_en
-- ----------------------------------------------------------------------------
-- La setea SOLO el trigger de abajo la primera vez que el pedido pasa a
-- entregado. No se agrega al grant de UPDATE de authenticated (016 da UPDATE
-- solo sobre estado, pagado y pagado_en), asi que el cliente no puede escribirla.
alter table public.pedidos
  add column if not exists entregado_en timestamptz;

comment on column public.pedidos.entregado_en is
  'Primera vez que el pedido paso a entregado. La setea el trigger (021); nunca se borra.';

-- Backfill de pedidos ya entregados (aproximado: usa created_at). No dispara
-- los triggers de estado porque no toca esa columna.
update public.pedidos
   set entregado_en = created_at
 where estado = 'entregado'
   and entregado_en is null;

-- ----------------------------------------------------------------------------
-- 3. Trigger de transiciones de estado
-- ----------------------------------------------------------------------------
-- Reglas (valen para admin de sucursal y dueno):
--   pendiente  -> confirmado | cancelado
--   confirmado -> listo | cancelado
--   listo      -> en_camino | entregado | cancelado
--   en_camino  -> entregado | cancelado
--   entregado  -> nada                  (dueno: puede corregir a cancelado)
--   cancelado  -> nada                  (dueno: puede volver a pendiente)
-- en_camino solo existe en delivery: un retiro nunca pasa por ahi.
-- Solo se controlan las sesiones de la API (roles authenticated / anon); el
-- SQL Editor y service_role (sin esos roles) quedan sin restriccion para
-- poder reparar datos a mano.
create or replace function public.pm_pedidos_validar_estado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_permitido boolean := false;
begin
  if new.estado is not distinct from old.estado then
    return new;
  end if;

  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    if new.estado = 'en_camino' and old.modalidad is distinct from 'delivery' then
      raise exception 'Un pedido de retiro no puede pasar a "en camino".';
    end if;

    v_permitido := case old.estado
      when 'pendiente'  then new.estado in ('confirmado', 'cancelado')
      when 'confirmado' then new.estado in ('listo', 'cancelado')
      when 'listo'      then new.estado in ('en_camino', 'entregado', 'cancelado')
      when 'en_camino'  then new.estado in ('entregado', 'cancelado')
      else false
    end;

    -- Excepciones solo para el dueno: corregir errores de carga.
    if not v_permitido and public.es_dueno() then
      v_permitido := (old.estado = 'entregado' and new.estado = 'cancelado')
                  or (old.estado = 'cancelado' and new.estado = 'pendiente');
    end if;

    if not v_permitido then
      if old.estado = 'entregado' then
        raise exception 'Un pedido entregado no se puede modificar. Solo el dueño puede cancelarlo.';
      elsif old.estado = 'cancelado' then
        raise exception 'Un pedido cancelado no se puede reactivar. Solo el dueño puede volverlo a pendiente.';
      else
        raise exception 'No se puede pasar un pedido de "%" a "%".', old.estado, new.estado;
      end if;
    end if;
  end if;

  -- Primera vez que se entrega; se conserva aunque despues se corrija.
  if new.estado = 'entregado' and old.estado is distinct from 'entregado' then
    new.entregado_en := coalesce(old.entregado_en, now());
  end if;

  return new;
end;
$$;

revoke all on function public.pm_pedidos_validar_estado() from public, anon, authenticated;

comment on function public.pm_pedidos_validar_estado() is
  'Valida las transiciones de estado de pedidos y setea entregado_en (021). El dueno puede corregir entregado->cancelado y cancelado->pendiente.';

drop trigger if exists pedidos_validar_estado on public.pedidos;
create trigger pedidos_validar_estado
  before update of estado on public.pedidos
  for each row
  execute function public.pm_pedidos_validar_estado();

-- ----------------------------------------------------------------------------
-- 4. pm_pedidos_liberar_premio (019): no liberar si el pedido ya estuvo entregado
-- ----------------------------------------------------------------------------
-- Unico cambio respecto de 019: "and old.entregado_en is null". Un pedido que
-- ya fue entregado consumio el premio de verdad; si el dueno lo corrige a
-- cancelado, el premio NO vuelve a quedar disponible. El trigger
-- pedidos_liberar_premio (AFTER UPDATE OF estado) de 019 sigue enlazado.
create or replace function public.pm_pedidos_liberar_premio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado = 'cancelado' and old.estado is distinct from 'cancelado'
     and old.entregado_en is null then
    -- Solo se libera si no vencio: un premio vencido queda como usado.
    update public.premios
       set usado = false,
           usado_en = null,
           pedido_id = null
     where pedido_id = new.id
       and usado
       and vencimiento > now();
  end if;
  return new;
end;
$$;

revoke all on function public.pm_pedidos_liberar_premio() from public, anon, authenticated;

comment on function public.pm_pedidos_liberar_premio() is
  'Al cancelar un pedido que uso un premio, lo deja disponible de nuevo (si no vencio y el pedido nunca fue entregado).';

-- ----------------------------------------------------------------------------
-- 5. Verificacion final
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgname = 'pedidos_validar_estado' and not tgisinternal) then
    raise exception '021: falta el trigger pedidos_validar_estado.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'pedidos'
                    and column_name = 'entregado_en') then
    raise exception '021: falta pedidos.entregado_en.';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Compatibilidad con el tablero del admin (revisado en admin.js)
-- ----------------------------------------------------------------------------
-- El tablero solo hace UPDATE de estado en actualizarEstadoPedido():
--   Avanzar: pendiente->confirmado, confirmado->listo,
--            listo->en_camino (delivery) o listo->entregado (retiro),
--            en_camino->entregado.
--   Cancelar (boton visible si no esta entregado/cancelado): desde pendiente,
--            confirmado, listo o en_camino.
-- Todas estan permitidas. "Marcar pagado" actualiza pagado/pagado_en, no
-- estado, asi que el trigger ni se dispara. No hay boton de reactivar ni de
-- corregir entregados: esas dos excepciones del dueno solo se hacen por API
-- o SQL (el tablero no las ofrece).
-- Un pedido de retiro viejo que haya quedado en en_camino puede seguir
-- ->entregado/cancelado (el trigger solo bloquea ENTRAR a en_camino).

-- ----------------------------------------------------------------------------
-- 7. Casos de prueba (comentados; correr a mano en un entorno de prueba)
-- ----------------------------------------------------------------------------
-- Envio (llamar a public.pm_calcular_pedido como postgres/SQL Editor):
--   -- Delivery, zona con tramos, SIN coordenadas       -> "Elegí una dirección del buscador para calcular el envío."
--   -- Delivery, zona con tramos, lat=95                -> mismo error
--   -- Delivery, solo p_lat sin p_lng                   -> mismo error
--   -- Delivery con coordenadas a ~40 km de la sucursal -> "La dirección queda fuera de la zona de entrega (máximo 30 km de la sucursal)."
--   -- Delivery con coordenadas cercanas                -> OK, costo_envio = costo del tramo
--   -- Retiro sin coordenadas                           -> OK (no se exigen)
--   -- Cambiar el radio: update public.config_negocio set valor = '10'::jsonb where clave = 'envio_radio_max_km';
--
-- Estados (como admin de sucursal):
--   set local role authenticated;
--   set local request.jwt.claims = '{"role":"authenticated","email":"EMAIL_SUCURSAL"}';
--   update public.pedidos set estado = 'entregado' where id = '<pendiente>';      -- ERROR (pendiente -> entregado)
--   update public.pedidos set estado = 'confirmado' where id = '<pendiente>';     -- OK
--   update public.pedidos set estado = 'en_camino' where id = '<retiro listo>';   -- ERROR (retiro)
--   update public.pedidos set estado = 'pendiente' where id = '<cancelado>';      -- ERROR (solo dueño)
--   update public.pedidos set estado = 'cancelado' where id = '<entregado>';      -- ERROR (solo dueño)
-- Como dueno (claims con EMAIL_DUENO):
--   update ... set estado = 'cancelado' where id = '<entregado>';                 -- OK
--   update ... set estado = 'pendiente' where id = '<cancelado>';                 -- OK
--   update ... set estado = 'confirmado' where id = '<cancelado>';                -- ERROR
-- entregado_en:
--   select id, estado, entregado_en from public.pedidos where estado = 'entregado' limit 5;  -- no nulo
-- Premio:
--   -- Pedido con premio -> cancelar estando pendiente: el premio vuelve a disponible.
--   -- Pedido con premio -> entregado -> el dueno lo cancela: el premio sigue usado.

-- ----------------------------------------------------------------------------
-- 8. Rollback manual (comentado; no ejecutar sin backup)
-- ----------------------------------------------------------------------------
-- begin;
--   drop trigger if exists pedidos_validar_estado on public.pedidos;
--   drop function if exists public.pm_pedidos_validar_estado();
--   -- Volver pm_pedidos_liberar_premio a la version de 019: copiar la funcion
--   -- de 019_fidelidad_premios.sql (seccion 5) sin "and old.entregado_en is null".
--   -- Volver pm_calcular_pedido a la version de 017: re-ejecutar el
--   -- "create or replace function public.pm_calcular_pedido" de la seccion 8
--   -- de 017_admin_por_sucursal.sql.
--   -- La columna es inofensiva; si se quiere sacar (despues de revertir la
--   -- funcion de premios):
--   -- alter table public.pedidos drop column if exists entregado_en;
-- commit;
