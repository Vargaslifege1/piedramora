-- ============================================================================
-- 023_normalizar_telefonos.sql
-- Normaliza los telefonos argentinos a 10 digitos (codigo de area + numero,
-- sin 0, sin 15, sin 54, sin 9). Ej.: 3834818271
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP COMPLETO de la base (Supabase > Database >
-- Backups, o pg_dump). Esta migracion MODIFICA DATOS (clientes, pedidos,
-- premios, cupon_usos y tablas de intentos) y la fusion de clientes
-- duplicados NO se puede revertir sin el backup.
--
-- Prerrequisitos (ya aplicadas): 010, 018, 019, 020, 021, 022.
-- No se modifica ninguna migracion anterior; las funciones se redefinen con
-- CREATE OR REPLACE partiendo de su version ACTUAL (cambia SOLO la
-- normalizacion del telefono; las firmas no cambian, no hay DROP):
--   crear_pedido (020), registrar_cliente (020), borrar_mis_datos (020),
--   mis_premios (019), mi_progreso_fidelidad (019),
--   valida_cupon (018), pm_validar_cupon (018).
-- Los permisos (grants/revokes) se conservan con CREATE OR REPLACE.
--
-- Que hace:
--   1. pm_normalizar_telefono(text): IMMUTABLE, devuelve 10 digitos o null.
--   2. Redefine las 7 funciones para usarla (null => se rechaza).
--   3. Cambia los checks ^[0-9]{8,15}$ por ^[0-9]{10}$ (primero NOT VALID).
--   4. Migra los datos existentes (fusiona clientes duplicados) con el
--      trigger pedidos_actualizar_clientes deshabilitado solo durante el
--      UPDATE masivo, verifica que los totales no cambien y lo rehabilita.
--   5. VALIDATE de los checks que no tengan filas invalidas.
--   Todo en UNA transaccion: si algo falla, no queda nada a medias.
--
-- Registros que no se pueden normalizar: NO se tocan. Ver el SELECT de
-- revision comentado al final. Los registros de las tablas *_intentos
-- (anti-spam, se limpian solos) con telefono invalido SI se borran.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. pm_normalizar_telefono
-- ----------------------------------------------------------------------------
-- Reglas (en orden): solo digitos; quita 54 inicial (si sobran digitos);
-- si quedan 11 y empieza con 9, lo quita; quita 0 inicial; si quedan 12 con
-- "15" justo despues del codigo de area (2 digitos = 11, o 3/4 digitos),
-- quita el 15. Devuelve null si no quedan exactamente 10 digitos.
-- Es idempotente: normalizar un numero ya normalizado lo deja igual.
create or replace function public.pm_normalizar_telefono(p_tel text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := regexp_replace(coalesce(p_tel, ''), '\D', '', 'g');
begin
  if v like '54%' and char_length(v) > 10 then
    v := substr(v, 3);
  end if;
  if char_length(v) = 11 and v like '9%' then
    v := substr(v, 2);
  end if;
  if v like '0%' then
    v := substr(v, 2);
  end if;
  if char_length(v) = 12 then
    if substr(v, 1, 2) = '11' and substr(v, 3, 2) = '15' then
      v := substr(v, 1, 2) || substr(v, 5);
    elsif substr(v, 4, 2) = '15' then
      v := substr(v, 1, 3) || substr(v, 6);
    elsif substr(v, 5, 2) = '15' then
      v := substr(v, 1, 4) || substr(v, 7);
    end if;
  end if;
  if v ~ '^[0-9]{10}$' then
    return v;
  end if;
  return null;
end;
$$;

comment on function public.pm_normalizar_telefono(text) is
  'Normaliza un telefono argentino a 10 digitos (area + numero) o devuelve null (023).';

-- Solo la usan funciones SECURITY DEFINER; sin acceso directo.
revoke all on function public.pm_normalizar_telefono(text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Funciones (version actual + normalizacion nueva)
-- ----------------------------------------------------------------------------
-- pm_validar_cupon (base: 018_cupones.sql)
create or replace function public.pm_validar_cupon(
  p_codigo      text,
  p_telefono    text,
  p_subtotal    numeric,
  p_sucursal_id text,
  p_modalidad   text,
  p_bloquear    boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_codigo text;
  v_tel text;
  v_cupon public.cupones%rowtype;
  v_subtotal numeric;
  v_descuento numeric := 0;
  v_usos_total integer := 0;
  v_usos_cliente integer := 0;
  v_pedidos_previos integer := 0;
begin
  v_codigo := upper(btrim(coalesce(p_codigo, '')));
  if v_codigo = '' then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'El cupón no es válido.');
  end if;

  -- Misma normalizacion de telefono que usa crear_pedido desde 013.
  v_tel := public.pm_normalizar_telefono(p_telefono);
  if v_tel is null then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'Ingresá código de área y número, sin 0 ni 15 (ej. 3834818271).');
  end if;

  v_subtotal := greatest(coalesce(p_subtotal, 0), 0);

  -- El bloqueo se usa desde crear_pedido para evitar carreras con
  -- usos_maximos_total y usos_por_cliente.
  if p_bloquear then
    select * into v_cupon
      from public.cupones
     where codigo = v_codigo
     for update;
  else
    select * into v_cupon
      from public.cupones
     where codigo = v_codigo;
  end if;

  -- Mismo mensaje para codigo inexistente e inactivo/pausado.
  if v_cupon.id is null or v_cupon.activo is not true then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'El cupón no es válido.');
  end if;

  if v_cupon.fecha_inicio is not null and now() < v_cupon.fecha_inicio then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón todavía no está vigente.');
  end if;

  if v_cupon.fecha_vencimiento is not null and now() > v_cupon.fecha_vencimiento then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', 'Este cupón está vencido.');
  end if;

  if v_cupon.modalidades_permitidas is not null
     and (
       p_modalidad is null
       or not (p_modalidad = any (v_cupon.modalidades_permitidas))
     ) then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón no es válido para esta modalidad de entrega.');
  end if;

  if v_cupon.sucursales_permitidas is not null
     and (
       p_sucursal_id is null
       or not (p_sucursal_id = any (v_cupon.sucursales_permitidas))
     ) then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón no es válido para esta sucursal.');
  end if;

  if v_cupon.primera_compra then
    select count(*) into v_pedidos_previos
      from public.pedidos p
     where p.cliente_telefono = v_tel
       and p.estado <> 'cancelado'
       and p.sincronizado is distinct from false;

    if v_pedidos_previos > 0 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Este cupón es solo para la primera compra.');
    end if;
  end if;

  if v_subtotal < v_cupon.compra_minima then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', format(
        'El mínimo de compra es $%s; te faltan $%s.',
        replace(trim(to_char(round(v_cupon.compra_minima), 'FM999,999,999,999')), ',', '.'),
        replace(trim(to_char(round(v_cupon.compra_minima - v_subtotal), 'FM999,999,999,999')), ',', '.')));
  end if;

  -- Usos validos: solo pedidos que no estan cancelados.
  select count(*) into v_usos_total
    from public.cupon_usos u
    join public.pedidos p on p.id = u.pedido_id
   where u.cupon_id = v_cupon.id
     and p.estado <> 'cancelado';

  if v_cupon.usos_maximos_total is not null
     and v_usos_total >= v_cupon.usos_maximos_total then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Este cupón ya no tiene usos disponibles.');
  end if;

  select count(*) into v_usos_cliente
    from public.cupon_usos u
    join public.pedidos p on p.id = u.pedido_id
   where u.cupon_id = v_cupon.id
     and u.telefono = v_tel
     and p.estado <> 'cancelado';

  if v_cupon.usos_por_cliente is not null
     and v_usos_cliente >= v_cupon.usos_por_cliente then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Ya usaste este cupón.');
  end if;

  if v_cupon.tipo = 'porcentaje' then
    v_descuento := round(v_subtotal * v_cupon.valor / 100);
  else
    v_descuento := round(v_cupon.valor);
  end if;

  v_descuento := least(greatest(v_descuento, 0), v_subtotal);

  return jsonb_build_object(
    'ok', true,
    'descuento', v_descuento,
    'mensaje', 'Cupón aplicado.',
    'cupon_id', v_cupon.id,
    'acumulable', v_cupon.acumulable_con_pago);
