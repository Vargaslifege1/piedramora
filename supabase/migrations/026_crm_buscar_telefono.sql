-- ============================================================================
-- 026_crm_buscar_telefono.sql
-- Buscador del CRM: encuentra clientes por telefono aunque se escriba con
-- espacios, guiones, parentesis o prefijo (+54 9).
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP de la base (Supabase > Database > Backups).
-- Esta migracion solo REEMPLAZA crm_clientes (misma firma de 6 parametros, mismo
-- retorno, mismos grants). No toca tablas, datos ni otras funciones.
--
-- Prerrequisitos (ya aplicadas): 022 (crm_clientes, pm_crm_umbrales,
-- pm_crm_segmento), 023 (telefonos guardados con 10 digitos).
-- NO se modifica ninguna migracion anterior.
--
-- Que cambia (unico cambio respecto de 022, marcado con "-- 026"):
--   Si el texto buscado esta formado solo por digitos y separadores
--   (espacio, + - . ( )), ademas del ilike de siempre se compara por digitos
--   contra clientes.telefono. Casos: "383 481" -> 3834818271; "383-481-8271";
--   "(383) 4818271"; "+54 9 383 481 8271" y "03834818271" (se quitan 54/549 y
--   el 0 inicial con 8+ digitos). Buscar por nombre/apellido no cambia, y un
--   texto con letras no busca por telefono.
-- crm_exportar y crm_inactivos_promos no buscan por texto: no cambian.
--
-- Idempotente: create or replace + revoke/grant repetidos.
-- ============================================================================

begin;

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
  v_dig text;                                                -- 026: buscador por telefono
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

  -- 026: si lo escrito parece un telefono (solo digitos, espacios, + - . ( )) se
  -- busca por digitos: "383 481", "(383) 481-8271" o "+54 9 383 481 8271" encuentran
  -- 3834818271 (los telefonos se guardan con 10 digitos, desde 023). Se quita el
  -- prefijo 54/549 y el 0 inicial solo cuando hay 8+ digitos (para no recortar
  -- busquedas parciales cortas). Si no parece telefono, no se busca por telefono
  -- ("juan 2" no devuelve a todos los que tengan un 2).
  if v_buscar is not null and v_buscar ~ '^[0-9 ()+.-]+$' then
    v_dig := regexp_replace(v_buscar, '[^0-9]', '', 'g');
    if char_length(v_dig) >= 8 then
      v_dig := regexp_replace(v_dig, '^(549|54)', '');
      v_dig := regexp_replace(v_dig, '^0', '');
    end if;
    if v_dig = '' then
      v_dig := null;
    end if;
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
        or (v_dig is not null and c.telefono like '%' || v_dig || '%')   -- 026
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
  'Listado paginado de clientes con segmento para el dueno. Busca por nombre/apellido o telefono (con o sin separadores). Solo lectura.';

revoke all on function public.crm_clientes(text, text, text, text, integer, integer) from public, anon;
grant execute on function public.crm_clientes(text, text, text, text, integer, integer) to authenticated;

commit;

-- ============================================================================
-- CASOS DE PRUEBA (ejecutar logueado como DUENO; esperado entre parentesis).
-- Suponer un cliente con telefono 3834818271 y nombre "Juan Perez".
-- ============================================================================
-- select public.crm_clientes('383 481',          null, null, null, 10, 0) ->> 'total';  -- (>= 1, incluye a Juan)
-- select public.crm_clientes('383-481-8271',     null, null, null, 10, 0) ->> 'total';  -- (>= 1)
-- select public.crm_clientes('(383) 4818271',    null, null, null, 10, 0) ->> 'total';  -- (>= 1)
-- select public.crm_clientes('+54 9 383 481 8271', null, null, null, 10, 0) ->> 'total'; -- (>= 1)
-- select public.crm_clientes('03834818271',      null, null, null, 10, 0) ->> 'total';  -- (>= 1)
-- select public.crm_clientes('3834818271',       null, null, null, 10, 0) ->> 'total';  -- (>= 1, como antes)
-- select public.crm_clientes('juan',             null, null, null, 10, 0) ->> 'total';  -- (>= 1, sin cambios)
-- select public.crm_clientes('juan 2',           null, null, null, 10, 0) ->> 'total';  -- (no devuelve a todos los que tienen un 2 en el telefono)
-- select public.crm_clientes('999 999',          null, null, null, 10, 0) ->> 'total';  -- (0)
-- select public.crm_clientes(null,               null, null, null, 10, 0) ->> 'total';  -- (total de clientes, sin cambios)
-- -- Como encargado de sucursal o anon: ERROR "No tenés permiso para hacer esto." / sin execute.

-- ============================================================================
-- ROLLBACK (manual): volver a ejecutar de 022 el bloque "5. crm_clientes"
-- (create or replace function public.crm_clientes ... + comment). No hay datos
-- que revertir.
-- ============================================================================
