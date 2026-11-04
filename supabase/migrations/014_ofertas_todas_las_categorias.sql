-- Piedra Mora - Fase 1 - Paso 1C (ajuste)
-- Las ofertas valen para productos de CUALQUIER categoria (antes solo "promo").
-- Cambia una sola regla dentro de public.pm_calcular_pedido.
-- Si ya estaba aplicado, no hace nada.

do $$
declare
  v_def text;
  v_nuevo text;
begin
  select pg_get_functiondef('public.pm_calcular_pedido(text,text,text,jsonb,text,numeric,numeric)'::regprocedure)
    into v_def;

  if position('v_cat = ''promo'' and v_oferta' in v_def) = 0 then
    raise notice 'La regla de promo ya no esta en la funcion: ya estaba aplicado. No se cambio nada.';
    return;
  end if;

  v_nuevo := replace(v_def, 'v_cat = ''promo'' and v_oferta is not null', 'v_oferta is not null');
  execute v_nuevo;
  raise notice 'Aplicado: las ofertas ahora valen para todas las categorias.';
end $$;