end;
$$;

-- valida_cupon (base: 018_cupones.sql)
create or replace function public.valida_cupon(
  p_codigo      text,
  p_telefono    text,
  p_subtotal    numeric,
  p_sucursal_id text,
  p_modalidad   text,
  p_metodo_pago text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ip text;
  v_tel text;
  v_intentos_tel integer := 0;
  v_intentos_ip integer := 0;
  v_intentos_global integer := 0;
  v_subtotal numeric;
  v_res jsonb;
  v_desc_cupon numeric := 0;
  v_desc_pago numeric := 0;
  v_pagos jsonb;
  v_pct numeric := 0;
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);
  v_subtotal := greatest(coalesce(p_subtotal, 0), 0);

  -- IP del pedido (detras del proxy de Supabase).
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

  -- Limpieza de intentos de mas de 1 dia.
  delete from public.cupon_intentos
   where creado_en < now() - interval '1 day';

  -- Limite anti-spam con los mismos umbrales base que crear_pedido,
  -- mas un limite por IP.
  if v_tel is not null then
    select count(*) into v_intentos_tel
      from public.cupon_intentos
     where telefono = v_tel
       and creado_en > now() - interval '10 minutes';

    if v_intentos_tel >= 5 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Hiciste varios intentos seguidos. Esperá unos minutos.');
    end if;
  end if;

  if v_ip is not null then
    select count(*) into v_intentos_ip
      from public.cupon_intentos
     where ip = v_ip
       and creado_en > now() - interval '10 minutes';

    if v_intentos_ip >= 20 then
      return jsonb_build_object(
        'ok', false, 'descuento', 0,
        'mensaje', 'Hiciste varios intentos seguidos. Esperá unos minutos.');
    end if;
  end if;

  select count(*) into v_intentos_global
    from public.cupon_intentos
   where creado_en > now() - interval '5 minutes';

  if v_intentos_global >= 40 then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'Hay muchos intentos en este momento. Esperá unos minutos.');
  end if;

  insert into public.cupon_intentos (telefono, ip, codigo)
  values (
    case when v_tel is not null then v_tel else null end,
    v_ip,
    left(upper(btrim(coalesce(p_codigo, ''))), 40)
  );

  v_res := public.pm_validar_cupon(
    p_codigo, p_telefono, v_subtotal, p_sucursal_id, p_modalidad, false);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'descuento', 0,
      'mensaje', v_res ->> 'mensaje');
  end if;

  v_desc_cupon := coalesce((v_res ->> 'descuento')::numeric, 0);

  -- Descuento por medio de pago, con la misma formula que pm_calcular_pedido.
  select valor into v_pagos
    from public.config_negocio
   where clave = 'descuentos_pago';

  if v_pagos is not null
     and jsonb_typeof(v_pagos -> p_metodo_pago) = 'number' then
    v_pct := least(100, greatest(0, (v_pagos ->> p_metodo_pago)::numeric));
  end if;

  v_desc_pago := round(v_subtotal * v_pct / 100);

  -- Regla de beneficio unico (opcion A).
  if coalesce((v_res ->> 'acumulable')::boolean, false) then
    return jsonb_build_object(
      'ok', true,
      'descuento', least(v_subtotal, v_desc_cupon),
      'mensaje', 'Cupón aplicado.');
  end if;

  if v_desc_cupon >= v_desc_pago then
    return jsonb_build_object(
      'ok', true,
      'descuento', least(v_subtotal, v_desc_cupon),
      'mensaje', 'Cupón aplicado.');
  end if;

  return jsonb_build_object(
    'ok', false,
    'descuento', 0,
    'mensaje', 'Con ese medio de pago ya tenés un descuento mayor; el cupón no se aplica.');
