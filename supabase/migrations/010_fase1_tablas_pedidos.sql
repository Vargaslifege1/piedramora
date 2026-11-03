-- ============================================================================
-- Piedra Mora - Fase 1 - Paso 1B
-- Tablas base: pedidos, clientes, configuracion, zonas y tramos de envio
-- ============================================================================
-- Objetivo:
--   1. Crear la estructura de pedidos con numero PM-0001.
--   2. Crear clientes con contadores que solo cambian al pasar a 'entregado'.
--   3. Crear configuracion editable del negocio.
--   4. Crear zonas y tramos de envio.
--
-- Decisiones:
--   - La carta sigue viviendo como JSONB en public.carta (no se migra).
--   - total = subtotal - descuento + costo_envio.
--   - El descuento de pago se aplica solo a los productos.
--   - Modalidades permitidas: mesa, delivery, retiro.
--   - Estados permitidos: pendiente, confirmado, entregado, cancelado.
--   - Zona normal: $3000 por sucursal. La Estancita: $6000 por sucursal.
--   - tramos_envio queda vacia para cargarla desde el admin.
--
-- Requisitos previos:
--   - Haber ejecutado las migraciones 000, 001, 002 y 003.
--   - Tener public.admins y public.es_admin() disponibles.
--
-- Idempotente:
--   Se puede ejecutar varias veces. No pisa configuracion ni zonas existentes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Secuencia para el numero de orden
-- ----------------------------------------------------------------------------
create sequence if not exists public.pm_pedido_numero_seq
  as bigint
  start with 1
  increment by 1
  no minvalue
  no maxvalue
  cache 1;

comment on sequence public.pm_pedido_numero_seq is
  'Secuencia del numero de orden visible PM-0001. Puede dejar huecos si falla una insercion.';

-- ----------------------------------------------------------------------------
-- 2. Pedidos
-- ----------------------------------------------------------------------------
create table if not exists public.pedidos (
  id uuid primary key default gen_random_uuid(),

  numero_orden text not null unique
    default ('PM-' || lpad(nextval('public.pm_pedido_numero_seq')::text, 4, '0')),

  created_at timestamptz not null default now(),

  sucursal_id text not null,
  modalidad text not null default 'delivery',
  estado text not null default 'pendiente',

  cliente_nombre text not null,
  cliente_telefono text not null,

  direccion text,
  lat numeric(10, 7),
  lng numeric(10, 7),
  zona_envio text,

  items_snapshot jsonb not null default '[]'::jsonb,

  subtotal numeric(12, 2) not null,
  descuento numeric(12, 2) not null default 0,
  costo_envio numeric(12, 2) not null default 0,
  total numeric(12, 2) not null,

  metodo_pago text not null,

  -- Clave para que la RPC de 1C no duplique pedidos por doble clic o reintento.
  idempotency_key uuid unique,

  -- Notas del cliente (timbre, numero de mesa, aclaraciones).
  notas text,

  -- true cuando el pedido quedo guardado en la base.
  sincronizado boolean not null default true,

  constraint pedidos_numero_orden_formato_chk
    check (numero_orden ~ '^PM-[0-9]{4,}$'),

  constraint pedidos_sucursal_id_chk
    check (char_length(btrim(sucursal_id)) between 1 and 80),

  constraint pedidos_modalidad_chk
    check (modalidad in ('mesa', 'delivery', 'retiro')),

  constraint pedidos_estado_chk
    check (estado in ('pendiente', 'confirmado', 'entregado', 'cancelado')),

  constraint pedidos_cliente_nombre_chk
    check (char_length(btrim(cliente_nombre)) between 2 and 80),

  constraint pedidos_cliente_telefono_chk
    check (cliente_telefono ~ '^[0-9]{8,15}$'),

  constraint pedidos_direccion_largo_chk
    check (direccion is null or char_length(direccion) <= 300),

  constraint pedidos_lat_chk
    check (lat is null or (lat between -90 and 90)),

  constraint pedidos_lng_chk
    check (lng is null or (lng between -180 and 180)),

  constraint pedidos_zona_envio_largo_chk
    check (zona_envio is null or char_length(btrim(zona_envio)) between 1 and 80),

  constraint pedidos_items_snapshot_array_chk
    check (jsonb_typeof(items_snapshot) = 'array'),

  constraint pedidos_notas_largo_chk
    check (notas is null or char_length(notas) <= 500),

  constraint pedidos_metodo_pago_chk
    check (char_length(btrim(metodo_pago)) between 1 and 40),

  constraint pedidos_costos_no_negativos_chk
    check (
      subtotal >= 0
      and descuento >= 0
      and costo_envio >= 0
      and total >= 0
    ),

  constraint pedidos_descuento_no_mayor_al_subtotal_chk
    check (descuento <= subtotal),

  constraint pedidos_total_coherente_chk
    check (total = subtotal - descuento + costo_envio),

  constraint pedidos_delivery_datos_chk
    check (
      modalidad <> 'delivery'
      or (
        direccion is not null
        and lat is not null
        and lng is not null
        and zona_envio is not null
      )
    )
);

