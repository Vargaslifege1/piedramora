-- ============================================================================
-- Piedra Mora - Fase 1 - Paso 1B: limpieza de ofertas fuera de la categoria promo
-- ============================================================================
-- IMPORTANTE: ESTE SCRIPT YA FUE EJECUTADO A MANO POR EL USUARIO.
-- Queda solo como registro reproducible de lo que se hizo. No hace falta
-- ejecutarlo de nuevo, y desde el proyecto no se ejecuta contra la base.
--
-- Que hace:
--   1. Asegura la tabla de respaldo backups.carta_antes_ofertas.
--   2. Guarda una copia de la carta actual (id = 1) antes de limpiar.
--   3. Quita de los productos que NO son de la categoria "promo" cualquier
--      campo cuyo nombre contenga "oferta" (sin distinguir mayusculas).
--      Esto incluye delivery_oferta, mesa_oferta, tipoOferta, etc.
--   4. Los productos de la categoria "promo" quedan intactos.
--
-- Idempotente:
--   - Si ya no hay campos de oferta fuera de "promo", no respalda ni modifica
--     nada y solo muestra un aviso.
--   - El respaldo usa "on conflict (id) do nothing", por lo que conserva el
--     primero guardado y no lo pisa.
-- ============================================================================

create schema if not exists backups;

create table if not exists backups.carta_antes_ofertas (
  id integer primary key,
  contenido jsonb not null,
  respaldado_at timestamptz not null default now()
);

-- La tabla de respaldo no debe ser accesible desde el frontend.
revoke all on schema backups from anon, authenticated;
alter table backups.carta_antes_ofertas enable row level security;
revoke all on backups.carta_antes_ofertas from anon, authenticated;

do $$
declare
  v_contenido jsonb;
  v_productos jsonb;
  v_pendientes integer;
begin
  select contenido
    into v_contenido
    from public.carta
   where id = 1;

  if v_contenido is null then
    raise notice 'No existe la fila id=1 en public.carta. No se limpio nada.';
    return;
  end if;

  if jsonb_typeof(v_contenido -> 'productos') <> 'array' then
    raise notice 'La carta no tiene el array "productos". No se limpio nada.';
    return;
  end if;

  -- Productos fuera de "promo" que todavia tienen algun campo con "oferta".
  select count(*)
    into v_pendientes
    from jsonb_array_elements(v_contenido -> 'productos') as prod
   where coalesce(prod ->> 'categoria', '') <> 'promo'
     and exists (
       select 1
         from jsonb_object_keys(prod) as campo
        where campo ~* 'oferta'
     );

  if v_pendientes = 0 then
    raise notice 'No hay campos de oferta fuera de la categoria promo. Nada para limpiar.';
    return;
  end if;

  -- Respaldo previo (conserva el primero si ya existe).
  insert into backups.carta_antes_ofertas (id, contenido)
  values (1, v_contenido)
  on conflict (id) do nothing;

  -- Reconstruye cada producto: los de "promo" quedan igual; al resto se les
  -- quitan las claves cuyo nombre contenga "oferta".
  select jsonb_agg(
           case
             when coalesce(prod ->> 'categoria', '') = 'promo' then prod
             else (
               select coalesce(jsonb_object_agg(campo.key, campo.value), '{}'::jsonb)
                 from jsonb_each(prod) as campo
                where campo.key !~* 'oferta'
             )
           end
           order by orden
         )
    into v_productos
    from jsonb_array_elements(v_contenido -> 'productos')
         with ordinality as t(prod, orden);

  update public.carta
     set contenido = jsonb_set(v_contenido, '{productos}', v_productos, true),
         updated_at = now()
   where id = 1;

  raise notice 'Limpieza de ofertas aplicada a % productos fuera de promo.', v_pendientes;
end $$;
