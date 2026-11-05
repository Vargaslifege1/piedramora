-- ============================================================================
-- 019 - Fidelidad y premios (Fase 3D-1, solo base de datos)
-- ============================================================================
-- Reglas:
--   - Ciclo de 10 pedidos entregados que se repite.
--   - Al 5.o de cada ciclo: 30% de descuento en un pedido futuro (sin tope en pesos).
--   - Al 10.o de cada ciclo: una Cheeseburger gratis.
--   - Ambos premios vencen a los 30 dias y son de un solo uso.
--   - Cuentan solo pedidos entregados, con sincronizado distinto de false y
--     pedidos.subtotal >= pedido minimo (10.000). Se mide sobre el subtotal de
--     productos (antes de descuentos y sin envio).
--   - Un solo beneficio por pedido: con premio no se aplican ni el cupon ni el
--     descuento por medio de pago.
--
-- Prerequisitos: 010 a 018 aplicadas (usa es_dueno() de 017, carta y
-- agotados_sucursal, crear_pedido de 018 con 13 argumentos).
--
-- Que hace:
--   1. Seed de config_negocio.fidelidad (solo reglas, sin datos personales).
--   2. Funcion interna pm_fidelidad_config() que valida la config.
--   3. Tabla premios (RLS: solo el dueno lee; nadie escribe directo).
--   4. Columnas: pedidos.fidelidad_contado, pedidos.premio_id,
--      clientes.fidelidad_pedidos.
--   5. Trigger: se extiende pm_pedidos_actualizar_clientes() (010) para
--      acreditar fidelidad al pasar a 'entregado'.
--   6. Trigger nuevo: cancelar un pedido libera el premio que consumio.
--   7. fidelidad_intentos + mis_premios() + mi_progreso_fidelidad().
--   8. crear_pedido pasa de 13 a 14 argumentos (p_premio_id).
--
-- Escritura de config_negocio: ya es solo es_dueno() desde la 017
-- ("Config alta/edicion/baja admin"). Esta migracion NO la cambia.
--
-- LIMITACIONES CONOCIDAS (decision de diseno, documentadas):
--   - Cada pedido suma como maximo una vez (pedidos.fidelidad_contado). Si un
--     pedido entregado se revierte o se cancela despues, el contador NO se
--     resta y un premio ya generado NO se retira.
--   - Si un pedido entregado cambia de telefono, el conteo queda en el telefono
--     original (el bloque de fidelidad solo se dispara al pasar a 'entregado').
--   - Pedidos entregados antes de aplicar esta migracion no cuentan (no hay
--     backfill): todos los clientes arrancan con contador 0.
--   - Si falla la acreditacion de fidelidad, el cambio de estado a 'entregado'
--     NO se bloquea: queda un WARNING en los logs de Postgres y el pedido no se
--     marca como contado (se puede reintentar al volver a entregar).
--
-- IMPORTANTE: hacer BACKUP de la base antes de aplicar esta migracion.
-- Idempotente: se puede ejecutar mas de una vez.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Configuracion del programa (solo reglas)
-- ----------------------------------------------------------------------------
insert into public.config_negocio (clave, valor)
values (
  'fidelidad',
  '{
    "activo": true,
    "pedido_minimo": 10000,
    "ciclo": 10,
    "niveles": [
      {"en": 5,  "tipo": "descuento_porcentaje", "valor": 30,
       "tope_en_pesos": null, "dias_vencimiento": 30},
      {"en": 10, "tipo": "producto_gratis", "producto_id": "burger_cheeseburger",
       "dias_vencimiento": 30}
    ]
  }'::jsonb
)
on conflict (clave) do nothing;

-- Devuelve la config SOLO si el programa esta activo y la config es valida;
-- en cualquier otro caso (falta, mal formada, inactiva) devuelve null y el
-- programa se considera inactivo. Uso interno: sin permisos para clientes.
create or replace function public.pm_fidelidad_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  v_nivel jsonb;
  v_ciclo integer;
  v_en integer;
  v_ens integer[] := '{}';
  v_tipo text;
