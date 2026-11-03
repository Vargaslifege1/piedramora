-- ============================================================================
-- Piedra Mora - Fase 0 - IDs estables y control de agotado
-- ============================================================================
-- Objetivo:
--   1. Pasar las categorias a singular:
--        promos -> promo, hamburguesas -> burger, pizzas -> pizza,
--        lomitos -> lomo, milanesas -> milanesa, barrolucos -> barroluco,
--        bebidas -> bebida.
--   2. Normalizar IDs de productos a snake_case con prefijo de categoria:
--        cheeseburger -> burger_cheeseburger
--        blue_bacon   -> burger_blue_bacon
--   3. Hacer unicos los IDs de variaciones y adicionales dentro de su producto:
--        simple -> burger_cheeseburger_simple
--        extra_queso -> burger_cheeseburger_extra_queso
--   4. Agregar los campos de agotado:
--        agotado (boolean)
--        agotado_fecha (YYYY-MM-DD en America/Argentina/Buenos_Aires)
--        agotado_hasta_nuevo_aviso (boolean)
--
-- Requisitos previos:
--   - Haber ejecutado 000_backup_carta.sql y 001_seguridad_rls_storage.sql.
--   - La carta debe tener al menos la fila id=1.
--
-- Idempotente:
--   Se puede ejecutar varias veces. Si un ID ya esta normalizado, se conserva.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper de slug
-- ----------------------------------------------------------------------------
create or replace function public.pm_slugify(p_texto text)
returns text
language sql
immutable
as $$
  select trim(both '_' from regexp_replace(
    regexp_replace(
      lower(translate(coalesce(p_texto, ''), 'áéíóúüñçÁÉÍÓÚÜÑÇ', 'aeiouuncAEIOUUNC')),
      '[^a-z0-9]+',
      '_',
      'g'
    ),
    '_+',
    '_',
    'g'
  ));
$$;

revoke all on function public.pm_slugify(text) from public;

comment on function public.pm_slugify(text) is
  'Normaliza texto a snake_case ASCII para IDs estables.';

-- ----------------------------------------------------------------------------
-- Migracion de la fila id=1
-- ----------------------------------------------------------------------------
do $$
declare
  v_contenido jsonb;
  v_row_id integer;
  v_cats jsonb := '[]'::jsonb;
  v_prods jsonb := '[]'::jsonb;
  v_cat jsonb;
  v_prod jsonb;
  v_prod_new jsonb;
  v_old text;
  v_new text;
  v_base text;
  v_i integer;
  v_prefix text;
  v_cat_new text;
  v_old_id text;
  v_new_id text;
  v_op jsonb;
  v_op_old text;
  v_op_new text;
  v_ops jsonb;
  v_tiene_ops boolean;
  v_add jsonb;
  v_add_old text;
  v_add_new text;
  v_adds jsonb;
  v_tiene_adds boolean;
  v_seen text[];
  v_agotado boolean;
  v_agotado_fecha text;
  v_permanente boolean;
  v_map_categorias jsonb := '{
    "promos": "promo",
    "hamburguesas": "burger",
    "pizzas": "pizza",
    "lomitos": "lomo",
    "milanesas": "milanesa",
    "barrolucos": "barroluco",
    "bebidas": "bebida"
  }'::jsonb;
