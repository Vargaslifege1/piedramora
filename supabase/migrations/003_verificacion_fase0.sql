-- ============================================================================
-- Piedra Mora - Fase 0 - Verificacion (solo lectura)
-- ============================================================================
-- Objetivo:
--   Confirmar que la migracion de IDs y el blindaje RLS/Storage quedaron bien.
--   No modifica datos.
--
-- Cuando ejecutarlo:
--   Despues de 001 y 002. Si algo falla, el script lanza una excepcion con el
--   detalle y no continua.
-- ============================================================================

do $$
declare
  v_bad integer;
  v_detalle text;
begin
  -- --------------------------------------------------------------------------
  -- Categorias
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'categorias') cat
  where c.id = 1
    and (
      cat ->> 'id' is null
      or cat ->> 'id' !~ '^[a-z0-9]+(_[a-z0-9]+)*$'
      or cat ->> 'id' in (
        'promos', 'hamburguesas', 'pizzas', 'lomitos',
        'milanesas', 'barrolucos', 'bebidas'
      )
    );

  if v_bad > 0 then
    raise exception 'Hay % categorias con ID invalido o plural.', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select cat ->> 'id' as categoria_id, count(*) as repes
    from public.carta c,
         jsonb_array_elements(c.contenido -> 'categorias') cat
    where c.id = 1
    group by 1
    having count(*) > 1
  ) x;

  if v_bad > 0 then
    raise exception 'Hay % categorias con ID repetido.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Productos: ID snake_case y prefijo de categoria
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'productos') p
  where c.id = 1
    and (
      p ->> 'id' is null
      or p ->> 'categoria' is null
      or p ->> 'id' !~ '^[a-z0-9]+(_[a-z0-9]+)*$'
      or not starts_with(p ->> 'id', (p ->> 'categoria') || '_')
    );

  if v_bad > 0 then
    raise exception 'Hay % productos con ID invalido o sin prefijo de categoria.', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select p ->> 'id' as producto_id, count(*) as repes
    from public.carta c,
         jsonb_array_elements(c.contenido -> 'productos') p
    where c.id = 1
    group by 1
    having count(*) > 1
  ) x;

  if v_bad > 0 then
    raise exception 'Hay % productos con ID repetido.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Productos: categoria existente
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'productos') p
  where c.id = 1
    and not exists (
      select 1
      from jsonb_array_elements(c.contenido -> 'categorias') cat
      where cat ->> 'id' = p ->> 'categoria'
    );

  if v_bad > 0 then
    raise exception 'Hay % productos apuntando a una categoria inexistente.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Variaciones: ID unico y con prefijo del producto
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'productos') p,
       jsonb_array_elements(coalesce(p -> 'variaciones' -> 'opciones', '[]'::jsonb)) o
  where c.id = 1
    and (
      o ->> 'id' is null
      or p ->> 'id' is null
      or o ->> 'id' !~ '^[a-z0-9]+(_[a-z0-9]+)*$'
      or not starts_with(o ->> 'id', (p ->> 'id') || '_')
    );

  if v_bad > 0 then
    raise exception 'Hay % variaciones con ID invalido o sin prefijo del producto.', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select p ->> 'id' as producto_id, o ->> 'id' as opcion_id, count(*) as repes
    from public.carta c,
         jsonb_array_elements(c.contenido -> 'productos') p,
         jsonb_array_elements(coalesce(p -> 'variaciones' -> 'opciones', '[]'::jsonb)) o
    where c.id = 1
    group by 1, 2
    having count(*) > 1
  ) x;

  if v_bad > 0 then
    raise exception 'Hay % variaciones repetidas dentro de un mismo producto.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Adicionales: ID unico y con prefijo del producto
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'productos') p,
       jsonb_array_elements(coalesce(p -> 'adicionales', '[]'::jsonb)) a
  where c.id = 1
    and (
      a ->> 'id' is null
      or p ->> 'id' is null
      or a ->> 'id' !~ '^[a-z0-9]+(_[a-z0-9]+)*$'
      or not starts_with(a ->> 'id', (p ->> 'id') || '_')
    );

  if v_bad > 0 then
    raise exception 'Hay % adicionales con ID invalido o sin prefijo del producto.', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select p ->> 'id' as producto_id, a ->> 'id' as adicional_id, count(*) as repes
    from public.carta c,
         jsonb_array_elements(c.contenido -> 'productos') p,
         jsonb_array_elements(coalesce(p -> 'adicionales', '[]'::jsonb)) a
    where c.id = 1
    group by 1, 2
    having count(*) > 1
  ) x;

  if v_bad > 0 then
    raise exception 'Hay % adicionales repetidos dentro de un mismo producto.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Campos de agotado
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from public.carta c,
       jsonb_array_elements(c.contenido -> 'productos') p
  where c.id = 1
    and (
      coalesce(jsonb_typeof(p -> 'agotado'), 'missing') <> 'boolean'
      or coalesce(jsonb_typeof(p -> 'agotado_hasta_nuevo_aviso'), 'missing') <> 'boolean'
      or coalesce(jsonb_typeof(p -> 'agotado_fecha'), 'missing') not in ('string', 'null')
      or (
        jsonb_typeof(p -> 'agotado_fecha') = 'string'
        and (p ->> 'agotado_fecha') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      )
    );

  if v_bad > 0 then
    raise exception 'Hay % productos con campos de agotado invalidos.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Funcion es_admin()
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'es_admin'
    and p.prosecdef;

  if v_bad <> 1 then
    raise exception 'No existe public.es_admin() o no es security definer.';
  end if;

  -- --------------------------------------------------------------------------
  -- admins: sin politica de lectura
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from pg_policies
  where schemaname = 'public'
    and tablename = 'admins'
    and cmd = 'SELECT';

  if v_bad > 0 then
    select string_agg(policyname, ', ') into v_detalle
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admins'
      and cmd = 'SELECT';

    raise exception 'public.admins todavia tiene politicas de lectura: %.', v_detalle;
  end if;

  -- --------------------------------------------------------------------------
  -- carta: lectura publica y escritura admin
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from pg_policies
  where schemaname = 'public'
    and tablename = 'carta'
    and policyname = 'Carta lectura publica'
    and 'anon' = any(roles::text[]);

  if v_bad <> 1 then
    raise exception 'Falta la politica de lectura publica de public.carta.';
  end if;

  select count(*) into v_bad
  from pg_policies
  where schemaname = 'public'
    and tablename = 'carta'
    and policyname in ('Carta alta admin', 'Carta edicion admin', 'Carta baja admin')
    and 'authenticated' = any(roles::text[]);

  if v_bad <> 3 then
    raise exception 'Faltan politicas de escritura admin en public.carta. Encontradas: %.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Storage
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from storage.buckets
  where id = 'carta-imagenes'
    and public = true;

  if v_bad <> 1 then
    raise exception 'El bucket carta-imagenes no existe o no es publico.';
  end if;

  select count(*) into v_bad
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname in (
      'Imagenes lectura publica',
      'Imagenes alta admin',
      'Imagenes edicion admin',
      'Imagenes baja admin'
    );

  if v_bad <> 4 then
    raise exception 'Faltan politicas de Storage para carta-imagenes. Encontradas: %.', v_bad;
  end if;

  -- --------------------------------------------------------------------------
  -- Extras
  -- --------------------------------------------------------------------------
  select count(*) into v_bad
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'admins'
    and indexname = 'admins_email_lower_uidx';

  if v_bad <> 1 then
    raise exception 'Falta el indice unico admins_email_lower_uidx.';
  end if;

  select count(*) into v_bad
  from pg_trigger
  where tgname = 'carta_touch_updated_at'
    and tgrelid = 'public.carta'::regclass
    and not tgisinternal;

  if v_bad <> 1 then
    raise exception 'Falta el trigger carta_touch_updated_at.';
  end if;

  select count(*) into v_bad
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename = 'carta';

  if v_bad = 0 then
    raise notice 'Aviso: public.carta no esta en la publicacion supabase_realtime.';
  end if;

  raise notice 'Verificacion Fase 0 OK.';
end $$;

-- Resumen legible.
select
  (select count(*)
     from public.carta c,
          jsonb_array_elements(c.contenido -> 'categorias')
    where c.id = 1) as categorias,
  (select count(*)
     from public.carta c,
          jsonb_array_elements(c.contenido -> 'productos')
    where c.id = 1) as productos,
  (select count(*)
     from public.carta c,
          jsonb_array_elements(c.contenido -> 'productos') p,
          jsonb_array_elements(coalesce(p -> 'variaciones' -> 'opciones', '[]'::jsonb))
    where c.id = 1) as variaciones,
  (select count(*)
     from public.carta c,
          jsonb_array_elements(c.contenido -> 'productos') p,
          jsonb_array_elements(coalesce(p -> 'adicionales', '[]'::jsonb))
    where c.id = 1) as adicionales,
  (select count(*)
     from public.carta c,
          jsonb_array_elements(c.contenido -> 'productos') p
    where c.id = 1
      and p ->> 'agotado' = 'true') as agotados;
