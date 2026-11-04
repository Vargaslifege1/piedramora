-- Piedra Mora - Fase 1 - Paso 1C
-- RPC public.crear_pedido: guarda el pedido antes de abrir WhatsApp.
--
-- Decisiones:
--   - El servidor es la fuente de verdad de precios, ofertas y totales.
--   - El cliente envia solo ids, cantidades y datos de contacto.
--   - La clave de idempotencia evita duplicados por doble clic o reintento.
--   - El envio se guarda en 0 y la zona como "Zona normal" por ahora.
--     El checkout publico todavia no calcula ni cobra envio.
--   - Las ofertas se validan con oferta_desde/oferta_hasta en horario argentino.
--
-- No ejecutar contra la base real sin confirmacion.

create or replace function public.crear_pedido(
  p_sucursal_id text,
  p_modalidad text,
  p_cliente_nombre text,
  p_cliente_telefono text,
  p_direccion text,
  p_lat numeric,
  p_lng numeric,
  p_pago_tipo text,
  p_notas text,
  p_items jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_carta jsonb;
  v_descuentos jsonb;

  v_modalidad text;
  v_sucursal_id text;
  v_pago_tipo text;
  v_nombre text;
  v_telefono text;
  v_notas text;
  v_direccion text;
  v_zona text;
  v_lat numeric;
  v_lng numeric;
  v_pct numeric := 0;

  v_item jsonb;
  v_prod jsonb;
  v_categoria text;
  v_producto_id text;
  v_cantidad integer;
  v_total_unidades integer := 0;
  v_hoy text;

  v_variacion_id text;
  v_variacion jsonb;
  v_variacion_nombre text;
  v_variacion_precio numeric;
  v_opciones jsonb;
  v_opciones_pan jsonb;
  v_es_solo_pan boolean;
  v_permite_adicionales boolean;
  v_oferta_activa boolean;

  v_adicionales jsonb;
  v_adicionales_out jsonb;
  v_add_id text;
  v_add jsonb;
  v_add_nombre text;
  v_add_precio numeric;
  v_precio_adicionales numeric;

  v_precio_regular numeric;
  v_precio_oferta numeric;
  v_precio_base numeric;
  v_precio_unitario numeric;
  v_subtotal_item numeric;
  v_items_out jsonb := '[]'::jsonb;

  v_subtotal numeric(12, 2) := 0;
  v_descuento numeric(12, 2) := 0;
  v_envio numeric(12, 2) := 0;
  v_total numeric(12, 2) := 0;
begin
  if p_idempotency_key is null then
    raise exception 'Falta la clave de idempotencia del pedido.';
  end if;

  -- Reintento: devolver el pedido ya creado.
  select * into v_pedido
    from public.pedidos
   where idempotency_key = p_idempotency_key;

  if found then
    return jsonb_build_object(
      'id', v_pedido.id,
      'numero_orden', v_pedido.numero_orden,
      'estado', v_pedido.estado,
      'created_at', v_pedido.created_at,
      'subtotal', v_pedido.subtotal,
      'descuento', v_pedido.descuento,
      'costo_envio', v_pedido.costo_envio,
      'total', v_pedido.total,
      'pago_tipo', v_pedido.metodo_pago,
      'items', v_pedido.items_snapshot,
      'reutilizado', true
    );
  end if;

  v_modalidad := lower(btrim(coalesce(p_modalidad, '')));
  if v_modalidad not in ('mesa', 'delivery', 'retiro') then
    raise exception 'Modalidad invalida.';
  end if;

  v_sucursal_id := btrim(coalesce(p_sucursal_id, ''));
  if char_length(v_sucursal_id) < 1 or char_length(v_sucursal_id) > 80 then
    raise exception 'Sucursal invalida.';
  end if;

  v_nombre := btrim(coalesce(p_cliente_nombre, ''));
  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then
    raise exception 'El nombre debe tener entre 2 y 80 caracteres.';
  end if;

  v_telefono := regexp_replace(coalesce(p_cliente_telefono, ''), '[^0-9]', '', 'g');
  if v_telefono !~ '^[0-9]{8,15}$' then
    raise exception 'El telefono debe tener entre 8 y 15 digitos.';
  end if;

  v_notas := nullif(btrim(coalesce(p_notas, '')), '');
  if v_notas is not null and char_length(v_notas) > 500 then
    raise exception 'Las notas no pueden superar los 500 caracteres.';
  end if;

  v_pago_tipo := lower(btrim(coalesce(p_pago_tipo, '')));
  if char_length(v_pago_tipo) < 1 or char_length(v_pago_tipo) > 40 then
    raise exception 'Forma de pago invalida.';
  end if;

  select valor into v_descuentos
    from public.config_negocio
   where clave = 'descuentos_pago';

  if v_descuentos is null or jsonb_typeof(v_descuentos) <> 'object' then
    raise exception 'No esta configurado el descuento por forma de pago.';
  end if;

  if not jsonb_exists(v_descuentos, v_pago_tipo) then
    raise exception 'Forma de pago no habilitada.';
  end if;

  v_pct := coalesce((v_descuentos ->> v_pago_tipo)::numeric, 0);
  if v_pct < 0 or v_pct > 100 then
    raise exception 'Descuento de pago invalido.';
  end if;

  if v_modalidad = 'delivery' then
    v_direccion := nullif(btrim(coalesce(p_direccion, '')), '');
    if v_direccion is null then
      raise exception 'Falta la direccion de entrega.';
    end if;
    if char_length(v_direccion) > 300 then
      raise exception 'La direccion no puede superar los 300 caracteres.';
    end if;

    if (p_lat is null) <> (p_lng is null) then
      raise exception 'La ubicacion GPS esta incompleta.';
    end if;
    if p_lat is not null and (p_lat < -90 or p_lat > 90) then
      raise exception 'Latitud invalida.';
    end if;
    if p_lng is not null and (p_lng < -180 or p_lng > 180) then
      raise exception 'Longitud invalida.';
    end if;

    v_lat := p_lat;
    v_lng := p_lng;
    v_zona := 'Zona normal';
  else
    v_direccion := null;
    v_lat := null;
    v_lng := null;
    v_zona := null;
  end if;

  select contenido into v_carta
    from public.carta
   where id = 1;

  if v_carta is null or jsonb_typeof(v_carta -> 'productos') <> 'array' then
    raise exception 'La carta no esta disponible.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'El pedido no tiene productos.';
  end if;

  if jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 50 then
    raise exception 'El pedido debe tener entre 1 y 50 lineas.';
  end if;

  v_hoy := to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD');

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Hay un item invalido en el pedido.';
    end if;

    v_producto_id := nullif(btrim(coalesce(v_item ->> 'producto_id', '')), '');
    if v_producto_id is null then
      raise exception 'Hay un producto sin id.';
    end if;

    v_cantidad := coalesce((v_item ->> 'cantidad')::integer, 0);
    if v_cantidad < 1 or v_cantidad > 50 then
      raise exception 'La cantidad de % debe estar entre 1 y 50.', v_producto_id;
    end if;

    v_total_unidades := v_total_unidades + v_cantidad;
    if v_total_unidades > 200 then
      raise exception 'El pedido supera el maximo de 200 unidades.';
    end if;

    select p.value into v_prod
      from jsonb_array_elements(v_carta -> 'productos') as p(value)
     where p.value ->> 'id' = v_producto_id
     limit 1;

    if v_prod is null then
      raise exception 'El producto % no existe en la carta.', v_producto_id;
    end if;

    if not exists (
      select 1
        from jsonb_array_elements_text(coalesce(v_prod -> 'sucursales', '[]'::jsonb)) as s(sucursal_id)
       where s.sucursal_id = v_sucursal_id
    ) then
      raise exception 'El producto % no esta disponible en esta sucursal.', v_producto_id;
    end if;

    if coalesce(v_prod ->> 'agotado', 'false') = 'true' then
      if coalesce(v_prod ->> 'agotado_hasta_nuevo_aviso', 'false') = 'true'
         or coalesce(v_prod ->> 'agotado_fecha', '') = v_hoy then
        raise exception 'El producto % esta agotado.', coalesce(v_prod ->> 'nombre', v_producto_id);
      end if;
    end if;

    v_categoria := lower(coalesce(v_prod ->> 'categoria', ''));
    v_permite_adicionales := v_categoria not in ('pizza', 'promo', 'lomo', 'milanesa');

    v_variacion_id := nullif(btrim(coalesce(v_item ->> 'variacion_id', '')), '');
    v_variacion := null;
    v_variacion_nombre := null;
    v_variacion_precio := 0;
    v_precio_adicionales := 0;
    v_adicionales_out := '[]'::jsonb;

    -- Lomo y milanesa solo admiten pan. Si la carta no trae las opciones,
    -- se generan las dos opciones historicas con precio 0.
    v_es_solo_pan := v_categoria in ('lomo', 'milanesa');
    v_opciones := '[]'::jsonb;

    if v_es_solo_pan then
      select coalesce(jsonb_agg(o.value order by o.value ->> 'nombre'), '[]'::jsonb)
        into v_opciones_pan
        from jsonb_array_elements(coalesce(v_prod -> 'variaciones' -> 'opciones', '[]'::jsonb)) as o(value)
       where (
         coalesce(o.value ->> 'id', '') || ' ' || coalesce(o.value ->> 'nombre', '')
       ) ~* '(pan|franc|arabe|árabe)';

      if jsonb_array_length(v_opciones_pan) >= 2 then
        v_opciones := v_opciones_pan;
      else
        v_opciones := jsonb_build_array(
          jsonb_build_object('id', v_producto_id || '_pan_frances', 'nombre', 'Pan frances', 'precio', 0),
          jsonb_build_object('id', v_producto_id || '_pan_arabe', 'nombre', 'Pan arabe', 'precio', 0)
        );
      end if;
    else
      v_opciones := coalesce(v_prod -> 'variaciones' -> 'opciones', '[]'::jsonb);
      if jsonb_typeof(v_opciones) <> 'array' then
        v_opciones := '[]'::jsonb;
      end if;
    end if;

    if v_variacion_id is not null then
      select o.value into v_variacion
        from jsonb_array_elements(v_opciones) as o(value)
       where o.value ->> 'id' = v_variacion_id
       limit 1;

      if v_variacion is null then
        raise exception 'La variacion elegida no es valida para %.', v_producto_id;
      end if;

      v_variacion_nombre := nullif(btrim(coalesce(v_variacion ->> 'nombre', '')), '');
      v_variacion_precio := coalesce((v_variacion ->> 'precio')::numeric, 0);
      if v_variacion_precio < 0 then
        raise exception 'El precio de la variacion no puede ser negativo.';
      end if;
    end if;

    if jsonb_array_length(v_opciones) > 0
       and (v_es_solo_pan or coalesce(v_prod -> 'variaciones' ->> 'obligatorio', 'false') = 'true')
       and v_variacion_id is null then
      raise exception 'Falta elegir la variacion de %.', v_producto_id;
    end if;

    if v_categoria in ('pizza', 'promo') and v_variacion_id is not null then
      raise exception 'El producto % no admite variaciones.', v_producto_id;
    end if;

    v_adicionales := coalesce(v_item -> 'adicionales_ids', '[]'::jsonb);
    if jsonb_typeof(v_adicionales) <> 'array' then
      raise exception 'Los adicionales de % son invalidos.', v_producto_id;
    end if;
    if jsonb_array_length(v_adicionales) > 10 then
      raise exception 'El producto % supera el maximo de 10 adicionales.', v_producto_id;
    end if;
    if jsonb_array_length(v_adicionales) > 0 and not v_permite_adicionales then
      raise exception 'El producto % no admite adicionales.', v_producto_id;
    end if;

    if (select count(*) from jsonb_array_elements_text(v_adicionales))
       <> (select count(distinct value) from jsonb_array_elements_text(v_adicionales) as t(value)) then
      raise exception 'Hay adicionales repetidos en %.', v_producto_id;
    end if;

    for v_add_id in select value from jsonb_array_elements_text(v_adicionales)
    loop
      select a.value into v_add
        from jsonb_array_elements(coalesce(v_prod -> 'adicionales', '[]'::jsonb)) as a(value)
       where a.value ->> 'id' = v_add_id
       limit 1;

      if v_add is null then
        raise exception 'El adicional % no es valido para %.', v_add_id, v_producto_id;
      end if;

      v_add_nombre := nullif(btrim(coalesce(v_add ->> 'nombre', '')), '');
      v_add_precio := coalesce((v_add ->> 'precio')::numeric, 0);
      if v_add_precio < 0 then
        raise exception 'El precio del adicional no puede ser negativo.';
      end if;

      v_precio_adicionales := v_precio_adicionales + v_add_precio;
      v_adicionales_out := v_adicionales_out || jsonb_build_array(
        jsonb_build_object(
          'id', v_add_id,
          'nombre', v_add_nombre,
          'precio', v_add_precio
        )
      );
    end loop;

    if v_modalidad = 'mesa' then
      v_precio_regular := coalesce(
        nullif(v_prod -> 'precios' ->> 'mesa', '')::numeric,
        nullif(v_prod -> 'precios' ->> 'delivery', '')::numeric,
        0
      );
    else
      v_precio_regular := coalesce(
        nullif(v_prod -> 'precios' ->> 'delivery', '')::numeric,
        nullif(v_prod -> 'precios' ->> 'mesa', '')::numeric,
        0
      );
    end if;

    if v_precio_regular <= 0 then
      raise exception 'El producto % no tiene un precio valido.', v_producto_id;
    end if;

    v_oferta_activa := true;
    if nullif(v_prod ->> 'oferta_desde', '') is not null
       and now() < (v_prod ->> 'oferta_desde')::timestamptz then
      v_oferta_activa := false;
    end if;
    if nullif(v_prod ->> 'oferta_hasta', '') is not null
       and now() > (v_prod ->> 'oferta_hasta')::timestamptz then
      v_oferta_activa := false;
    end if;

    v_precio_oferta := null;
    if v_oferta_activa then
      if v_modalidad = 'mesa' then
        v_precio_oferta := coalesce(
          nullif(v_prod ->> 'mesa_oferta', '')::numeric,
          nullif(v_prod ->> 'delivery_oferta', '')::numeric
        );
      else
        v_precio_oferta := coalesce(
          nullif(v_prod ->> 'delivery_oferta', '')::numeric,
          nullif(v_prod ->> 'mesa_oferta', '')::numeric
        );
      end if;
    end if;

    if v_precio_oferta is not null
       and (v_precio_oferta <= 0 or v_precio_oferta >= v_precio_regular) then
      v_precio_oferta := null;
    end if;

    v_precio_base := coalesce(v_precio_oferta, v_precio_regular);
    v_precio_unitario := round(v_precio_base + v_variacion_precio + v_precio_adicionales, 2);
    v_subtotal_item := round(v_precio_unitario * v_cantidad, 2);
    v_subtotal := v_subtotal + v_subtotal_item;

    v_items_out := v_items_out || jsonb_build_array(
      jsonb_build_object(
        'producto_id', v_producto_id,
        'nombre', coalesce(nullif(v_prod ->> 'nombre', ''), v_producto_id),
        'categoria', v_categoria,
        'variacion_id', v_variacion_id,
        'variacion_nombre', v_variacion_nombre,
        'adicionales', v_adicionales_out,
        'precio_regular', v_precio_regular,
        'precio_oferta', v_precio_oferta,
        'precio_unitario', v_precio_unitario,
        'cantidad', v_cantidad,
        'subtotal', v_subtotal_item
      )
    );
  end loop;

  v_subtotal := round(v_subtotal, 2);
  v_descuento := round(v_subtotal * v_pct / 100, 2);
  v_envio := 0;
  v_total := round(v_subtotal - v_descuento + v_envio, 2);

  insert into public.pedidos (
    sucursal_id,
    modalidad,
    estado,
    cliente_nombre,
    cliente_telefono,
    direccion,
    lat,
    lng,
    zona_envio,
    items_snapshot,
    subtotal,
    descuento,
    costo_envio,
    total,
    metodo_pago,
    idempotency_key,
    notas
  ) values (
    v_sucursal_id,
    v_modalidad,
    'pendiente',
    v_nombre,
    v_telefono,
    v_direccion,
    v_lat,
    v_lng,
    v_zona,
    v_items_out,
    v_subtotal,
    v_descuento,
    v_envio,
    v_total,
    v_pago_tipo,
    p_idempotency_key,
    v_notas
  )
  on conflict (idempotency_key) do nothing
  returning * into v_pedido;

  if v_pedido.id is null then
    select * into v_pedido
      from public.pedidos
     where idempotency_key = p_idempotency_key;
  end if;

  if v_pedido.id is null then
    raise exception 'No se pudo guardar el pedido.';
  end if;

  return jsonb_build_object(
    'id', v_pedido.id,
    'numero_orden', v_pedido.numero_orden,
    'estado', v_pedido.estado,
    'created_at', v_pedido.created_at,
    'subtotal', v_pedido.subtotal,
    'descuento', v_pedido.descuento,
    'costo_envio', v_pedido.costo_envio,
    'total', v_pedido.total,
    'pago_tipo', v_pedido.metodo_pago,
    'items', v_pedido.items_snapshot,
    'reutilizado', false
  );
end;
$$;

comment on function public.crear_pedido(
  text, text, text, text, text, numeric, numeric, text, text, jsonb, uuid
) is
  'Crea un pedido publico calculando precios de oferta, variaciones, adicionales, descuento de pago y totales en el servidor. Es idempotente por p_idempotency_key.';

revoke all on function public.crear_pedido(
  text, text, text, text, text, numeric, numeric, text, text, jsonb, uuid
) from public;

grant execute on function public.crear_pedido(
  text, text, text, text, text, numeric, numeric, text, text, jsonb, uuid
) to anon, authenticated;