begin
  select id, contenido
    into v_row_id, v_contenido
    from public.carta
   where id = 1;

  if v_row_id is null then
    raise exception 'No existe la fila id=1 en public.carta. Restaura el respaldo antes de migrar.';
  end if;

  if jsonb_typeof(v_contenido -> 'categorias') <> 'array'
     or jsonb_typeof(v_contenido -> 'productos') <> 'array' then
    raise exception 'La carta no tiene los arrays "categorias" y "productos" como corresponde.';
  end if;

  -- --------------------------------------------------------------------------
  -- Categorias
  -- --------------------------------------------------------------------------
  drop table if exists pg_temp.tmp_pm_cat_map_fase0;
  create temporary table tmp_pm_cat_map_fase0 (
    old_id text primary key,
    new_id text not null
  ) on commit drop;

  for v_cat in
    select value from jsonb_array_elements(v_contenido -> 'categorias')
  loop
    v_old := coalesce(v_cat ->> 'id', '');
    v_new := v_map_categorias ->> v_old;

    if v_new is null then
      if v_old ~ '^[a-z0-9]+(_[a-z0-9]+)*$' then
        v_new := v_old;
      else
        v_new := public.pm_slugify(coalesce(v_cat ->> 'nombre', v_old));
      end if;
    end if;

    if v_new is null or v_new = '' then
      v_new := 'categoria';
    end if;

    v_base := v_new;
    v_i := 2;
    while exists (
      select 1 from tmp_pm_cat_map_fase0 where new_id = v_new
    ) loop
      v_new := v_base || '_' || v_i;
      v_i := v_i + 1;
    end loop;

    insert into tmp_pm_cat_map_fase0 (old_id, new_id)
    values (v_old, v_new)
    on conflict (old_id) do nothing;

    v_cats := v_cats || jsonb_build_array(
      jsonb_set(v_cat, '{id}', to_jsonb(v_new), true)
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- Productos, variaciones y adicionales
  -- --------------------------------------------------------------------------
  drop table if exists pg_temp.tmp_pm_prod_ids_fase0;
  create temporary table tmp_pm_prod_ids_fase0 (
    new_id text primary key
  ) on commit drop;

  for v_prod in
    select value from jsonb_array_elements(v_contenido -> 'productos')
  loop
    v_old_id := coalesce(v_prod ->> 'id', '');

    v_cat_new := (
      select new_id
      from tmp_pm_cat_map_fase0
      where old_id = coalesce(v_prod ->> 'categoria', '')
    );

    if v_cat_new is null then
      v_cat_new := public.pm_slugify(coalesce(v_prod ->> 'categoria', ''));
      if v_cat_new = '' then
        v_cat_new := 'sin_categoria';
      end if;
    end if;

    v_prefix := v_cat_new;

    if v_old_id = '' then
      v_new_id := v_prefix || '_' || coalesce(
        nullif(public.pm_slugify(coalesce(v_prod ->> 'nombre', 'producto')), ''),
        'producto'
      );
    elsif v_old_id ~ '^[a-z0-9]+(_[a-z0-9]+)*$'
          and starts_with(v_old_id, v_prefix || '_') then
      v_new_id := v_old_id;
    else
      v_new_id := v_prefix || '_' || public.pm_slugify(v_old_id);
    end if;

    if v_new_id = v_prefix || '_' or v_new_id = '' then
      v_new_id := v_prefix || '_' || coalesce(
        nullif(public.pm_slugify(coalesce(v_prod ->> 'nombre', 'producto')), ''),
        'producto'
      );
    end if;

    v_base := v_new_id;
    v_i := 2;
    while exists (
      select 1 from tmp_pm_prod_ids_fase0 where new_id = v_new_id
    ) loop
      v_new_id := v_base || '_' || v_i;
      v_i := v_i + 1;
    end loop;

    insert into tmp_pm_prod_ids_fase0 (new_id) values (v_new_id);

    v_prod_new := jsonb_set(v_prod, '{id}', to_jsonb(v_new_id), true);
    v_prod_new := jsonb_set(v_prod_new, '{categoria}', to_jsonb(v_cat_new), true);

    -- Variaciones: IDs unicos dentro del producto.
    v_tiene_ops := (
      jsonb_exists(v_prod, 'variaciones')
      and jsonb_typeof(v_prod -> 'variaciones') = 'object'
      and jsonb_exists(v_prod -> 'variaciones', 'opciones')
      and jsonb_typeof(v_prod -> 'variaciones' -> 'opciones') = 'array'
    );

    if v_tiene_ops then
      v_ops := '[]'::jsonb;
      v_seen := '{}';

      for v_op in
        select value from jsonb_array_elements(v_prod -> 'variaciones' -> 'opciones')
      loop
        v_op_old := coalesce(
          v_op ->> 'id',
          public.pm_slugify(coalesce(v_op ->> 'nombre', 'opcion'))
        );

        if v_op_old ~ '^[a-z0-9]+(_[a-z0-9]+)*$'
           and starts_with(v_op_old, v_new_id || '_') then
          v_op_new := v_op_old;
        else
          v_op_new := v_new_id || '_' || public.pm_slugify(v_op_old);
        end if;

        if v_op_new = v_new_id || '_' then
          v_op_new := v_new_id || '_' || coalesce(
            nullif(public.pm_slugify(coalesce(v_op ->> 'nombre', 'opcion')), ''),
            'opcion'
          );
        end if;

        v_base := v_op_new;
        v_i := 2;
        while v_op_new = any(v_seen) loop
          v_op_new := v_base || '_' || v_i;
          v_i := v_i + 1;
        end loop;

        v_seen := v_seen || v_op_new;
        v_ops := v_ops || jsonb_build_array(
          jsonb_set(v_op, '{id}', to_jsonb(v_op_new), true)
        );
      end loop;

      v_prod_new := jsonb_set(v_prod_new, '{variaciones,opciones}', v_ops, true);
    end if;

    -- Adicionales: IDs unicos dentro del producto.
    v_tiene_adds := (
      jsonb_exists(v_prod, 'adicionales')
      and jsonb_typeof(v_prod -> 'adicionales') = 'array'
    );

    if v_tiene_adds then
      v_adds := '[]'::jsonb;
      v_seen := '{}';

      for v_add in
        select value from jsonb_array_elements(v_prod -> 'adicionales')
      loop
        v_add_old := coalesce(
          v_add ->> 'id',
          public.pm_slugify(coalesce(v_add ->> 'nombre', 'adicional'))
        );

        if v_add_old ~ '^[a-z0-9]+(_[a-z0-9]+)*$'
           and starts_with(v_add_old, v_new_id || '_') then
          v_add_new := v_add_old;
        else
          v_add_new := v_new_id || '_' || public.pm_slugify(v_add_old);
        end if;

        if v_add_new = v_new_id || '_' then
          v_add_new := v_new_id || '_' || coalesce(
            nullif(public.pm_slugify(coalesce(v_add ->> 'nombre', 'adicional')), ''),
            'adicional'
          );
        end if;

        v_base := v_add_new;
        v_i := 2;
        while v_add_new = any(v_seen) loop
          v_add_new := v_base || '_' || v_i;
          v_i := v_i + 1;
        end loop;

        v_seen := v_seen || v_add_new;
        v_adds := v_adds || jsonb_build_array(
          jsonb_set(v_add, '{id}', to_jsonb(v_add_new), true)
        );
      end loop;

      v_prod_new := jsonb_set(v_prod_new, '{adicionales}', v_adds, true);
    end if;

    -- Agotado: se conserva lo existente y se completa lo que falte.
    v_agotado := case
      when jsonb_typeof(v_prod -> 'agotado') = 'boolean'
        then (v_prod ->> 'agotado')::boolean
      else false
    end;

    v_permanente := case
      when jsonb_typeof(v_prod -> 'agotado_hasta_nuevo_aviso') = 'boolean'
        then (v_prod ->> 'agotado_hasta_nuevo_aviso')::boolean
      else false
    end;

    v_agotado_fecha := case
      when jsonb_typeof(v_prod -> 'agotado_fecha') = 'string'
        then nullif(v_prod ->> 'agotado_fecha', '')
      else null
    end;

    if v_agotado and v_agotado_fecha is null then
      v_agotado_fecha := to_char(
        now() at time zone 'America/Argentina/Buenos_Aires',
        'YYYY-MM-DD'
      );
    end if;

    if not v_agotado then
      v_agotado_fecha := null;
      v_permanente := false;
    end if;

    -- Si el agotado era solo por el dia y la fecha guardada no es la de hoy,
    -- se libera automaticamente al aplicar la migracion.
    if v_agotado
       and not v_permanente
       and v_agotado_fecha is distinct from to_char(
         now() at time zone 'America/Argentina/Buenos_Aires',
         'YYYY-MM-DD'
       ) then
      v_agotado := false;
      v_agotado_fecha := null;
    end if;

    v_prod_new := jsonb_set(
      v_prod_new,
      '{agotado}',
      to_jsonb(v_agotado),
      true
    );
    v_prod_new := jsonb_set(
      v_prod_new,
      '{agotado_fecha}',
      coalesce(to_jsonb(v_agotado_fecha), 'null'::jsonb),
      true
    );
    v_prod_new := jsonb_set(
      v_prod_new,
      '{agotado_hasta_nuevo_aviso}',
      to_jsonb(v_permanente),
      true
    );

    v_prods := v_prods || jsonb_build_array(v_prod_new);
  end loop;

  -- --------------------------------------------------------------------------
  -- Guardar
  -- --------------------------------------------------------------------------
  v_contenido := jsonb_set(v_contenido, '{categorias}', v_cats, true);
  v_contenido := jsonb_set(v_contenido, '{productos}', v_prods, true);

  update public.carta
     set contenido = v_contenido,
         updated_at = now()
   where id = 1;

  raise notice 'Carta migrada: % categorias y % productos.',
    jsonb_array_length(v_cats),
    jsonb_array_length(v_prods);
end $$;