end;
$$;

-- mis_premios (base: 019_fidelidad_premios.sql)
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
  v_tel := public.pm_normalizar_telefono(p_telefono);

  if v_tel is null or not public.pm_fidelidad_antispam(v_tel) then
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

-- mi_progreso_fidelidad (base: 019_fidelidad_premios.sql)
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
  v_tel := public.pm_normalizar_telefono(p_telefono);

  if v_tel is null or not public.pm_fidelidad_antispam(v_tel) then
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

-- registrar_cliente (base: 020_registro_clientes.sql)
create or replace function public.registrar_cliente(
  p_nombre        text,
  p_apellido      text,
  p_telefono      text,
  p_acepta_promos boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_nombre text;
  v_apellido text;
  v_acepta boolean := coalesce(p_acepta_promos, false);
  v_cli public.clientes%rowtype;
  v_pidio boolean;
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);
  v_nombre := btrim(coalesce(p_nombre, ''));
  v_apellido := btrim(coalesce(p_apellido, ''));

  if v_tel is null
     or char_length(v_nombre) not between 2 and 60
     or char_length(v_apellido) not between 2 and 60
     or not public.pm_registro_antispam(v_tel) then
    return jsonb_build_object(
      'ok', false,
      'mensaje', 'No pudimos completar el registro. Probá de nuevo en unos minutos.');
  end if;

  insert into public.clientes (
    telefono, nombre, apellido,
    acepta_promos, acepta_promos_en, registrado_en, origen
  ) values (
    v_tel, v_nombre, v_apellido,
    v_acepta, case when v_acepta then now() end, now(), 'registro'
  )
  on conflict (telefono) do nothing;

  if found then
    return jsonb_build_object('ok', true);
  end if;

  -- Ya existia: se bloquea la fila para serializar con el trigger de pedidos.
  select * into v_cli
    from public.clientes
   where telefono = v_tel
   for update;

  v_pidio := v_cli.cantidad_pedidos_entregados > 0
             or exists (select 1 from public.pedidos p where p.cliente_telefono = v_tel);

  update public.clientes c
     set nombre = case when v_pidio then c.nombre else v_nombre end,
         apellido = case when v_pidio
                         then coalesce(nullif(btrim(c.apellido), ''), v_apellido)
                         else v_apellido end,
         registrado_en = coalesce(c.registrado_en, now()),
         acepta_promos = c.acepta_promos or v_acepta,
         acepta_promos_en = case when not c.acepta_promos and v_acepta
                                 then now() else c.acepta_promos_en end
   where c.telefono = v_tel;

  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object(
    'ok', false,
    'mensaje', 'No pudimos completar el registro. Probá de nuevo en unos minutos.');
