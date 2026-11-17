-- ============================================================================
-- 027_cupon_no_acumulable.sql
-- Cupones NO acumulables: ni con promociones, ni con descuento por medio de
-- pago, ni con premios de fidelidad.
-- ============================================================================
-- ANTES DE APLICAR: hacer un BACKUP COMPLETO de la base (Supabase > Database >
-- Backups, o pg_dump). Esta migracion REEMPLAZA crear_pedido (funcion de
-- dinero, misma firma de 16 parametros y mismos grants) y agrega una funcion
-- valida_cupon nueva (otra firma).
--
-- Prerrequisitos (ya aplicadas): 001-026 (usa pm_calcular_pedido de 021,
-- pm_validar_cupon de 023 y crear_pedido de 025). NO se modifica ninguna
-- migracion anterior ni pm_calcular_pedido / pm_validar_cupon.
--
-- Reglas:
--   1. Un cupon se calcula SOLO sobre el subtotal de productos "normales".
--      Producto en promo = categoria 'promo' OR en_oferta (oferta vigente).
--      Los productos en promo quedan a su precio de promo, sin cupon.
--   2. Si no hay ningun producto normal: "El cupon no se puede usar con promociones."
--   3. Si el medio de pago tiene descuento (> 0%), el cupon se rechaza.
--   4. Con premio de fidelidad no se puede usar cupon (y al reves).
--   El minimo de compra y el tope del cupon se evaluan sobre esa base elegible.
--   Los usos previos siguen ignorando pedidos cancelados (pm_validar_cupon).
--
-- Compatibilidad: valida_cupon(6 parametros, con p_subtotal del navegador) de
-- 023 NO se toca aca, para que la pagina publicada siga andando hasta publicar
-- el main.js nuevo. La firma vieja se elimina en la 028, que se aplica DESPUES
-- de publicar el frontend. Postgres las trata como funciones distintas.
-- La columna cupones.acumulable_con_pago queda sin efecto (no se borra).
--
-- Idempotente: se puede volver a correr (create or replace).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. pm_cupon_base_elegible: subtotal de productos sin promo
--    p_items = el 'items' que devuelve pm_calcular_pedido (con categoria,
--    en_oferta y subtotal por item). Devuelve {base, hay_promo}.
-- ----------------------------------------------------------------------------
create or replace function public.pm_cupon_base_elegible(p_items jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'base', coalesce(sum((i.value ->> 'subtotal')::numeric) filter (
              where not (coalesce(i.value ->> 'categoria', '') = 'promo'
                         or coalesce(i.value ->> 'en_oferta', 'false') = 'true')), 0),
    'hay_promo', coalesce(bool_or(
              coalesce(i.value ->> 'categoria', '') = 'promo'
              or coalesce(i.value ->> 'en_oferta', 'false') = 'true'), false))
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) as i(value);
$$;