begin
  select valor into v from public.config_negocio where clave = 'fidelidad';

  if v is null or jsonb_typeof(v) <> 'object' then
    return null;
  end if;
  if jsonb_typeof(v -> 'activo') <> 'boolean' or (v ->> 'activo') <> 'true' then
    return null;
  end if;
  if jsonb_typeof(v -> 'pedido_minimo') <> 'number'
     or (v ->> 'pedido_minimo')::numeric < 0 then
    return null;
  end if;
  if jsonb_typeof(v -> 'ciclo') <> 'number'
     or (v ->> 'ciclo') !~ '^[0-9]{1,4}$' then
    return null;
  end if;
  v_ciclo := (v ->> 'ciclo')::integer;
  if v_ciclo < 1 or v_ciclo > 1000 then
    return null;
  end if;
  if jsonb_typeof(v -> 'niveles') <> 'array'
     or jsonb_array_length(v -> 'niveles') < 1
     or jsonb_array_length(v -> 'niveles') > 20 then
    return null;
  end if;

  for v_nivel in select e.value from jsonb_array_elements(v -> 'niveles') as e(value) loop
    if jsonb_typeof(v_nivel) <> 'object' then
      return null;
    end if;

    if jsonb_typeof(v_nivel -> 'en') <> 'number'
       or (v_nivel ->> 'en') !~ '^[0-9]{1,4}$' then
      return null;
    end if;
    v_en := (v_nivel ->> 'en')::integer;
    if v_en < 1 or v_en > v_ciclo or v_en = any (v_ens) then
      return null;
    end if;
    v_ens := v_ens || v_en;

    if jsonb_typeof(v_nivel -> 'dias_vencimiento') <> 'number'
       or (v_nivel ->> 'dias_vencimiento') !~ '^[0-9]{1,3}$'
       or (v_nivel ->> 'dias_vencimiento')::integer < 1
       or (v_nivel ->> 'dias_vencimiento')::integer > 365 then
      return null;
    end if;

    v_tipo := v_nivel ->> 'tipo';
    if v_tipo = 'descuento_porcentaje' then
      if jsonb_typeof(v_nivel -> 'valor') <> 'number'
         or (v_nivel ->> 'valor')::numeric <= 0
         or (v_nivel ->> 'valor')::numeric > 100 then
        return null;
      end if;
      if v_nivel ? 'tope_en_pesos'
         and jsonb_typeof(v_nivel -> 'tope_en_pesos') <> 'null'
         and (jsonb_typeof(v_nivel -> 'tope_en_pesos') <> 'number'
              or (v_nivel ->> 'tope_en_pesos')::numeric <= 0) then
        return null;
      end if;
    elsif v_tipo = 'producto_gratis' then
      if jsonb_typeof(v_nivel -> 'producto_id') <> 'string'
         or char_length(btrim(v_nivel ->> 'producto_id')) not between 1 and 80 then
        return null;
      end if;
    else
      return null;
    end if;
  end loop;

  return v;
exception when others then
  return null;
end;
$$;

revoke all on function public.pm_fidelidad_config() from public, anon, authenticated;

comment on function public.pm_fidelidad_config() is
  'Config de fidelidad validada. null si falta, es invalida o el programa esta inactivo.';

-- ----------------------------------------------------------------------------
-- 2. Tabla premios
-- ----------------------------------------------------------------------------
create table if not exists public.premios (
  id uuid primary key default gen_random_uuid(),

  -- Telefono normalizado (solo digitos), igual que crear_pedido y clientes.
  telefono text not null,
  tipo text not null,
  valor numeric(12, 2),
  producto_id text,
  tope_en_pesos numeric(12, 2),
  vencimiento timestamptz not null,

  usado boolean not null default false,
  usado_en timestamptz,
  -- Pedido donde se canjeo el premio.
  pedido_id uuid references public.pedidos (id) on delete set null,
  -- Pedido entregado que genero el premio.
  pedido_origen_id uuid references public.pedidos (id) on delete set null,
  creado_en timestamptz not null default now(),

  constraint premios_telefono_chk
    check (telefono ~ '^[0-9]{8,15}$'),
  constraint premios_tipo_chk
    check (tipo in ('descuento_porcentaje', 'producto_gratis')),
  constraint premios_datos_por_tipo_chk
    check (
      (tipo = 'descuento_porcentaje'
        and valor is not null and valor > 0 and valor <= 100
        and producto_id is null)
      or
      (tipo = 'producto_gratis'
        and producto_id is not null and char_length(btrim(producto_id)) between 1 and 80
        and valor is null and tope_en_pesos is null)
    ),
  constraint premios_tope_chk
    check (tope_en_pesos is null or tope_en_pesos > 0),
  constraint premios_uso_coherente_chk
    check (usado or (usado_en is null and pedido_id is null))
);

-- Evita premios duplicados si el trigger corre dos veces para el mismo pedido.
create unique index if not exists premios_origen_tipo_uidx
  on public.premios (pedido_origen_id, tipo);

create index if not exists premios_telefono_disponibles_idx
  on public.premios (telefono, vencimiento)
  where not usado;

create index if not exists premios_pedido_idx
  on public.premios (pedido_id);

comment on table public.premios is
  'Premios de fidelidad. Solo los crean/modifican funciones security definer.';

alter table public.premios enable row level security;

revoke all on public.premios from public, anon, authenticated;
grant select on public.premios to authenticated;

-- Solo el dueno lee. No hay policies ni grants de escritura: ni el dueno ni el
-- admin de sucursal ni los clientes modifican premios directamente.
drop policy if exists "Premios lectura dueno" on public.premios;
create policy "Premios lectura dueno"
  on public.premios
  for select
  to authenticated
  using (public.es_dueno());

-- ----------------------------------------------------------------------------
-- 3. Columnas nuevas
-- ----------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists fidelidad_contado boolean not null default false;

alter table public.pedidos
  add column if not exists premio_id uuid references public.premios (id) on delete set null;

comment on column public.pedidos.fidelidad_contado is
  'true cuando el pedido ya sumo al contador de fidelidad. Evita sumar dos veces.';
comment on column public.pedidos.premio_id is
  'Premio de fidelidad canjeado en este pedido. null si no se uso.';

-- Lectura para el admin autenticado. NO se modifica el grant de UPDATE por
-- columnas de pedidos: estas columnas solo las escriben funciones definer.
grant select (fidelidad_contado, premio_id) on public.pedidos to authenticated;

alter table public.clientes
  add column if not exists fidelidad_pedidos integer not null default 0;

alter table public.clientes
  drop constraint if exists clientes_fidelidad_pedidos_chk;
alter table public.clientes
  add constraint clientes_fidelidad_pedidos_chk check (fidelidad_pedidos >= 0);

comment on column public.clientes.fidelidad_pedidos is
  'Pedidos que cuentan para fidelidad (separado de cantidad_pedidos_entregados). No se resta al revertir.';