-- Si la tabla ya existia de una corrida anterior, aseguramos el default.
alter table public.pedidos
  alter column numero_orden
  set default ('PM-' || lpad(nextval('public.pm_pedido_numero_seq')::text, 4, '0'));

alter sequence public.pm_pedido_numero_seq
  owned by public.pedidos.numero_orden;

create index if not exists pedidos_estado_created_at_idx
  on public.pedidos (estado, created_at desc);

create index if not exists pedidos_created_at_idx
  on public.pedidos (created_at desc);

create index if not exists pedidos_cliente_telefono_idx
  on public.pedidos (cliente_telefono);

create index if not exists pedidos_sucursal_id_idx
  on public.pedidos (sucursal_id);

comment on table public.pedidos is
  'Pedidos del checkout publico. Los totales y los precios deben ser calculados por la RPC crear_pedido.';

comment on column public.pedidos.numero_orden is
  'Numero visible con formato PM-0001. Se genera con public.pm_pedido_numero_seq.';

comment on column public.pedidos.items_snapshot is
  'Snapshot de items: producto_id, nombre, precio_unitario final, cantidad, variacion y adicionales.';

comment on column public.pedidos.idempotency_key is
  'UUID generado por el cliente para evitar pedidos duplicados por reintentos.';

comment on column public.pedidos.total is
  'Debe cumplir: subtotal - descuento + costo_envio. El descuento de pago no se aplica al envio.';

-- ----------------------------------------------------------------------------
-- 3. Clientes
-- ----------------------------------------------------------------------------
create table if not exists public.clientes (
  telefono text primary key,
  nombre text not null,
  cantidad_pedidos_entregados integer not null default 0,
  monto_total_gastado numeric(12, 2) not null default 0,
  ultima_visita timestamptz,

  constraint clientes_telefono_chk
    check (telefono ~ '^[0-9]{8,15}$'),

  constraint clientes_nombre_chk
    check (char_length(btrim(nombre)) between 2 and 80),

  constraint clientes_cantidad_no_negativa_chk
    check (cantidad_pedidos_entregados >= 0),

  constraint clientes_monto_no_negativo_chk
    check (monto_total_gastado >= 0)
);

create index if not exists clientes_ultima_visita_idx
  on public.clientes (ultima_visita desc);

comment on table public.clientes is
  'Clientes identificados por telefono normalizado (solo digitos, 8 a 15).';

comment on column public.clientes.cantidad_pedidos_entregados is
  'Solo se modifica desde el trigger de pedidos cuando el estado pasa a entregado o se revierte.';

