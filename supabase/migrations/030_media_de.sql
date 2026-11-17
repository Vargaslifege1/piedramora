-- ============================================================================
-- 030_media_de.sql
-- Vincula cada media pizza (029) con su pizza entera mediante el campo
-- "media_de": "pizza_<x>" en public.carta id=1.
-- ============================================================================
-- ANTES DE APLICAR:
--   - Hacer backup de la base.
--   - Aplicar SIN nadie editando la carta en el admin.
--   - Despues de aplicar, RECARGAR el admin (F5) en todas las sesiones abiertas:
--     un admin abierto con la carta vieja en memoria pisaria el campo al guardar.
--   - Aplicar ANTES (o a la vez) de publicar el main.js nuevo: sin "media_de" el
--     sitio nuevo mostraria las medias como tarjetas sueltas.
--
-- Que hace:
--   - Por cada pizza_media_<x> agrega "media_de": "pizza_<x>" (id de su entera).
--   - No cambia nada mas: categoria, precios, sucursales y agotado quedan igual.
--   - Falla con error claro (y no cambia nada) si falta alguna media o su entera.
--   - Idempotente: si "media_de" ya tiene el valor correcto, no hace nada.
--   - No toca crear_pedido, pm_calcular_pedido ni valida_cupon.
-- ============================================================================

do $$
declare
  v_contenido jsonb;
  v_prods     jsonb;
  v_res       jsonb := '[]'::jsonb;
  v_prod      jsonb;
  v_entera    text;
  v_i         integer;
  v_cambios   integer := 0;
  v_enteras   constant text[] := array[
    'pizza_muzzarella', 'pizza_especial', 'pizza_napolitana', 'pizza_fugazzeta',
    'pizza_fugazzeta_provolone', 'pizza_calabresa', 'pizza_rucula',
    'pizza_palmito_golf', 'pizza_roquefort', 'pizza_tropical',
    'pizza_argentina', 'pizza_ternera', 'pizza_pollo'
  ];
  v_e         text;
  v_media     text;
begin
  select contenido into v_contenido from public.carta where id = 1 for update;

  if v_contenido is null then
    raise exception 'No existe la fila id=1 en public.carta.';
  end if;
  v_prods := v_contenido -> 'productos';
  if jsonb_typeof(v_prods) <> 'array' then
    raise exception 'La carta no tiene el array "productos".';
  end if;

  -- Validar que existan las 13 medias y sus 13 enteras.
  foreach v_e in array v_enteras loop
    v_media := replace(v_e, 'pizza_', 'pizza_media_');

    if not exists (select 1 from jsonb_array_elements(v_prods) p(value) where p.value ->> 'id' = v_media) then
      raise exception 'Falta la media "%" en la carta (aplicar antes la 029).', v_media;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_prods) p(value) where p.value ->> 'id' = v_e) then
      raise exception 'Falta la pizza entera "%" (la media "%" quedaria huerfana).', v_e, v_media;
    end if;
  end loop;

  -- Reconstruir el array agregando media_de a cada media.
  for v_i in 0 .. jsonb_array_length(v_prods) - 1 loop
    v_prod := v_prods -> v_i;

    if (v_prod ->> 'id') = any (
      array(select replace(x, 'pizza_', 'pizza_media_') from unnest(v_enteras) x)
    ) then
      v_entera := replace(v_prod ->> 'id', 'pizza_media_', 'pizza_');
      if (v_prod ->> 'media_de') is distinct from v_entera then
        v_prod := jsonb_set(v_prod, '{media_de}', to_jsonb(v_entera), true);
        v_cambios := v_cambios + 1;
      end if;
    end if;

    v_res := v_res || jsonb_build_array(v_prod);
  end loop;

  if v_cambios = 0 then
    raise notice 'Las 13 medias ya tenian media_de. Nada para hacer.';
    return;
  end if;

  update public.carta
     set contenido = jsonb_set(v_contenido, '{productos}', v_res, true),
         updated_at = now()
   where id = 1;

  raise notice 'media_de agregado a % medias.', v_cambios;
end $$;

-- ----------------------------------------------------------------------------
-- VERIFICACION (solo lectura; correr a mano despues de aplicar)
-- ----------------------------------------------------------------------------
-- Deben salir 13 filas, con media_de = id de la entera correspondiente:
--   select e.value ->> 'id' as id, e.value ->> 'media_de' as media_de
--     from public.carta c, jsonb_array_elements(c.contenido -> 'productos') e(value)
--    where c.id = 1 and e.value ->> 'id' like 'pizza_media_%';