-- ----------------------------------------------------------------------------
-- 4. Acreditar fidelidad + trigger de clientes extendido
-- ----------------------------------------------------------------------------
-- Suma un pedido al contador del cliente y genera el premio si corresponde.
-- Lo llama el trigger pm_pedidos_actualizar_clientes() al pasar a 'entregado'.
create or replace function public.pm_fidelidad_acreditar(p public.pedidos)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg jsonb;
  v_ciclo integer;
  v_cli public.clientes%rowtype;
  v_n integer;
  v_pos integer;
  v_nivel jsonb;
begin
  v_cfg := public.pm_fidelidad_config();
  if v_cfg is null then
    return;
  end if;

  -- Solo pedidos sincronizados y que llegan al minimo (sobre el subtotal de
  -- productos, antes de descuentos y sin envio).
  if p.sincronizado is not distinct from false then
    return;
  end if;
  if p.subtotal < (v_cfg ->> 'pedido_minimo')::numeric then
    return;
  end if;

  -- Cada pedido suma como maximo una vez. Si no se actualiza ninguna fila,
  -- el pedido ya estaba contado.
  update public.pedidos
     set fidelidad_contado = true
   where id = p.id
     and not fidelidad_contado;
  if not found then
    return;
  end if;

  -- Bloqueo de la fila del cliente: serializa entregas simultaneas.
  -- (La fila ya existe: el trigger la crea/actualiza antes de llamar aca.)
  select * into v_cli
    from public.clientes
   where telefono = p.cliente_telefono
   for update;
  if not found then
    raise exception 'Cliente inexistente para fidelidad.';
  end if;

  update public.clientes
     set fidelidad_pedidos = fidelidad_pedidos + 1
   where telefono = p.cliente_telefono
  returning fidelidad_pedidos into v_n;

  v_ciclo := (v_cfg ->> 'ciclo')::integer;
  v_pos := ((v_n - 1) % v_ciclo) + 1;

  for v_nivel in
    select e.value
      from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
     where (e.value ->> 'en')::integer = v_pos
  loop
    insert into public.premios (
      telefono, tipo, valor, producto_id, tope_en_pesos,
      vencimiento, pedido_origen_id
    ) values (
      p.cliente_telefono,
      v_nivel ->> 'tipo',
      case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
           then (v_nivel ->> 'valor')::numeric end,
      case when v_nivel ->> 'tipo' = 'producto_gratis'
           then v_nivel ->> 'producto_id' end,
      case when v_nivel ->> 'tipo' = 'descuento_porcentaje'
                 and jsonb_typeof(v_nivel -> 'tope_en_pesos') = 'number'
           then (v_nivel ->> 'tope_en_pesos')::numeric end,
      now() + make_interval(days => (v_nivel ->> 'dias_vencimiento')::integer),
      p.id
    )
    on conflict (pedido_origen_id, tipo) do nothing;
  end loop;
end;
$$;

revoke all on function public.pm_fidelidad_acreditar(public.pedidos)
  from public, anon, authenticated;

comment on function public.pm_fidelidad_acreditar(public.pedidos) is
  'Suma un pedido entregado al contador de fidelidad y genera el premio del ciclo. Solo desde el trigger.';

-- Funcion del trigger: copia de la version de 010 (016 solo le cambio el
-- comment). El unico agregado es el bloque de fidelidad antes del return.
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

  -- Fidelidad (019): solo al pasar a entregado (no por cambio de telefono).
  -- Si falla, no se bloquea el cambio de estado: queda un WARNING en los logs.
  if old.estado <> 'entregado' and new.estado = 'entregado' then
    begin
      perform public.pm_fidelidad_acreditar(new);
    exception when others then
      raise warning 'fidelidad: no se pudo acreditar el pedido %: %', new.id, sqlerrm;
    end;
  end if;

  return new;
end;
$$;

comment on function public.pm_pedidos_actualizar_clientes() is
  'Mantiene los contadores de clientes al entrar o salir del estado entregado y acredita fidelidad (019).';

-- El trigger ya existe (010) con la misma definicion; se recrea igual por idempotencia.
drop trigger if exists pedidos_actualizar_clientes on public.pedidos;
create trigger pedidos_actualizar_clientes
  after update of estado, cliente_telefono, total on public.pedidos
  for each row
  execute function public.pm_pedidos_actualizar_clientes();

-- ----------------------------------------------------------------------------
-- 5. Cancelar un pedido libera el premio que consumio
-- ----------------------------------------------------------------------------
create or replace function public.pm_pedidos_liberar_premio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado = 'cancelado' and old.estado is distinct from 'cancelado' then
    -- Solo se libera si no vencio: un premio vencido queda como usado.
    update public.premios
       set usado = false,
           usado_en = null,
           pedido_id = null
     where pedido_id = new.id
       and usado
       and vencimiento > now();
  end if;
  return new;
end;
$$;

revoke all on function public.pm_pedidos_liberar_premio() from public, anon, authenticated;

comment on function public.pm_pedidos_liberar_premio() is
  'Al cancelar un pedido que uso un premio, lo deja disponible de nuevo (si no vencio).';

drop trigger if exists pedidos_liberar_premio on public.pedidos;
create trigger pedidos_liberar_premio
  after update of estado on public.pedidos
  for each row
  execute function public.pm_pedidos_liberar_premio();