end;
$$;

-- borrar_mis_datos (base: 020_registro_clientes.sql)
create or replace function public.borrar_mis_datos(p_telefono text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_cli public.clientes%rowtype;
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);

  if v_tel is null or not public.pm_registro_antispam(v_tel) then
    return jsonb_build_object(
      'ok', false,
      'mensaje', 'No pudimos completar la solicitud. Probá de nuevo en unos minutos.');
  end if;

  select * into v_cli
    from public.clientes
   where telefono = v_tel
   for update;

  if found then
    update public.clientes
       set acepta_promos = false,
           acepta_promos_en = null
     where telefono = v_tel;

    if v_cli.cantidad_pedidos_entregados = 0
       and not exists (select 1 from public.pedidos p where p.cliente_telefono = v_tel) then
      delete from public.clientes where telefono = v_tel;
    end if;
  end if;

  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object(
    'ok', false,
    'mensaje', 'No pudimos completar la solicitud. Probá de nuevo en unos minutos.');
end;
$$;

-- crear_pedido (base: 020_registro_clientes.sql)
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
  p_premio_id        uuid default null,
  p_acepta_promos    boolean default null
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

  v_tel := public.pm_normalizar_telefono(p_cliente_telefono);
  if v_tel is null then
    raise exception 'Ingresá código de área y número, sin 0 ni 15 (ej. 3834818271).';
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

  -- 020: consentimiento de promos. Solo si viene true; null/false no cambian
  -- nada. Usa v_nombre (ya validado). Si el cliente existe, el on conflict NO
  -- toca nombre ni otras columnas: solo acepta_promos y su fecha.
  if p_acepta_promos is true then
    insert into public.clientes (
      telefono, nombre, acepta_promos, acepta_promos_en, origen
    ) values (
      v_tel, v_nombre, true, now(), 'pedido'
    )
    on conflict (telefono) do update
      set acepta_promos = true,
          acepta_promos_en = case when public.clientes.acepta_promos
                                  then public.clientes.acepta_promos_en
                                  else now() end;
  end if;

  return public.pm_pedido_resultado(v_ped);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Checks de telefono: 10 digitos (NOT VALID: rige para filas nuevas ya)