revoke all on function public.pm_cupon_base_elegible(jsonb)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. valida_cupon (firma nueva: recibe los items, el servidor calcula todo)
-- ----------------------------------------------------------------------------
create or replace function public.valida_cupon(
  p_codigo      text,
  p_telefono    text,
  p_items       jsonb,
  p_sucursal_id text,
  p_modalidad   text,
  p_metodo_pago text,
  p_premio_id   uuid default null
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
  v_calc jsonb;
  v_el jsonb;
  v_base numeric;
  v_hay_promo boolean;
  v_pct_pago numeric;
  v_res jsonb;
  v_desc numeric;
  v_cupon public.cupones%rowtype;
  v_codigo text;
  v_etiqueta text;
begin
  v_tel := public.pm_normalizar_telefono(p_telefono);
  v_codigo := left(upper(btrim(coalesce(p_codigo, ''))), 40);

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

  -- Limite anti-spam (mismos umbrales que la version de 023).
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
  values (v_tel, v_ip, v_codigo);

  -- Regla 4: premio de fidelidad y cupon no se combinan.
  if p_premio_id is not null then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'No podés usar un cupón junto con un premio de fidelidad.');
  end if;

  -- Precios y medio de pago salen del servidor. Se calcula como retiro: el
  -- envio no interviene en el cupon (y no exige coordenadas en la vista previa).
  begin
    v_calc := public.pm_calcular_pedido(
      p_sucursal_id, 'retiro', p_metodo_pago, p_items, null, null, null);
  exception when others then
    return jsonb_build_object('ok', false, 'descuento', 0, 'mensaje', sqlerrm);
  end;

  -- Regla 3: con descuento por medio de pago no hay cupon.
  v_pct_pago := coalesce((v_calc ->> 'porcentaje_pago')::numeric, 0);
  if v_pct_pago > 0 then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'El cupón no se puede usar con un medio de pago que tiene descuento. Elegí otro medio de pago.');
  end if;

  -- Reglas 1 y 2: solo productos sin promo.
  v_el := public.pm_cupon_base_elegible(v_calc -> 'items');
  v_base := coalesce((v_el ->> 'base')::numeric, 0);
  v_hay_promo := coalesce((v_el ->> 'hay_promo')::boolean, false);

  if v_base <= 0 then
    return jsonb_build_object(
      'ok', false, 'descuento', 0,
      'mensaje', 'El cupón no se puede usar con promociones.');
  end if;

  v_res := public.pm_validar_cupon(
    p_codigo, p_telefono, v_base, p_sucursal_id, p_modalidad, false);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    return jsonb_build_object(
      'ok', false, 'descuento', 0, 'mensaje', v_res ->> 'mensaje');
  end if;

  v_desc := least(greatest(coalesce((v_res ->> 'descuento')::numeric, 0), 0), v_base);

  select * into v_cupon from public.cupones
   where id = (v_res ->> 'cupon_id')::uuid;

  v_etiqueta := 'Cupón ' || v_codigo
    || case when v_cupon.tipo = 'porcentaje'
            then ' ' || trim_scale(v_cupon.valor)::text || '%' else '' end
    || case when v_hay_promo then ' sobre productos sin promo'
            else ' sobre los productos' end;

  return jsonb_build_object(
    'ok', true,
    'descuento', v_desc,
    'base_elegible', v_base,
    'etiqueta', v_etiqueta,
    'mensaje', 'Cupón aplicado.');
end;
$$;