-- ----------------------------------------------------------------------------
-- 6. Anti-spam y consultas publicas (mis_premios, mi_progreso_fidelidad)
-- ----------------------------------------------------------------------------
-- Igual que cupon_intentos (018): RLS activo, sin policies ni grants.
create table if not exists public.fidelidad_intentos (
  id bigint generated by default as identity primary key,

  telefono text,
  ip text,
  creado_en timestamptz not null default now(),

  constraint fidelidad_intentos_telefono_chk
    check (telefono is null or telefono ~ '^[0-9]{8,15}$'),
  constraint fidelidad_intentos_ip_largo_chk
    check (ip is null or char_length(ip) <= 100)
);

create index if not exists fidelidad_intentos_telefono_fecha_idx
  on public.fidelidad_intentos (telefono, creado_en desc);
create index if not exists fidelidad_intentos_ip_fecha_idx
  on public.fidelidad_intentos (ip, creado_en desc);
create index if not exists fidelidad_intentos_fecha_idx
  on public.fidelidad_intentos (creado_en desc);

comment on table public.fidelidad_intentos is
  'Intentos de consulta de premios/progreso para el limite anti-spam. Sin acceso publico.';

alter table public.fidelidad_intentos enable row level security;
revoke all on public.fidelidad_intentos from public, anon, authenticated;

-- Registra el intento y devuelve false si se superaron los limites.
-- Umbrales (ajustables): 10 por telefono y 30 por IP cada 10 minutos,
-- 100 globales cada 5 minutos.
create or replace function public.pm_fidelidad_antispam(p_tel text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ip text;
  v_n integer;
begin
  begin
    v_ip := nullif(btrim(split_part(
      coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''),
      ',', 1)), '');
    if v_ip is null then
      v_ip := nullif(btrim(
        current_setting('request.headers', true)::jsonb ->> 'x-real-ip'), '');
    end if;
  exception when others then
    v_ip := null;
  end;
  v_ip := left(v_ip, 100);

  -- Limpieza de intentos de mas de 1 dia.
  delete from public.fidelidad_intentos
   where creado_en < now() - interval '1 day';

  select count(*) into v_n
    from public.fidelidad_intentos
   where telefono = p_tel and creado_en > now() - interval '10 minutes';
  if v_n >= 10 then
    return false;
  end if;

  if v_ip is not null then
    select count(*) into v_n
      from public.fidelidad_intentos
     where ip = v_ip and creado_en > now() - interval '10 minutes';
    if v_n >= 30 then
      return false;
    end if;
  end if;

  select count(*) into v_n
    from public.fidelidad_intentos
   where creado_en > now() - interval '5 minutes';
  if v_n >= 100 then
    return false;
  end if;

  insert into public.fidelidad_intentos (telefono, ip) values (p_tel, v_ip);
  return true;
end;
$$;

revoke all on function public.pm_fidelidad_antispam(text) from public, anon, authenticated;

-- Nombre del producto desde la carta (null si no existe).
create or replace function public.pm_fidelidad_nombre_producto(p_producto_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.value ->> 'nombre'
    from public.carta c
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(c.contenido -> 'productos') = 'array'
           then c.contenido -> 'productos' else '[]'::jsonb end
    ) as e(value)
   where c.id = 1
     and e.value ->> 'id' = p_producto_id
   limit 1;
$$;

revoke all on function public.pm_fidelidad_nombre_producto(text) from public, anon, authenticated;

-- mis_premios: SOLO premios no usados y no vencidos del telefono consultado.
-- Nunca devuelve nombre, historial ni datos personales.
create or replace function public.mis_premios(p_telefono text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_lista jsonb;
begin
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');

  if v_tel !~ '^[0-9]{8,15}$' or not public.pm_fidelidad_antispam(v_tel) then
    return jsonb_build_object(
      'ok', false,
      'mensaje', 'No pudimos consultar tus premios. Probá de nuevo en unos minutos.');
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', p.id,
             'tipo', p.tipo,
             'valor', p.valor,
             'tope_en_pesos', p.tope_en_pesos,
             'producto_nombre', case when p.tipo = 'producto_gratis'
                                     then public.pm_fidelidad_nombre_producto(p.producto_id) end,
             'vencimiento', p.vencimiento
           ) order by p.vencimiento, p.creado_en
         ), '[]'::jsonb)
    into v_lista
    from public.premios p
   where p.telefono = v_tel
     and not p.usado
     and p.vencimiento > now();

  return jsonb_build_object('ok', true, 'premios', v_lista);
exception when others then
  return jsonb_build_object(
    'ok', false,
    'mensaje', 'No pudimos consultar tus premios. Probá de nuevo en unos minutos.');
end;
$$;

revoke all on function public.mis_premios(text) from public, anon, authenticated;
grant execute on function public.mis_premios(text) to anon, authenticated;

comment on function public.mis_premios(text) is
  'Premios disponibles de un telefono. Con anti-spam y mensaje de error generico.';

