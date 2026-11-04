-- Piedra Mora - Fase 1 - Paso 1C: crear_pedido (calculo de precios en el servidor)

-- 1. Coordenadas de sucursales (el servidor las necesita para los tramos por cuadras)
insert into public.config_negocio (clave, valor)
values ('sucursales_coords', '{
  "maestro-quiroga":    {"lat": -28.4594712, "lng": -65.7846355},
  "intendente-lascano": {"lat": -28.4677229, "lng": -65.8149113}
}'::jsonb)
on conflict (clave) do nothing;

-- 2. Zonas: cual aplica tramos por distancia (por defecto "Zona normal")
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'zonas_envio' and column_name = 'aplica_tramos'
  ) then
    alter table public.zonas_envio add column aplica_tramos boolean not null default false;
    update public.zonas_envio set aplica_tramos = true where lower(nombre) = 'zona normal';
  end if;
end $$;

-- 3. Helper: texto ISO -> timestamptz (invalido o vacio = sin limite, igual que la web)
create or replace function public.pm_ts_o_null(p text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  return p::timestamptz;
exception when others then
  return null;
end;
$$;

-- 4. Calculo del pedido (no inserta nada)
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
begin
  if coalesce(p_modalidad, '') not in ('delivery', 'retiro') then
    raise exception 'Esa modalidad de entrega no está disponible.';
  end if;

  select valor into v_coords from public.config_negocio where clave = 'sucursales_coords';
  v_suc := v_coords -> p_sucursal_id;
  if v_suc is null then
    raise exception 'La sucursal no existe.';
  end if;
  -- FASE 2: aca se va a validar que la sucursal este abierta.

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
    if v_cat = 'promo' and v_oferta is not null and v_oferta > 0 and v_oferta < v_regular
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

    -- Tramos por cuadras (distancia en linea recta, redondeada hacia arriba)
    if v_zona_row.aplica_tramos and p_lat is not null and p_lng is not null
       and exists (
         select 1 from public.tramos_envio t
          where t.activa and (t.sucursal_id = p_sucursal_id or t.sucursal_id is null)
       ) then
      v_lat0 := (v_suc ->> 'lat')::numeric;
      v_lng0 := (v_suc ->> 'lng')::numeric;
      select coalesce(nullif(c.valor #>> '{}', '')::numeric, 100) into v_mpc
        from public.config_negocio c where c.clave = 'metros_por_cuadra';
      if v_mpc is null or v_mpc <= 0 then v_mpc := 100; end if;

      v_metros := 2 * 6371000 * asin(sqrt(least(1,
          power(sin(radians(p_lat - v_lat0) / 2), 2)
        + cos(radians(v_lat0)) * cos(radians(p_lat))
          * power(sin(radians(p_lng - v_lng0) / 2), 2))));
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

-- 5. Resultado que se le devuelve a la web
create or replace function public.pm_pedido_resultado(p public.pedidos)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'numero_orden', p.numero_orden,
    'estado', p.estado,
    'subtotal', p.subtotal,
    'descuento', p.descuento,
    'costo_envio', p.costo_envio,
    'total', p.total,
    'zona_envio', p.zona_envio,
    'items', p.items_snapshot);
$$;

-- 6. crear_pedido: la unica puerta publica para crear pedidos
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
  p_idempotency_key  uuid default null
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

  v_tel := regexp_replace(coalesce(p_cliente_telefono, ''), '\D', '', 'g');
  if v_tel !~ '^[0-9]{8,15}$' then
    raise exception 'El teléfono no es válido.';
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

  v_calc := public.pm_calcular_pedido(
    p_sucursal_id, p_modalidad, p_metodo_pago, p_items, p_zona_envio, v_lat, v_lng);

  begin
    insert into public.pedidos (
      sucursal_id, modalidad, cliente_nombre, cliente_telefono,
      direccion, lat, lng, zona_envio, items_snapshot,
      subtotal, descuento, costo_envio, total,
      metodo_pago, idempotency_key, notas
    ) values (
      p_sucursal_id, p_modalidad, v_nombre, v_tel,
      v_dir, v_lat, v_lng, v_calc ->> 'zona_envio', v_calc -> 'items',
      (v_calc ->> 'subtotal')::numeric, (v_calc ->> 'descuento')::numeric,
      (v_calc ->> 'costo_envio')::numeric, (v_calc ->> 'total')::numeric,
      p_metodo_pago, p_idempotency_key, nullif(v_notas, '')
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

  return public.pm_pedido_resultado(v_ped);
end;
$$;

-- 7. Permisos: solo crear_pedido es publica
revoke all on function public.pm_ts_o_null(text) from public, anon, authenticated;
revoke all on function public.pm_calcular_pedido(text, text, text, jsonb, text, numeric, numeric) from public, anon, authenticated;
revoke all on function public.pm_pedido_resultado(public.pedidos) from public, anon, authenticated;
revoke all on function public.crear_pedido(text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid) from public;
grant execute on function public.crear_pedido(text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid) to anon, authenticated;