-- ----------------------------------------------------------------------------
alter table public.clientes drop constraint if exists clientes_telefono_chk;
alter table public.clientes add constraint clientes_telefono_chk
  check (telefono ~ '^[0-9]{10}$') not valid;

alter table public.pedidos drop constraint if exists pedidos_cliente_telefono_chk;
alter table public.pedidos add constraint pedidos_cliente_telefono_chk
  check (cliente_telefono ~ '^[0-9]{10}$') not valid;

alter table public.premios drop constraint if exists premios_telefono_chk;
alter table public.premios add constraint premios_telefono_chk
  check (telefono ~ '^[0-9]{10}$') not valid;

alter table public.cupon_usos drop constraint if exists cupon_usos_telefono_chk;
alter table public.cupon_usos add constraint cupon_usos_telefono_chk
  check (telefono ~ '^[0-9]{10}$') not valid;

alter table public.cupon_intentos drop constraint if exists cupon_intentos_telefono_chk;
alter table public.cupon_intentos add constraint cupon_intentos_telefono_chk
  check (telefono is null or telefono ~ '^[0-9]{10}$') not valid;

alter table public.fidelidad_intentos drop constraint if exists fidelidad_intentos_telefono_chk;
alter table public.fidelidad_intentos add constraint fidelidad_intentos_telefono_chk
  check (telefono is null or telefono ~ '^[0-9]{10}$') not valid;

alter table public.registro_intentos drop constraint if exists registro_intentos_telefono_chk;
alter table public.registro_intentos add constraint registro_intentos_telefono_chk
  check (telefono is null or telefono ~ '^[0-9]{10}$') not valid;

-- ----------------------------------------------------------------------------
-- 4. Migracion de datos
-- ----------------------------------------------------------------------------
-- 4.a Totales ANTES (para verificar al final que la fusion no pierde nada).
--     Solo clientes cuyo telefono se puede normalizar (los invalidos no se tocan).
create temp table pm_tel_totales_antes on commit drop as
select coalesce(sum(cantidad_pedidos_entregados), 0) as pedidos,
       coalesce(sum(monto_total_gastado), 0) as monto,
       coalesce(sum(fidelidad_pedidos), 0) as fidelidad
  from public.clientes
 where public.pm_normalizar_telefono(telefono) is not null;

-- 4.b Mapa telefono viejo -> nuevo (null si no se puede normalizar).
create temp table pm_tel_map on commit drop as
select t.tel as viejo, public.pm_normalizar_telefono(t.tel) as nuevo
  from (select telefono as tel from public.clientes
        union select cliente_telefono from public.pedidos
        union select telefono from public.premios
        union select telefono from public.cupon_usos
        union select telefono from public.cupon_intentos
        union select telefono from public.fidelidad_intentos
        union select telefono from public.registro_intentos) t
 where t.tel is not null;

-- 4.c Clientes: fusion de duplicados (mismo telefono normalizado).
--     Suma pedidos, monto y fidelidad; ultima_visita mas reciente;
--     acepta_promos = OR; nombre/apellido del que tenga mas pedidos.
--     Solo entran grupos con mas de un cliente o con telefono a cambiar.
create temp table pm_clientes_fusion on commit drop as
with g as (
  select m.nuevo,
         c.*,
         row_number() over (
           partition by m.nuevo
           order by c.cantidad_pedidos_entregados desc,
                    c.ultima_visita desc nulls last,
                    c.telefono) as rn
    from public.clientes c
    join pm_tel_map m on m.viejo = c.telefono
   where m.nuevo is not null
)
select nuevo as telefono,
       max(nombre) filter (where rn = 1) as nombre,
       coalesce(max(apellido) filter (where rn = 1), max(apellido)) as apellido,
       sum(cantidad_pedidos_entregados)::integer as cantidad_pedidos_entregados,
       sum(monto_total_gastado) as monto_total_gastado,
       max(ultima_visita) as ultima_visita,
       sum(fidelidad_pedidos)::integer as fidelidad_pedidos,
       bool_or(acepta_promos) as acepta_promos,
       min(acepta_promos_en) filter (where acepta_promos) as acepta_promos_en,
       min(registrado_en) as registrado_en,
       case when bool_or(origen = 'registro') then 'registro' else 'pedido' end as origen
  from g
 group by nuevo