-- mi_progreso_fidelidad: avance dentro del ciclo. Un telefono inexistente
-- devuelve progreso 0 (no revela si existe).
create or replace function public.mi_progreso_fidelidad(p_telefono text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_cfg jsonb;
  v_ciclo integer;
  v_n integer;
  v_pos integer;
  v_sig jsonb;
  v_faltan integer;
begin
  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');

  if v_tel !~ '^[0-9]{8,15}$' or not public.pm_fidelidad_antispam(v_tel) then
    return jsonb_build_object(
      'ok', false,
      'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
  end if;

  v_cfg := public.pm_fidelidad_config();
  if v_cfg is null then
    return jsonb_build_object(
      'ok', true, 'activo', false, 'pedidos_en_ciclo', 0,
      'faltan_para_proximo', null, 'proximo_premio', null);
  end if;

  v_ciclo := (v_cfg ->> 'ciclo')::integer;

  select coalesce(
           (select c.fidelidad_pedidos from public.clientes c where c.telefono = v_tel), 0)
    into v_n;
  v_pos := v_n % v_ciclo;

  -- Proximo nivel dentro del ciclo; si no queda ninguno, el primero del ciclo siguiente.
  select e.value into v_sig
    from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
   where (e.value ->> 'en')::integer > v_pos
   order by (e.value ->> 'en')::integer
   limit 1;

  if v_sig is not null then
    v_faltan := (v_sig ->> 'en')::integer - v_pos;
  else
    select e.value into v_sig
      from jsonb_array_elements(v_cfg -> 'niveles') as e(value)
     order by (e.value ->> 'en')::integer
     limit 1;
    v_faltan := v_ciclo - v_pos + (v_sig ->> 'en')::integer;
  end if;

  return jsonb_build_object(
    'ok', true,
    'activo', true,
    'pedidos_en_ciclo', v_pos,
    'faltan_para_proximo', v_faltan,
    'proximo_premio', jsonb_build_object(
      'tipo', v_sig ->> 'tipo',
      'valor', case when v_sig ->> 'tipo' = 'descuento_porcentaje'
                    then (v_sig ->> 'valor')::numeric end,
      'producto', case when v_sig ->> 'tipo' = 'producto_gratis'
                       then public.pm_fidelidad_nombre_producto(v_sig ->> 'producto_id') end
    )
  );
exception when others then
  return jsonb_build_object(
    'ok', false,
    'mensaje', 'No pudimos consultar tu progreso. Probá de nuevo en unos minutos.');
end;
$$;

revoke all on function public.mi_progreso_fidelidad(text) from public, anon, authenticated;
grant execute on function public.mi_progreso_fidelidad(text) to anon, authenticated;

comment on function public.mi_progreso_fidelidad(text) is
  'Progreso del ciclo de fidelidad de un telefono. Anti-spam y error generico.';

-- ----------------------------------------------------------------------------
-- 7. Item de regalo para premios de producto gratis
-- ----------------------------------------------------------------------------
-- Valida que el producto exista y este disponible en la sucursal (mismas reglas
-- que pm_calcular_pedido) y arma el item de snapshot a $0 con regalo = true.
create or replace function public.pm_fidelidad_item_regalo(
  p_producto_id text,
  p_sucursal_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_productos jsonb;
  v_prod jsonb;
  v_var jsonb;
  v_var_snap jsonb := null;
  v_hoy text := to_char(timezone('America/Argentina/Buenos_Aires', now()), 'YYYY-MM-DD');
begin
  select contenido -> 'productos' into v_productos from public.carta where id = 1;
  if v_productos is null or jsonb_typeof(v_productos) <> 'array' then
    raise exception 'La carta no está disponible en este momento.';
  end if;

  select e.value into v_prod
    from jsonb_array_elements(v_productos) as e(value)
   where e.value ->> 'id' = p_producto_id
   limit 1;
  if v_prod is null then
    raise exception 'El producto del premio ya no existe en la carta.';
  end if;

  if v_prod ->> 'agotado' = 'true'
     and (v_prod ->> 'agotado_hasta_nuevo_aviso' = 'true' or v_prod ->> 'agotado_fecha' = v_hoy) then
    raise exception '"%" está agotado.', v_prod ->> 'nombre';
  end if;

  if exists (
    select 1 from public.agotados_sucursal a
     where a.producto_id = (v_prod ->> 'id')
       and a.sucursal_id = p_sucursal_id
  ) then
    raise exception '"%" está agotado en esta sucursal.', v_prod ->> 'nombre';
  end if;

  if not coalesce((v_prod -> 'sucursales') ? p_sucursal_id, false) then
    raise exception '"%" no está disponible en esta sucursal.', v_prod ->> 'nombre';
  end if;

  -- Variacion obligatoria (ej. Cheeseburger): se regala la SIMPLE, o en su
  -- defecto la primera opcion de precio 0.
  if jsonb_typeof(v_prod -> 'variaciones' -> 'opciones') = 'array' then
    select e.value into v_var
      from jsonb_array_elements(v_prod -> 'variaciones' -> 'opciones') as e(value)
     where upper(btrim(e.value ->> 'nombre')) = 'SIMPLE'
     limit 1;
    if v_var is null then
      select e.value into v_var
        from jsonb_array_elements(v_prod -> 'variaciones' -> 'opciones') as e(value)
       where coalesce((e.value ->> 'precio')::numeric, 0) = 0
       limit 1;
    end if;
    if v_var is not null then
      v_var_snap := jsonb_build_object('id', v_var ->> 'id', 'nombre', v_var ->> 'nombre');
    end if;
  end if;

  return jsonb_build_object(
    'producto_id', v_prod ->> 'id',
    'nombre', v_prod ->> 'nombre',
    'categoria', coalesce(v_prod ->> 'categoria', ''),
    'precio_regular', 0,
    'precio_base', 0,
    'en_oferta', false,
    'variacion', v_var_snap,
    'adicionales', '[]'::jsonb,
    'cantidad', 1,
    'precio_unitario', 0,
    'subtotal', 0,
    'regalo', true);
end;
$$;

revoke all on function public.pm_fidelidad_item_regalo(text, text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8. crear_pedido con premio (14 argumentos)
-- ----------------------------------------------------------------------------
-- Se elimina la firma de 13 argumentos (018) para que PostgREST no vea dos
-- funciones ambiguas. El cuerpo es el de 018; los unicos cambios son los de
-- fidelidad (marcados con "019").
drop function if exists public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text);

create or replace function public.crear_pedido(
  p_sucursal_id      text,
  p_modalidad        text,
  p_metodo_pago      text,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_items            jsonb,
  p_direccion        text default null,
  p_lat              numeric default null,
  p_lng              numeric default null,
  p_zona_envio       text default null,
  p_notas            text default null,
  p_idempotency_key  uuid default null,
  p_cupon            text default null,
  p_premio_id        uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ped public.pedidos%rowtype;
  v_calc jsonb;
  v_nombre text;
  v_tel text;
  v_dir text;
  v_notas text;
  v_lat numeric := p_lat;
  v_lng numeric := p_lng;

  v_codigo text;
  v_cupon_res jsonb;
  v_subtotal numeric := 0;
  v_envio numeric := 0;
  v_desc_pago numeric := 0;
  v_desc_cupon numeric := 0;
  v_desc_final numeric := 0;
  v_cupon_aplicado boolean := false;
  v_acumulable boolean := false;
  v_total numeric := 0;

  v_items jsonb;                            -- 019
  v_premio public.premios%rowtype;          -- 019
  v_premio_aplicado boolean := false;       -- 019
begin
  -- Reintento del mismo pedido: devuelve el que ya existe
  if p_idempotency_key is not null then
    select * into v_ped from public.pedidos where idempotency_key = p_idempotency_key;
    if found then
      return public.pm_pedido_resultado(v_ped);
    end if;
  end if;

  v_nombre := btrim(coalesce(p_cliente_nombre, ''));
  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then
    raise exception 'Ingresá tu nombre.';
  end if;

  v_tel := regexp_replace(coalesce(p_cliente_telefono, ''), '\D', '', 'g');
  if v_tel !~ '^[0-9]{8,15}$' then
    raise exception 'El teléfono no es válido.';
  end if;

  -- 019: un solo beneficio por pedido.
  if p_premio_id is not null and btrim(coalesce(p_cupon, '')) <> '' then
    raise exception 'No podés usar un premio y un cupón en el mismo pedido.';
  end if;

  if p_modalidad = 'delivery' then
    v_dir := btrim(coalesce(p_direccion, ''));
    if char_length(v_dir) < 5 or char_length(v_dir) > 300 then
      raise exception 'Falta la dirección de entrega.';
    end if;
    if (v_lat is null) <> (v_lng is null)
       or v_lat not between -90 and 90 or v_lng not between -180 and 180 then
      v_lat := null;
      v_lng := null;
    end if;
  else
    v_dir := null;
    v_lat := null;
    v_lng := null;
  end if;

  v_notas := left(btrim(coalesce(p_notas, '')), 500);

  -- Anti-spam (ajustable): por telefono y global
  if (select count(*) from public.pedidos
       where cliente_telefono = v_tel and created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'Hiciste varios pedidos seguidos. Esperá unos minutos o escribinos por WhatsApp.';
  end if;
  if (select count(*) from public.pedidos
       where created_at > now() - interval '5 minutes') >= 40 then
    raise exception 'Hay muchos pedidos en este momento. Escribinos por WhatsApp.';
  end if;

  v_calc := public.pm_calcular_pedido(
    p_sucursal_id, p_modalidad, p_metodo_pago, p_items, p_zona_envio, v_lat, v_lng);

  v_subtotal := coalesce((v_calc ->> 'subtotal')::numeric, 0);
  v_envio := coalesce((v_calc ->> 'costo_envio')::numeric, 0);
  v_desc_pago := coalesce((v_calc ->> 'descuento')::numeric, 0);
  v_desc_final := v_desc_pago;
  v_items := v_calc -> 'items';             -- 019

  -- 019: canje de premio. Se bloquea la fila del premio hasta el commit, lo
  -- que serializa canjes simultaneos del mismo premio. Solo se acepta si es
  -- del telefono del pedido, no esta usado y no vencio. Con premio se ignoran
  -- el cupon y el descuento por medio de pago.
  if p_premio_id is not null then
    select * into v_premio
      from public.premios
     where id = p_premio_id
       and telefono = v_tel
     for update;
    if not found then
      raise exception 'El premio no es válido.';
    end if;
    if v_premio.usado then
      raise exception 'Este premio ya fue usado.';
    end if;
    if v_premio.vencimiento <= now() then
      raise exception 'Este premio está vencido.';
    end if;

    if v_premio.tipo = 'descuento_porcentaje' then
      -- Sobre el subtotal de productos (sin envio), con tope si existe.
      v_desc_final := round(v_subtotal * v_premio.valor / 100);
      if v_premio.tope_en_pesos is not null then
        v_desc_final := least(v_desc_final, v_premio.tope_en_pesos);
      end if;
      v_desc_final := least(greatest(v_desc_final, 0), v_subtotal);
    else
      -- Producto gratis: item a $0; el subtotal pagado no cambia.
      v_desc_final := 0;
      v_items := v_items || jsonb_build_array(
        public.pm_fidelidad_item_regalo(v_premio.producto_id, p_sucursal_id));
    end if;

    v_premio_aplicado := true;
  end if;

  -- Re-validacion del cupon dentro de la misma transaccion.
  -- Se ignora cualquier descuento que venga del cliente.
  v_codigo := upper(btrim(coalesce(p_cupon, '')));

  if v_codigo <> '' then
    v_cupon_res := public.pm_validar_cupon(
      v_codigo, v_tel, v_subtotal, p_sucursal_id, p_modalidad, true);

    if not coalesce((v_cupon_res ->> 'ok')::boolean, false) then
      raise exception '%', v_cupon_res ->> 'mensaje';
    end if;

    v_desc_cupon := coalesce((v_cupon_res ->> 'descuento')::numeric, 0);
    v_acumulable := coalesce((v_cupon_res ->> 'acumulable')::boolean, false);

    if v_acumulable then
      -- Se suman, pero el cupon nunca descuenta mas que lo que queda
      -- despues del descuento por medio de pago.
      v_desc_cupon := least(v_desc_cupon, greatest(v_subtotal - v_desc_pago, 0));
      v_desc_final := v_desc_pago + v_desc_cupon;
      v_cupon_aplicado := v_desc_cupon > 0;
    elsif v_desc_cupon >= v_desc_pago then
      -- Gana el cupon.
      v_desc_final := v_desc_cupon;
      v_cupon_aplicado := v_desc_cupon > 0;
    else
      -- Gana el medio de pago: el cupon no se consume ni se registra.
      v_desc_cupon := 0;
      v_desc_final := v_desc_pago;
      v_cupon_aplicado := false;
    end if;

    v_desc_final := least(v_desc_final, v_subtotal);
  end if;

  v_total := v_subtotal - v_desc_final + v_envio;

  begin
    insert into public.pedidos (
      sucursal_id, modalidad, cliente_nombre, cliente_telefono,
      direccion, lat, lng, zona_envio, items_snapshot,
      subtotal, descuento, costo_envio, total,
      metodo_pago, idempotency_key, notas,
      cupon_codigo, descuento_cupon,
      premio_id
    ) values (
      p_sucursal_id, p_modalidad, v_nombre, v_tel,
      v_dir, v_lat, v_lng, v_calc ->> 'zona_envio', v_items,
      v_subtotal, v_desc_final, v_envio, v_total,
      p_metodo_pago, p_idempotency_key, nullif(v_notas, ''),
      case when v_cupon_aplicado then v_codigo else null end,
      case when v_cupon_aplicado then v_desc_cupon else 0 end,
      case when v_premio_aplicado then v_premio.id else null end
    )
    returning * into v_ped;
  exception when unique_violation then
    if p_idempotency_key is not null then
      select * into v_ped from public.pedidos where idempotency_key = p_idempotency_key;
      if found then
        return public.pm_pedido_resultado(v_ped);
      end if;
    end if;
    raise;
  end;

  -- Registrar el uso en la misma transaccion. La fila del cupon quedo
  -- bloqueada con FOR UPDATE hasta el commit, lo que serializa usos
  -- simultaneos sobre el mismo codigo.
  if v_cupon_aplicado then
    insert into public.cupon_usos (
      cupon_id, telefono, pedido_id, monto_descontado
    ) values (
      (v_cupon_res ->> 'cupon_id')::uuid,
      v_tel,
      v_ped.id,
      v_desc_cupon
    );
  end if;

  -- 019: marcar el premio como usado en la misma transaccion (la fila sigue
  -- bloqueada desde el FOR UPDATE).
  if v_premio_aplicado then
    update public.premios
       set usado = true,
           usado_en = now(),
           pedido_id = v_ped.id
     where id = v_premio.id;
  end if;

  return public.pm_pedido_resultado(v_ped);
end;
$$;

-- Permisos de crear_pedido: exactamente como en 013/018, para la nueva firma.
revoke all on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid)
  from public;
grant execute on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid)
  to anon, authenticated;

comment on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid) is
  'Crea un pedido validando precios, cupon y premio en el servidor. Ignora totales y descuentos del cliente.';

-- ----------------------------------------------------------------------------
-- 9. Casos de prueba (comentados; ejecutar a mano en un entorno de prueba)
-- ----------------------------------------------------------------------------
-- Preparacion: usar un telefono de prueba (T) y crear los pedidos con
-- crear_pedido (productos que sumen >= $10.000 de subtotal). "Entregar" =
--   update public.pedidos set estado = 'entregado' where id = '<pedido>';
-- Verificar el contador con:
--   select fidelidad_pedidos from public.clientes where telefono = 'T';
--   select tipo, valor, producto_id, vencimiento, usado
--     from public.premios where telefono = 'T' order by creado_en;
--
-- a) 4 pedidos entregados NO generan premio:
--    entregar 4 pedidos -> fidelidad_pedidos = 4, premios = 0.
-- b) El 5.o genera 30%:
--    entregar el 5.o -> 1 premio descuento_porcentaje, valor 30,
--    tope_en_pesos null, vencimiento ~ now() + 30 dias.
-- c) El 10.o genera la Cheeseburger:
--    entregar hasta el 10.o -> 1 premio producto_gratis,
--    producto_id 'burger_cheeseburger'.
-- d) El 11.o reinicia el ciclo:
--    entregar el 11.o -> fidelidad_pedidos = 11, sin premios nuevos;
--    select public.mi_progreso_fidelidad('T');
--    -> pedidos_en_ciclo = 1, faltan_para_proximo = 4 (el proximo es el 15.o).
--    Entregar hasta el 15.o -> nuevo 30%; hasta el 20.o -> nueva Cheeseburger.
-- e) Pedido de $9.000 (subtotal < 10.000) NO cuenta:
--    crear un pedido con subtotal 9000, entregarlo -> fidelidad_pedidos no
--    cambia y fidelidad_contado sigue en false.
-- f) Pedido no sincronizado NO cuenta:
--    update public.pedidos set sincronizado = false where id = '<pedido>';
--    entregarlo -> fidelidad_pedidos no cambia.
-- g) Cambiar el estado dos veces no suma doble:
--    entregar un pedido, pasarlo a 'listo' y volver a 'entregado' ->
--    fidelidad_pedidos suma 1 una sola vez (fidelidad_contado = true).
-- h) Premio vencido se rechaza en crear_pedido:
--    update public.premios set vencimiento = now() - interval '1 day' where id = '<premio>';
--    select public.crear_pedido(..., p_premio_id => '<premio>');
--    -> error 'Este premio está vencido.' (y mis_premios no lo lista).
-- i) Premio de otro telefono se rechaza:
--    crear_pedido con el telefono T2 y p_premio_id de T
--    -> error 'El premio no es válido.' (mismo mensaje que un id inexistente).
-- j) Premio + cupon se rechaza:
--    crear_pedido(..., p_cupon => 'LICHI', p_premio_id => '<premio>')
--    -> error 'No podés usar un premio y un cupón en el mismo pedido.'
-- k) Canje del 30% y de la Cheeseburger:
--    30%: pedidos.descuento = round(subtotal * 0.30), total = subtotal - descuento
--    + envio, sin descuento por pago ni cupon; premio usado = true y
--    premios.pedido_id = pedido. Cheeseburger: items_snapshot lleva un item con
--    regalo = true, precio_unitario 0, subtotal 0, variacion {id,nombre} SIMPLE;
--    subtotal y total no cambian por el regalo.
-- l) Cancelar libera el premio:
--    update public.pedidos set estado = 'cancelado' where id = '<pedido con premio>';
--    -> premios.usado = false, usado_en null, pedido_id null (si no vencio).
--    Si el premio ya vencio, queda usado = true.
-- m) Doble canje simultaneo (solo uno pasa): abrir dos sesiones.
--    Sesion A: begin; select public.crear_pedido(..., p_premio_id => '<premio>');  (sin commit)
--    Sesion B: select public.crear_pedido(..., p_premio_id => '<premio>');  (queda esperando)
--    Sesion A: commit;
--    -> B falla con 'Este premio ya fue usado.' Un solo pedido con el premio.
-- n) mis_premios no devuelve datos personales:
--    select public.mis_premios('T');
--    -> {"ok": true, "premios": [{id, tipo, valor, tope_en_pesos,
--       producto_nombre, vencimiento}]}: sin nombre, telefono ni historial.
--    select public.mis_premios('00000000');  -> {"ok": true, "premios": []}
--    select public.mis_premios('abc');       -> mensaje generico (ok = false).
-- o) Anti-spam: llamar mis_premios 11 veces seguidas con el mismo telefono ->
--    la 11.a devuelve el mensaje generico. fidelidad_intentos no es accesible
--    para anon ni authenticated.
-- p) Config invalida -> programa inactivo:
--    update public.config_negocio set valor = '{"activo": true}' where clave = 'fidelidad';
--    entregar un pedido -> no cuenta; mi_progreso_fidelidad -> activo = false.
--    (restaurar el valor original despues de probar)
-- q) Permisos: con rol anon, select * from public.premios -> sin acceso;
--    como admin de sucursal (no dueno) -> 0 filas; como dueno -> ve todos.

