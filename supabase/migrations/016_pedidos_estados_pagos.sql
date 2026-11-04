-- ============================================================================
-- Piedra Mora - Fase 1 - Pedidos: estados de tablero y pagos
-- Migracion 016
-- ============================================================================
-- IMPORTANTE: hacer backup de la base antes de aplicarla.
--
-- Objetivo:
--   1. Agregar los estados listo y en_camino al check de pedidos.
--      Se mantiene confirmado como "En preparacion" (sin reescribir datos).
--   2. Agregar pagado boolean y pagado_en timestamptz.
--   3. Ampliar el UPDATE permitido al rol authenticated, manteniendo RLS.
--
-- No se modifica el check de modalidad ni el trigger de fidelidad.
-- El trigger public.pm_pedidos_actualizar_clientes() sigue disparando solo
-- cuando un pedido pasa a estado 'entregado'.
--
-- Idempotente: se puede ejecutar varias veces sin perder datos.
-- ============================================================================

-- 1. Columnas de pago ---------------------------------------------------------
alter table public.pedidos
  add column if not exists pagado boolean not null default false;

alter table public.pedidos
  add column if not exists pagado_en timestamptz;

comment on column public.pedidos.pagado is
  'Indica si el pedido fue cobrado. Lo marca el admin desde el tablero.';

comment on column public.pedidos.pagado_en is
  'Momento en que se marco el pedido como pagado.';

-- 2. Estados permitidos -------------------------------------------------------
alter table public.pedidos
  drop constraint if exists pedidos_estado_chk;

alter table public.pedidos
  add constraint pedidos_estado_chk
  check (estado in ('pendiente', 'confirmado', 'listo', 'en_camino', 'entregado', 'cancelado'));

comment on constraint pedidos_estado_chk on public.pedidos is
  'Estados del tablero: pendiente, confirmado (En preparacion), listo, en_camino, entregado y cancelado.';

-- 3. Permisos de actualizacion ------------------------------------------------
-- La politica RLS "Pedidos edicion admin" ya exige public.es_admin().
-- Se amplian las columnas que authenticated puede actualizar.
grant update (estado, pagado, pagado_en) on public.pedidos to authenticated;

-- 4. Verificacion del trigger de fidelidad ------------------------------------
-- No se recrea: la definicion vigente solo suma/resta clientes cuando
-- old.estado o new.estado son 'entregado'. Los estados nuevos no lo alteran.
comment on function public.pm_pedidos_actualizar_clientes() is
  'Mantiene los contadores de clientes solo al entrar o salir del estado entregado.';