having count(*) > 1 or bool_or(telefono <> nuevo);

-- 4.d UPDATE masivo con el trigger de contadores deshabilitado.
--     pedidos_actualizar_clientes se dispara al cambiar cliente_telefono y
--     duplicaria/restaria contadores; se rehabilita al terminar. Los demas
--     triggers de pedidos (liberar_premio, validar_estado) solo reaccionan a
--     cambios de estado, que aca no se tocan.
alter table public.pedidos disable trigger pedidos_actualizar_clientes;

delete from public.clientes c
 using pm_tel_map m
 where m.viejo = c.telefono
   and m.nuevo in (select f.telefono from pm_clientes_fusion f);

insert into public.clientes (
  telefono, nombre, apellido, cantidad_pedidos_entregados, monto_total_gastado,
  ultima_visita, fidelidad_pedidos, acepta_promos, acepta_promos_en,
  registrado_en, origen)
select telefono, nombre, apellido, cantidad_pedidos_entregados, monto_total_gastado,
       ultima_visita, fidelidad_pedidos, acepta_promos, acepta_promos_en,
       registrado_en, origen
  from pm_clientes_fusion;

update public.pedidos p set cliente_telefono = m.nuevo
  from pm_tel_map m
 where p.cliente_telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;

update public.premios p set telefono = m.nuevo
  from pm_tel_map m
 where p.telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;

update public.cupon_usos u set telefono = m.nuevo
  from pm_tel_map m
 where u.telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;

-- Tablas de intentos (anti-spam, se limpian solas): normalizar y borrar lo invalido.
update public.cupon_intentos i set telefono = m.nuevo
  from pm_tel_map m
 where i.telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;
delete from public.cupon_intentos
 where telefono is not null and telefono !~ '^[0-9]{10}$';

update public.fidelidad_intentos i set telefono = m.nuevo
  from pm_tel_map m
 where i.telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;
delete from public.fidelidad_intentos
 where telefono is not null and telefono !~ '^[0-9]{10}$';

update public.registro_intentos i set telefono = m.nuevo
  from pm_tel_map m
 where i.telefono = m.viejo and m.nuevo is not null and m.nuevo <> m.viejo;
delete from public.registro_intentos
 where telefono is not null and telefono !~ '^[0-9]{10}$';

alter table public.pedidos enable trigger pedidos_actualizar_clientes;

-- 4.e Verificacion: la fusion no puede cambiar los totales (si cambian, ROLLBACK).
do $$
declare
  a record;
  d record;
begin
  select * into a from pm_tel_totales_antes;
  select coalesce(sum(cantidad_pedidos_entregados), 0) as pedidos,
         coalesce(sum(monto_total_gastado), 0) as monto,
         coalesce(sum(fidelidad_pedidos), 0) as fidelidad
    into d
    from public.clientes
   where telefono ~ '^[0-9]{10}$';
  if d.pedidos is distinct from a.pedidos
     or d.monto is distinct from a.monto
     or d.fidelidad is distinct from a.fidelidad then
    raise exception '023: los totales de clientes cambiaron (pedidos % -> %, monto % -> %, fidelidad % -> %). Se cancela la migracion.',
      a.pedidos, d.pedidos, a.monto, d.monto, a.fidelidad, d.fidelidad;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 5. VALIDATE de los checks (solo si no quedan filas invalidas)
-- ----------------------------------------------------------------------------
-- Si una tabla conserva registros invalidos (ver SELECT de revision), su
-- check queda NOT VALID: igual rige para filas nuevas o modificadas, pero
-- editar una fila invalida existente (ej. cambiar el estado de un pedido
-- viejo con telefono invalido) fallaria hasta corregir ese telefono.
do $$
declare
  t record;
  hay_invalidas boolean;
