-- ============================================================================
-- Piedra Mora - Fase 1 - Envio por distancia (cuadras)
-- ============================================================================
-- YA EJECUTADO A MANO en Supabase. Queda como registro del proyecto.
--
-- Que hace:
--   1. Carga los tramos de envio SOLO si la tabla esta vacia
--      (no pisa los tramos que se editen despues).
--   2. Desactiva la zona fija "La Estancita": ahora la cubre el ultimo tramo.
--   3. Crea public.cotizar_envio(), publica, para que el checkout muestre el
--      costo antes de enviar. Usa la misma logica que crear_pedido.
--
-- Distancia: linea recta desde la sucursal hasta la direccion del cliente,
-- 100 m por cuadra (config_negocio.metros_por_cuadra), redondeada hacia arriba.
-- Requiere: 010, 011, 013 (columna zonas_envio.aplica_tramos) y la clave
-- sucursales_coords en config_negocio.
-- ============================================================================

-- 1. Tramos (sucursal_id null = todas las sucursales).
--    El ultimo llega hasta 999 cuadras para que ninguna distancia quede sin precio.
insert into public.tramos_envio (sucursal_id, desde_cuadras, hasta_cuadras, costo, activa)
select v.sucursal_id, v.desde_cuadras, v.hasta_cuadras, v.costo, true
from (
  values
    (null::text,  0,  15, 3000::numeric),
    (null::text, 16,  24, 4500::numeric),
    (null::text, 25, 999, 6000::numeric)
) as v(sucursal_id, desde_cuadras, hasta_cuadras, costo)
where not exists (select 1 from public.tramos_envio);

-- 2. La Estancita ya no es una zona fija
update public.zonas_envio set activa = false where lower(nombre) = 'la estancita';

-- 3. Cotizacion publica del envio
create or replace function public.cotizar_envio(
  p_sucursal_id text,
  p_lat numeric,
  p_lng numeric
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_coords jsonb;
  v_suc jsonb;
  v_zona public.zonas_envio%rowtype;
  v_envio numeric;
  v_mpc numeric;
  v_lat0 numeric;
  v_lng0 numeric;
  v_metros double precision;
  v_cuadras integer;
  v_costo numeric;
  v_por_distancia boolean := false;
begin
  select valor into v_coords from public.config_negocio where clave = 'sucursales_coords';
  v_suc := v_coords -> p_sucursal_id;
  if v_suc is null then
    raise exception 'La sucursal no existe.';
  end if;

  select z.* into v_zona
    from public.zonas_envio z
   where z.activa
     and lower(z.nombre) = 'zona normal'
     and (z.sucursal_id = p_sucursal_id or z.sucursal_id is null)
   order by (z.sucursal_id is null), z.orden
   limit 1;
  if not found then
    raise exception 'El envío no está configurado.';
  end if;
  v_envio := v_zona.costo;

  if v_zona.aplica_tramos
     and p_lat is not null and p_lng is not null
     and p_lat between -90 and 90 and p_lng between -180 and 180
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

    select t.costo into v_costo
      from public.tramos_envio t
     where t.activa
       and (t.sucursal_id = p_sucursal_id or t.sucursal_id is null)
       and v_cuadras between t.desde_cuadras and t.hasta_cuadras
     order by (t.sucursal_id is null), t.desde_cuadras
     limit 1;
    if found then
      v_envio := v_costo;
      v_por_distancia := true;
    end if;
  end if;

  return jsonb_build_object(
    'costo_envio', v_envio,
    'cuadras', v_cuadras,
    'metros', round(v_metros::numeric),
    'por_distancia', v_por_distancia);
end;
$$;

revoke all on function public.cotizar_envio(text, numeric, numeric) from public;
grant execute on function public.cotizar_envio(text, numeric, numeric) to anon, authenticated;