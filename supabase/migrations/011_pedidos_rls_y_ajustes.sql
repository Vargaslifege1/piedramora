-- Piedra Mora - Fase 1 - Paso 1B (complemento)
-- RLS, permisos, realtime y ajustes a la migracion 010.

-- 1. Numero de orden: PM-0001 ... PM-9999 ... PM-10000 (sin truncar)
create or replace function public.pm_formato_orden(p_n bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'PM-' || case when p_n < 10000 then lpad(p_n::text, 4, '0') else p_n::text end;
$$;

alter table public.pedidos
  alter column numero_orden
  set default public.pm_formato_orden(nextval('public.pm_pedido_numero_seq'));

-- 2. Delivery: direccion y zona obligatorias; lat/lng opcionales
alter table public.pedidos drop constraint if exists pedidos_delivery_datos_chk;
alter table public.pedidos
  add constraint pedidos_delivery_datos_chk
  check (modalidad <> 'delivery' or (direccion is not null and zona_envio is not null));

-- 3. Activar RLS en todas las tablas nuevas
alter table public.pedidos        enable row level security;
alter table public.clientes       enable row level security;
alter table public.config_negocio enable row level security;
alter table public.zonas_envio    enable row level security;
alter table public.tramos_envio   enable row level security;

-- 4. Cerrar permisos por defecto
revoke all on public.pedidos        from anon, authenticated;
revoke all on public.clientes       from anon, authenticated;
revoke all on public.config_negocio from anon, authenticated;
revoke all on public.zonas_envio    from anon, authenticated;
revoke all on public.tramos_envio   from anon, authenticated;
revoke all on sequence public.pm_pedido_numero_seq from anon, authenticated;
revoke all on function public.pm_pedidos_actualizar_clientes() from public, anon, authenticated;

-- 5. Pedidos: solo admin lee y cambia el estado. Nadie borra ni inserta directo
--    (el alta la hara la funcion crear_pedido en el paso 1C).
grant select on public.pedidos to authenticated;
grant update (estado) on public.pedidos to authenticated;

drop policy if exists "Pedidos lectura admin" on public.pedidos;
create policy "Pedidos lectura admin" on public.pedidos
  for select to authenticated using (public.es_admin());

drop policy if exists "Pedidos edicion admin" on public.pedidos;
create policy "Pedidos edicion admin" on public.pedidos
  for update to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- 6. Clientes: solo admin lee. Los contadores los mantiene el trigger.
grant select on public.clientes to authenticated;

drop policy if exists "Clientes lectura admin" on public.clientes;
create policy "Clientes lectura admin" on public.clientes
  for select to authenticated using (public.es_admin());

-- 7. Config, zonas y tramos: lectura publica, escritura solo admin
grant select on public.config_negocio, public.zonas_envio, public.tramos_envio
  to anon, authenticated;
grant insert, update, delete on public.config_negocio, public.zonas_envio, public.tramos_envio
  to authenticated;

drop policy if exists "Config lectura publica" on public.config_negocio;
create policy "Config lectura publica" on public.config_negocio
  for select to anon, authenticated using (true);
drop policy if exists "Config alta admin" on public.config_negocio;
create policy "Config alta admin" on public.config_negocio
  for insert to authenticated with check (public.es_admin());
drop policy if exists "Config edicion admin" on public.config_negocio;
create policy "Config edicion admin" on public.config_negocio
  for update to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists "Config baja admin" on public.config_negocio;
create policy "Config baja admin" on public.config_negocio
  for delete to authenticated using (public.es_admin());

drop policy if exists "Zonas lectura publica" on public.zonas_envio;
create policy "Zonas lectura publica" on public.zonas_envio
  for select to anon, authenticated using (true);
drop policy if exists "Zonas alta admin" on public.zonas_envio;
create policy "Zonas alta admin" on public.zonas_envio
  for insert to authenticated with check (public.es_admin());
drop policy if exists "Zonas edicion admin" on public.zonas_envio;
create policy "Zonas edicion admin" on public.zonas_envio
  for update to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists "Zonas baja admin" on public.zonas_envio;
create policy "Zonas baja admin" on public.zonas_envio
  for delete to authenticated using (public.es_admin());

drop policy if exists "Tramos lectura publica" on public.tramos_envio;
create policy "Tramos lectura publica" on public.tramos_envio
  for select to anon, authenticated using (true);
drop policy if exists "Tramos alta admin" on public.tramos_envio;
create policy "Tramos alta admin" on public.tramos_envio
  for insert to authenticated with check (public.es_admin());
drop policy if exists "Tramos edicion admin" on public.tramos_envio;
create policy "Tramos edicion admin" on public.tramos_envio
  for update to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists "Tramos baja admin" on public.tramos_envio;
create policy "Tramos baja admin" on public.tramos_envio
  for delete to authenticated using (public.es_admin());

-- 8. Realtime sobre pedidos
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pedidos'
  ) then
    alter publication supabase_realtime add table public.pedidos;
  end if;
end $$;