begin
  for t in
    select * from (values
      ('clientes', 'telefono', 'clientes_telefono_chk'),
      ('pedidos', 'cliente_telefono', 'pedidos_cliente_telefono_chk'),
      ('premios', 'telefono', 'premios_telefono_chk'),
      ('cupon_usos', 'telefono', 'cupon_usos_telefono_chk'),
      ('cupon_intentos', 'telefono', 'cupon_intentos_telefono_chk'),
      ('fidelidad_intentos', 'telefono', 'fidelidad_intentos_telefono_chk'),
      ('registro_intentos', 'telefono', 'registro_intentos_telefono_chk')
    ) as x(tabla, columna, restriccion)
  loop
    execute format(
      'select exists (select 1 from public.%I where %I is not null and %I !~ %L)',
      t.tabla, t.columna, t.columna, '^[0-9]{10}$') into hay_invalidas;
    if hay_invalidas then
      raise notice '023: public.% conserva telefonos invalidos; % queda NOT VALID (revisar con el SELECT del final).',
        t.tabla, t.restriccion;
    else
      execute format('alter table public.%I validate constraint %I', t.tabla, t.restriccion);
    end if;
  end loop;
end $$;

commit;

-- ============================================================================
-- REVISION de registros que NO se pudieron normalizar (no se tocaron).
-- Ejecutar a mano despues de aplicar:
-- ============================================================================
-- select 'clientes' as tabla, telefono as valor, nombre as detalle from public.clientes
--  where telefono !~ '^[0-9]{10}$'
-- union all
-- select 'pedidos', cliente_telefono, numero_orden from public.pedidos
--  where cliente_telefono !~ '^[0-9]{10}$'
-- union all
-- select 'premios', telefono, id::text from public.premios
--  where telefono !~ '^[0-9]{10}$'
-- union all
-- select 'cupon_usos', telefono, id::text from public.cupon_usos
--  where telefono !~ '^[0-9]{10}$'
-- order by 1, 2;

-- ============================================================================
-- CASOS DE PRUEBA (ejecutar a mano; esperado entre parentesis)
-- ============================================================================
-- select public.pm_normalizar_telefono('3834818271');            -- (3834818271)
-- select public.pm_normalizar_telefono('+54 9 383 481-8271');    -- (3834818271)
-- select public.pm_normalizar_telefono('543834818271');          -- (3834818271)
-- select public.pm_normalizar_telefono('03834818271');           -- (3834818271)
-- select public.pm_normalizar_telefono('0383 15 4818271');       -- (3834818271)
-- select public.pm_normalizar_telefono('383 15 481-8271');       -- (3834818271)
-- select public.pm_normalizar_telefono('011 15 4567-8901');      -- (1145678901)
-- select public.pm_normalizar_telefono('5491145678901');         -- (1145678901)
-- select public.pm_normalizar_telefono('4818271');               -- (null)
-- select public.pm_normalizar_telefono('');                      -- (null)
-- select public.pm_normalizar_telefono(null);                    -- (null)
-- select public.pm_normalizar_telefono(public.pm_normalizar_telefono('0383 15 4818271')); -- (3834818271, idempotente)
-- Funcional: registrar_cliente('Ana','Perez','0383 15 4818271', true) debe
-- guardar 3834818271; con '4818271' debe devolver ok=false con el mensaje generico.

-- ============================================================================
-- ROLLBACK (manual; los DATOS fusionados solo se recuperan con el backup)
-- ============================================================================
-- 1) Restaurar el backup (unica forma de deshacer la fusion de clientes), o bien:
-- 2) Funciones: volver a ejecutar las definiciones de crear_pedido y
--    registrar_cliente/borrar_mis_datos de 020, mis_premios/mi_progreso_fidelidad
--    de 019 y valida_cupon/pm_validar_cupon de 018 (su version previa).
-- 3) Checks (volver a 8-15 digitos):
--    alter table public.clientes drop constraint if exists clientes_telefono_chk;
--    alter table public.clientes add constraint clientes_telefono_chk check (telefono ~ '^[0-9]{8,15}$');
--    (idem pedidos_cliente_telefono_chk sobre cliente_telefono, premios_telefono_chk,
--     cupon_usos_telefono_chk, y con "telefono is null or" en cupon_intentos,
--     fidelidad_intentos y registro_intentos)
-- 4) drop function if exists public.pm_normalizar_telefono(text);