revoke all on function public.valida_cupon(text, text, jsonb, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.valida_cupon(text, text, jsonb, text, text, text, uuid)
  to anon, authenticated;

comment on function public.valida_cupon(text, text, jsonb, text, text, text, uuid) is
  'Vista previa del cupon calculada 100% en el servidor desde los items. Solo descuenta sobre productos sin promo; rechaza con promos solas, medio de pago con descuento o premio (027).';

-- ----------------------------------------------------------------------------
-- 3. crear_pedido (base: la version ACTUAL de 025, misma firma de 16 parametros)
--    Cambios marcados con "-- 027": el bloque del cupon usa la base elegible y
--    rechaza en vez de "gana el mayor / acumulable".
-- ----------------------------------------------------------------------------
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
  p_acepta_promos    boolean default null,
  p_programado_para  timestamptz default null     -- 024
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
  v_base numeric := 0;                      -- 027
  v_total numeric := 0;

  v_items jsonb;                            -- 019
  v_premio public.premios%rowtype;          -- 019
  v_premio_aplicado boolean := false;       -- 019

  v_tz constant text := 'America/Argentina/Buenos_Aires';   -- 024
  v_ahora timestamptz := now();                             -- 024
  v_estado jsonb;                                           -- 024
  v_prox timestamptz;                                       -- 024
  v_max_dias integer := 15;                                 -- 024
  v_modo text;                                              -- 024
  v_cuando text;                                            -- 024
  v_acd boolean;                                            -- 025
  v_acr boolean;                                            -- 025
  v_ini timestamptz;                                        -- 025
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

  -- 024: horario de atencion y pedidos programados. sucursal_estado valida
  -- ademas que la sucursal exista ("La sucursal no existe.").
  v_estado := public.sucursal_estado(p_sucursal_id, v_ahora);

  if p_programado_para is null then
    if not coalesce((v_estado ->> 'abierto')::boolean, false) then
      v_prox := (v_estado ->> 'proxima_apertura')::timestamptz;
      if v_estado ->> 'motivo' = 'cierre_especial' and v_prox is not null then
        raise exception 'Cerrado hasta el %. Podés programar tu pedido.',
          to_char(v_prox at time zone v_tz, 'DD/MM');
      elsif v_estado ->> 'motivo' = 'forzado_cerrado' or v_prox is null then
        raise exception 'Cerrado por el momento. Podés programar tu pedido.';
      else
        v_cuando := case
          when (v_prox at time zone v_tz)::date = (v_ahora at time zone v_tz)::date then ''
          when (v_prox at time zone v_tz)::date = (v_ahora at time zone v_tz)::date + 1 then 'mañana '
          else 'el ' || to_char(v_prox at time zone v_tz, 'DD/MM') || ' ' end;
        raise exception 'Cerrado, abrimos %a las %. Podés programar tu pedido.',
          v_cuando, to_char(v_prox at time zone v_tz, 'HH24:MI');
      end if;
    end if;

    -- 025: sucursal abierta -> el turno vigente (semanal o excepcion) tiene que
    -- aceptar la modalidad. En forzado abierto / sin horarios ambas son true.
    if p_modalidad = 'delivery'
       and not coalesce((v_estado ->> 'acepta_delivery')::boolean, true) then
      raise exception 'Hoy este local solo recibe pedidos para retiro. Elegí retiro.';
    elsif p_modalidad is distinct from 'delivery'
       and not coalesce((v_estado ->> 'acepta_retiro')::boolean, true) then
      raise exception 'Hoy este local solo recibe pedidos para delivery. Elegí delivery.';
    end if;
  else
    select case when jsonb_typeof(valor) <> 'number' then 15
                when (valor #>> '{}')::numeric between 1 and 90
                  then floor((valor #>> '{}')::numeric)::integer
                else 15 end
      into v_max_dias
      from public.config_negocio where clave = 'programar_max_dias';
    v_max_dias := coalesce(v_max_dias, 15);

    if p_programado_para <= v_ahora then
      raise exception 'La fecha y hora programadas tienen que ser futuras.';
    end if;
    if p_programado_para > v_ahora + make_interval(days => v_max_dias) then
      raise exception 'Solo podés programar pedidos hasta % días adelante.', v_max_dias;
    end if;

    -- Debe caer en horario de apertura. Se permite igual si ese dia esta en un
    -- cierre especial, o si es hoy y la sucursal esta en modo manual forzado
    -- (queda pendiente hasta que el local lo acepte).
    select modo into v_modo from public.sucursal_estado_manual where sucursal_id = p_sucursal_id;
    if not (
      (public.pm_en_turno(p_sucursal_id, p_programado_para)
         and not public.pm_en_cierre(p_sucursal_id, p_programado_para))
      or public.pm_en_cierre(p_sucursal_id, p_programado_para)
      or (coalesce(v_modo, 'automatico') <> 'automatico'
          and (p_programado_para at time zone v_tz)::date = (v_ahora at time zone v_tz)::date)
      or not exists (select 1 from public.sucursal_horarios where sucursal_id = p_sucursal_id)
    ) then
      raise exception 'Ese horario está fuera de nuestro horario de atención. Elegí otro día u horario.';
    end if;

    -- 025: el turno de ese dia tiene que aceptar la modalidad. No se valida en
    -- cierre especial ni con la sucursal en modo manual forzado hoy (casos que
    -- se dejan pasar a pendiente), ni si no hay turno (sin horarios).
    if not public.pm_en_cierre(p_sucursal_id, p_programado_para)
       and not (coalesce(v_modo, 'automatico') <> 'automatico'
                and (p_programado_para at time zone v_tz)::date = (v_ahora at time zone v_tz)::date) then
      select m.acepta_delivery, m.acepta_retiro, m.ini
        into v_acd, v_acr, v_ini
        from public.pm_modalidades_en(p_sucursal_id, p_programado_para) m;
      if p_modalidad = 'delivery' and v_acd is not null and not v_acd then
        raise exception 'El % este local solo recibe pedidos para retiro. Elegí retiro.',
          to_char(v_ini at time zone v_tz, 'DD/MM');
      elsif p_modalidad is distinct from 'delivery' and v_acr is not null and not v_acr then
        raise exception 'El % este local solo recibe pedidos para delivery. Elegí delivery.',
          to_char(v_ini at time zone v_tz, 'DD/MM');
      end if;
    end if;
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
    -- 027: el cupon no se acumula con descuento por medio de pago.
    if coalesce((v_calc ->> 'porcentaje_pago')::numeric, 0) > 0 then
      raise exception 'El cupón no se puede usar con un medio de pago que tiene descuento. Elegí otro medio de pago.';
    end if;

    -- 027: el cupon se calcula solo sobre productos sin promo
    -- (categoria 'promo' o en_oferta quedan afuera).
    v_base := coalesce(
      (public.pm_cupon_base_elegible(v_calc -> 'items') ->> 'base')::numeric, 0);
    if v_base <= 0 then
      raise exception 'El cupón no se puede usar con promociones.';
    end if;

    v_cupon_res := public.pm_validar_cupon(
      v_codigo, v_tel, v_base, p_sucursal_id, p_modalidad, true);

    if not coalesce((v_cupon_res ->> 'ok')::boolean, false) then
      raise exception '%', v_cupon_res ->> 'mensaje';
    end if;

    -- 027: nunca descuenta mas que la base elegible (<= subtotal).
    v_desc_cupon := least(
      greatest(coalesce((v_cupon_res ->> 'descuento')::numeric, 0), 0), v_base);
    v_desc_final := least(v_desc_cupon, v_subtotal);
    v_cupon_aplicado := v_desc_cupon > 0;
  end if;

  v_total := v_subtotal - v_desc_final + v_envio;

  begin
    insert into public.pedidos (
      sucursal_id, modalidad, cliente_nombre, cliente_telefono,
      direccion, lat, lng, zona_envio, items_snapshot,
      subtotal, descuento, costo_envio, total,
      metodo_pago, idempotency_key, notas,
      cupon_codigo, descuento_cupon,
      premio_id, programado_para
    ) values (
      p_sucursal_id, p_modalidad, v_nombre, v_tel,
      v_dir, v_lat, v_lng, v_calc ->> 'zona_envio', v_items,
      v_subtotal, v_desc_final, v_envio, v_total,
      p_metodo_pago, p_idempotency_key, nullif(v_notas, ''),
      case when v_cupon_aplicado then v_codigo else null end,
      case when v_cupon_aplicado then v_desc_cupon else 0 end,
      case when v_premio_aplicado then v_premio.id else null end,
      p_programado_para
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

revoke all on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz)
  from public;
grant execute on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz)
  to anon, authenticated;

comment on function public.crear_pedido(
  text, text, text, text, text, jsonb, text, numeric, numeric, text, text, uuid, text, uuid, boolean, timestamptz) is
  'Crea un pedido validando precios, cupon, premio, horario y modalidad aceptada por el turno en el servidor. Con p_programado_para agenda el pedido (futuro, max programar_max_dias, dentro del horario). Ignora totales y descuentos del cliente.';

commit;

-- ============================================================================
-- CASOS DE PRUEBA (a mano; el cupon PIEDRAMORA = 20 %, sin minimo; telefono de
-- prueba sin usos previos; carta actual: Cheeseburger $13.000, COMBO 2
-- CHEESEBURGER categoria promo). Usar los ids reales de la carta.
-- select public.valida_cupon('PIEDRAMORA','3834000000',
--   '[{"producto_id":"<id cheeseburger>","cantidad":1}]'::jsonb,
--   'maestro-quiroga','retiro','efectivo');
-- a) 1 Cheeseburger $13.000            -> ok, descuento 2600, base_elegible 13000
-- b) solo promo_combo_2_cheeseburger   -> ok=false "El cupón no se puede usar con promociones."
-- c) promo + 1 Cheeseburger            -> ok, descuento 2600 (solo sobre la Cheeseburger),
--                                          etiqueta "Cupón PIEDRAMORA 20% sobre productos sin promo"
-- d) con p_premio_id (cualquier uuid)  -> ok=false "No podés usar un cupón junto con un premio..."
--    crear_pedido con p_cupon y p_premio_id -> error "No podés usar un premio y un cupón..."
-- e) medio de pago con descuento > 0 (descuentos_pago) -> ok=false "...medio de pago que tiene descuento..."
--    crear_pedido con ese pago + cupon -> mismo error (no crea el pedido)
-- f) cancelar el pedido que uso el cupon (estado='cancelado') -> valida_cupon vuelve a dar ok
--    (pm_validar_cupon cuenta solo pedidos no cancelados).
-- crear_pedido (a): pedidos.subtotal 13000, descuento 2600, total 10400 + envio.
-- crear_pedido (c): descuento = 20 % de la parte sin promo; total = subtotal - descuento + envio.
-- ============================================================================