-- ----------------------------------------------------------------------------
-- 4. Configuracion del negocio
-- ----------------------------------------------------------------------------
create table if not exists public.config_negocio (
  clave text primary key,
  valor jsonb not null,

  constraint config_negocio_clave_chk
    check (char_length(btrim(clave)) between 1 and 80)
);

comment on table public.config_negocio is
  'Configuracion editable del negocio. Los valores iniciales salen de data/config.json.';

-- Descuentos actuales de data/config.json: ambos son 0%.
insert into public.config_negocio (clave, valor)
values
  ('descuentos_pago', '{"efectivo": 0, "transferencia": 0}'::jsonb),
  ('metros_por_cuadra', '100'::jsonb),
  -- data/config.json no tiene tiempo estimado; se deja null para cargarlo desde el admin.
  ('tiempo_estimado_entrega', 'null'::jsonb)
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- 5. Zonas de envio
-- ----------------------------------------------------------------------------
create table if not exists public.zonas_envio (
  id uuid primary key default gen_random_uuid(),
  sucursal_id text,
  nombre text not null,
  costo numeric(12, 2) not null default 0,
  activa boolean not null default true,
  orden integer not null default 0,
  nota text,

  constraint zonas_envio_sucursal_chk
    check (sucursal_id is null or char_length(btrim(sucursal_id)) between 1 and 80),

  constraint zonas_envio_nombre_chk
    check (char_length(btrim(nombre)) between 1 and 80),

  constraint zonas_envio_costo_no_negativo_chk
    check (costo >= 0),

  constraint zonas_envio_orden_no_negativo_chk
    check (orden >= 0),

  constraint zonas_envio_nota_largo_chk
    check (nota is null or char_length(nota) <= 500)
);

create unique index if not exists zonas_envio_sucursal_nombre_uidx
  on public.zonas_envio (coalesce(sucursal_id, ''), lower(nombre));

create index if not exists zonas_envio_sucursal_activa_orden_idx
  on public.zonas_envio (sucursal_id, activa, orden);

comment on table public.zonas_envio is
  'Zonas de entrega. sucursal_id null significa que aplica a todas las sucursales.';

comment on column public.zonas_envio.nota is
  'Texto libre para pegar la ubicacion de referencia de la zona.';

-- Valores iniciales. Se cargan por sucursal usando los IDs reales de data/sucursales.json.
insert into public.zonas_envio (sucursal_id, nombre, costo, activa, orden, nota)
select v.sucursal_id, v.nombre, v.costo, true, v.orden, v.nota
from (
  values
    ('maestro-quiroga'::text,    'Zona normal'::text,  3000::numeric, 10, null::text),
    ('maestro-quiroga'::text,    'La Estancita'::text, 6000::numeric, 20, null::text),
    ('intendente-lascano'::text, 'Zona normal'::text,  3000::numeric, 10, null::text),
    ('intendente-lascano'::text, 'La Estancita'::text, 6000::numeric, 20, null::text)
) as v(sucursal_id, nombre, costo, orden, nota)
where not exists (
  select 1
  from public.zonas_envio z
  where coalesce(z.sucursal_id, '') = coalesce(v.sucursal_id, '')
    and lower(z.nombre) = lower(v.nombre)
);

-- ----------------------------------------------------------------------------
-- 6. Tramos de envio
-- ----------------------------------------------------------------------------
create table if not exists public.tramos_envio (
  id uuid primary key default gen_random_uuid(),
  sucursal_id text,
  desde_cuadras integer not null,
  hasta_cuadras integer not null,
  costo numeric(12, 2) not null default 0,
  activa boolean not null default true,

  constraint tramos_envio_sucursal_chk
    check (sucursal_id is null or char_length(btrim(sucursal_id)) between 1 and 80),

  constraint tramos_envio_desde_no_negativo_chk
    check (desde_cuadras >= 0),

  constraint tramos_envio_hasta_no_negativo_chk
    check (hasta_cuadras >= 0),

  constraint tramos_envio_rango_chk
    check (hasta_cuadras >= desde_cuadras),

  constraint tramos_envio_costo_no_negativo_chk
    check (costo >= 0)
);

