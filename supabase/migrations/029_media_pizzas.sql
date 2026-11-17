-- ============================================================================
-- 029_media_pizzas.sql
-- Agrega 13 medias pizzas como productos propios en la carta (public.carta id=1).
-- ============================================================================
-- ANTES DE APLICAR:
--   - Hacer backup de la base.
--   - Aplicar SIN nadie editando la carta en el admin.
--   - Despues de aplicar, RECARGAR el admin (F5) en todas las sesiones abiertas:
--     un admin abierto con la carta vieja en memoria pisaria las medias al guardar.
--
-- Que hace:
--   - Por cada media crea un producto "1/2 <NOMBRE>" con id pizza_media_<x>,
--     categoria 'pizza', sin oferta (cuenta como producto normal para cupones, 027).
--   - sucursales, foto y descripcion se COPIAN de la pizza entera que esta en la
--     base (la descripcion lleva el prefijo "Media pizza. "). No se inventa nada.
--   - Precio: delivery segun lista del dueno. PRECIO MESA PROVISORIO = mismo valor
--     que delivery (el dueno pasara los valores reales mas adelante).
--   - Se insertan despues de la ultima pizza de la carta (antes de las bebidas),
--     en el orden de la lista.
--   - Agotado por sucursal: usa agotados_sucursal (017) por producto_id, sin cambios.
--
-- Idempotente: si un id pizza_media_<x> ya existe, se saltea (no se duplica ni se
-- pisa). Si falta alguna pizza entera, aborta con error y no cambia nada.
-- No toca crear_pedido ni pm_calcular_pedido.
-- ============================================================================

do $$
declare
  v_contenido jsonb;
  v_prods     jsonb;
  v_nuevo     jsonb := '[]'::jsonb;
  v_res       jsonb := '[]'::jsonb;
  v_ult       integer := -1;
  v_i         integer;
  v_agregadas integer := 0;
  v_ent       jsonb;
  v_id        text;
  -- (id de la entera, precio delivery de la media), en el orden pedido
  v_lista constant jsonb := '[
    {"entera": "pizza_muzzarella",       "precio": 7000},
    {"entera": "pizza_especial",         "precio": 8500},
    {"entera": "pizza_napolitana",       "precio": 8500},
    {"entera": "pizza_fugazzeta",        "precio": 8500},
    {"entera": "pizza_fugazzeta_provolone", "precio": 9500},
    {"entera": "pizza_calabresa",        "precio": 10000},
    {"entera": "pizza_rucula",           "precio": 11500},
    {"entera": "pizza_palmito_golf",     "precio": 11500},
    {"entera": "pizza_roquefort",        "precio": 9500},
    {"entera": "pizza_tropical",         "precio": 11500},
    {"entera": "pizza_argentina",        "precio": 10500},
    {"entera": "pizza_ternera",          "precio": 11500},
    {"entera": "pizza_pollo",            "precio": 9000}
  ]'::jsonb;
  v_item jsonb;
begin
  select contenido into v_contenido from public.carta where id = 1 for update;

  if v_contenido is null then
    raise exception 'No existe la fila id=1 en public.carta.';
  end if;
  v_prods := v_contenido -> 'productos';
  if jsonb_typeof(v_prods) <> 'array' then
    raise exception 'La carta no tiene el array "productos".';
  end if;

  -- Posicion de la ultima pizza (cualquier pizza, incluidas medias ya cargadas).
  for v_i in 0 .. jsonb_array_length(v_prods) - 1 loop
    if v_prods -> v_i ->> 'categoria' = 'pizza' then
      v_ult := v_i;
    end if;
  end loop;
  if v_ult < 0 then
    raise exception 'No hay pizzas en la carta.';
  end if;

  -- Armar las medias que faltan.
  for v_item in select value from jsonb_array_elements(v_lista) loop
    v_id := replace(v_item ->> 'entera', 'pizza_', 'pizza_media_');

    if exists (select 1 from jsonb_array_elements(v_prods) e(value) where e.value ->> 'id' = v_id) then
      continue;  -- ya existe: idempotente
    end if;

    select e.value into v_ent
      from jsonb_array_elements(v_prods) e(value)
     where e.value ->> 'id' = v_item ->> 'entera';
    if v_ent is null then
      raise exception 'Falta la pizza entera "%": no se puede crear su media.', v_item ->> 'entera';
    end if;

    v_nuevo := v_nuevo || jsonb_build_array(jsonb_build_object(
      'id', v_id,
      'categoria', 'pizza',
      'nombre', '1/2 ' || (v_ent ->> 'nombre'),
      'descripcion', 'Media pizza. ' || coalesce(v_ent ->> 'descripcion', ''),
      'foto', v_ent -> 'foto',
      'sucursales', v_ent -> 'sucursales',
      'precios', jsonb_build_object(
        'delivery', (v_item ->> 'precio')::integer,
        'mesa',     (v_item ->> 'precio')::integer   -- PROVISORIO: igual a delivery
      ),
      'agotado', false,
      'agotado_fecha', null,
      'agotado_hasta_nuevo_aviso', false
    ));
    v_agregadas := v_agregadas + 1;
  end loop;

  if v_agregadas = 0 then
    raise notice 'Las 13 medias ya estaban cargadas. Nada para hacer.';
    return;
  end if;

  -- Reconstruir el array: las nuevas van justo despues de la ultima pizza.
  for v_i in 0 .. jsonb_array_length(v_prods) - 1 loop
    v_res := v_res || jsonb_build_array(v_prods -> v_i);
    if v_i = v_ult then
      v_res := v_res || v_nuevo;
    end if;
  end loop;

  update public.carta
     set contenido = jsonb_set(v_contenido, '{productos}', v_res, true),
         updated_at = now()
   where id = 1;

  raise notice 'Medias pizzas agregadas: %.', v_agregadas;
end $$;

-- ----------------------------------------------------------------------------
-- VERIFICACION (solo lectura; correr a mano despues de aplicar)
-- ----------------------------------------------------------------------------
-- 1) Deben salir 13 filas, con las mismas sucursales que su entera:
--   select e.value ->> 'id' as id, e.value ->> 'nombre' as nombre,
--          e.value -> 'precios' as precios, e.value -> 'sucursales' as sucursales
--     from public.carta c, jsonb_array_elements(c.contenido -> 'productos') e(value)
--    where c.id = 1 and e.value ->> 'id' like 'pizza_media_%';
--
-- 2) Precio server-side de una media (delivery $7.000 -> subtotal 7000 x cantidad):
--   usar pm_calcular_pedido / valida_cupon con items
--   [{"producto_id":"pizza_media_muzzarella","cantidad":2}] y verificar subtotal 14000;
--   con cupon PIEDRAMORA debe descontar 20% (2800), porque no es promo.
--
-- 3) Agotada por sucursal (no cambia nada de esquema):
--   insert into public.agotados_sucursal (producto_id, sucursal_id)
--   values ('pizza_media_muzzarella', 'maestro-quiroga') on conflict do nothing;
--   -> crear_pedido en maestro-quiroga debe rechazarla y en intendente-lascano no.
--   (borrar la fila despues de probar)