-- ----------------------------------------------------------------------------
-- 10. ROLLBACK (comentado; ejecutar a mano solo si hace falta)
-- ----------------------------------------------------------------------------
-- Restaura crear_pedido de 13 argumentos tomando el CREATE FUNCTION de
-- 018_cupones.sql (seccion 6) y la funcion del trigger de
-- 010_fase1_tablas_pedidos.sql (seccion 7). Antes: backup.
--
-- begin;
--   drop trigger if exists pedidos_liberar_premio on public.pedidos;
--   drop function if exists public.pm_pedidos_liberar_premio();
--
--   drop function if exists public.crear_pedido(
--     text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid);
--   -- >>> volver a ejecutar aca el create or replace function public.crear_pedido(...)
--   -- >>> de 13 argumentos de 018_cupones.sql, mas sus revoke/grant/comment.
--
--   -- >>> volver a ejecutar aca el create or replace function
--   -- >>> public.pm_pedidos_actualizar_clientes() de 010_fase1_tablas_pedidos.sql.
--
--   drop function if exists public.mi_progreso_fidelidad(text);
--   drop function if exists public.mis_premios(text);
--   drop function if exists public.pm_fidelidad_item_regalo(text, text);
--   drop function if exists public.pm_fidelidad_nombre_producto(text);
--   drop function if exists public.pm_fidelidad_antispam(text);
--   drop function if exists public.pm_fidelidad_acreditar(public.pedidos);
--   drop function if exists public.pm_fidelidad_config();
--   drop table if exists public.fidelidad_intentos;
--
--   alter table public.pedidos drop column if exists premio_id;
--   alter table public.pedidos drop column if exists fidelidad_contado;
--   drop table if exists public.premios;
--
--   alter table public.clientes drop constraint if exists clientes_fidelidad_pedidos_chk;
--   alter table public.clientes drop column if exists fidelidad_pedidos;
--
--   delete from public.config_negocio where clave = 'fidelidad';
-- commit;