create unique index if not exists tramos_envio_sucursal_rango_uidx
  on public.tramos_envio (coalesce(sucursal_id, ''), desde_cuadras, hasta_cuadras);

create index if not exists tramos_envio_sucursal_activa_desde_idx
  on public.tramos_envio (sucursal_id, activa, desde_cuadras);

comment on table public.tramos_envio is
  'Tramos por cuadras para calcular envio. Queda vacia al inicio; se carga desde el admin.';

-- ----------------------------------------------------------------------------
-- 7. Trigger de contadores de clientes
-- ----------------------------------------------------------------------------
-- Regla:
--   - Nunca suma al crear el pedido.
--   - Suma solo cuando un pedido pasa de otro estado a 'entregado'.
--   - Resta si un pedido entregado se revierte o si cambia de telefono.
--   - Corrige el monto si cambia el total de un pedido ya entregado.
create or replace function public.pm_pedidos_actualizar_clientes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_telefono_anterior text;
  v_telefono_nuevo text;
  v_pedido_id uuid;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  v_telefono_anterior := old.cliente_telefono;
  v_telefono_nuevo := new.cliente_telefono;
  v_pedido_id := new.id;

  -- Restar el pedido anterior si estaba entregado y deja de estarlo,
  -- o si el pedido entregado cambia de telefono.
  if old.estado = 'entregado'
     and (
       new.estado <> 'entregado'
       or v_telefono_anterior is distinct from v_telefono_nuevo
     ) then
    update public.clientes c
       set cantidad_pedidos_entregados = greatest(0, c.cantidad_pedidos_entregados - 1),
           monto_total_gastado = greatest(0, c.monto_total_gastado - old.total),
           ultima_visita = (
             select max(p.created_at)
             from public.pedidos p
             where p.cliente_telefono = v_telefono_anterior
               and p.estado = 'entregado'
               and p.id <> v_pedido_id
           )
     where c.telefono = v_telefono_anterior;
  end if;

  -- Sumar cuando pasa a entregado, o cuando un pedido entregado cambia de telefono.
  if new.estado = 'entregado'
     and (
       old.estado <> 'entregado'
       or v_telefono_anterior is distinct from v_telefono_nuevo
     ) then
    insert into public.clientes (
      telefono,
      nombre,
      cantidad_pedidos_entregados,
      monto_total_gastado,
      ultima_visita
    )
    values (
      v_telefono_nuevo,
      new.cliente_nombre,
      1,
      new.total,
      now()
    )
    on conflict (telefono) do update
      set nombre = excluded.nombre,
          cantidad_pedidos_entregados = public.clientes.cantidad_pedidos_entregados + 1,
          monto_total_gastado = public.clientes.monto_total_gastado + excluded.monto_total_gastado,
          ultima_visita = excluded.ultima_visita;
  elsif old.estado = 'entregado'
        and new.estado = 'entregado'
        and v_telefono_anterior = v_telefono_nuevo
        and old.total is distinct from new.total then
    -- Corregir el monto si un pedido ya entregado cambia de total.
    update public.clientes c
       set monto_total_gastado = greatest(0, c.monto_total_gastado + (new.total - old.total)),
           nombre = new.cliente_nombre
     where c.telefono = v_telefono_nuevo;
  end if;

  return new;
end;
$$;

comment on function public.pm_pedidos_actualizar_clientes() is
  'Mantiene los contadores de clientes al entrar o salir del estado entregado.';

drop trigger if exists pedidos_actualizar_clientes on public.pedidos;
create trigger pedidos_actualizar_clientes
  after update of estado, cliente_telefono, total on public.pedidos
  for each row
  execute function public.pm_pedidos_actualizar_clientes();
