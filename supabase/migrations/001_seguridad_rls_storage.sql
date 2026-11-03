-- ============================================================================
-- Piedra Mora - Fase 0 - Blindaje de RLS y Storage
-- ============================================================================
-- Objetivo:
--   1. Centralizar la verificacion de administrador en public.es_admin().
--   2. Evitar que cualquier usuario autenticado pueda listar los emails admin.
--   3. Dejar lectura publica de la carta y de las imagenes.
--   4. Dejar escritura, edicion, borrado y subida SOLO para administradores.
--   5. Asegurar el bucket carta-imagenes y el updated_at del servidor.
--
-- Requisitos previos:
--   - Haber ejecutado 000_backup_carta.sql.
--   - Tener creadas public.admins, public.carta y el bucket carta-imagenes.
--
-- Idempotente:
--   Se puede ejecutar varias veces. Las politicas se eliminan y recrean.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Funcion central de verificacion de administrador
-- ----------------------------------------------------------------------------
-- security definer: puede leer public.admins aunque el rol que llama no tenga
-- permisos directos sobre la tabla.
-- search_path vacio: evita ataques de resolucion de nombres.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admins a
    where lower(trim(a.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );
$$;

revoke all on function public.es_admin() from public;
grant execute on function public.es_admin() to authenticated;

comment on function public.es_admin() is
  'Devuelve true si el email del JWT actual existe en public.admins.';

-- ----------------------------------------------------------------------------
-- 2. Tabla admins: sin lectura publica ni listado de emails
-- ----------------------------------------------------------------------------
alter table public.admins enable row level security;

-- La politica vieja permitia que cualquier autenticado viera todos los emails.
drop policy if exists "Admins lectura" on public.admins;

-- No se necesita acceso directo a la tabla desde el frontend: se usa es_admin().
revoke all on public.admins from anon, authenticated;

-- Evitar emails duplicados con distinta capitalizacion.
do $$
begin
  if exists (
    select 1
    from public.admins
    group by lower(trim(email))
    having count(*) > 1
  ) then
    raise exception 'Hay emails duplicados (sin distinguir mayusculas) en public.admins. Corregilos antes de continuar.';
  end if;
end $$;

drop index if exists public.admins_email_lower_uidx;
create unique index admins_email_lower_uidx
  on public.admins (lower(trim(email)));

-- ----------------------------------------------------------------------------
-- 3. Tabla carta: lectura publica, escritura solo admin
-- ----------------------------------------------------------------------------
alter table public.carta enable row level security;

-- Lectura publica de la carta.
drop policy if exists "Carta lectura publica" on public.carta;
create policy "Carta lectura publica"
  on public.carta
  for select
  to anon, authenticated
  using (true);

-- Escritura separada por operacion para que quede explicita.
drop policy if exists "Carta escritura admin" on public.carta;
drop policy if exists "Carta alta admin" on public.carta;
drop policy if exists "Carta edicion admin" on public.carta;
drop policy if exists "Carta baja admin" on public.carta;

create policy "Carta alta admin"
  on public.carta
  for insert
  to authenticated
  with check (public.es_admin());

create policy "Carta edicion admin"
  on public.carta
  for update
  to authenticated
  using (public.es_admin())
  with check (public.es_admin());

create policy "Carta baja admin"
  on public.carta
  for delete
  to authenticated
  using (public.es_admin());

grant select on public.carta to anon, authenticated;
grant insert, update, delete on public.carta to authenticated;

-- El servidor decide la fecha de actualizacion, no el navegador.
alter table public.carta
  alter column updated_at set default now();

create or replace function public.pm_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists carta_touch_updated_at on public.carta;
create trigger carta_touch_updated_at
  before update on public.carta
  for each row
  execute function public.pm_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 4. Bucket de imagenes: lectura publica, escritura solo admin
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'carta-imagenes',
  'carta-imagenes',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Lectura publica de las imagenes de la carta.
drop policy if exists "Imagenes lectura publica" on storage.objects;
create policy "Imagenes lectura publica"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'carta-imagenes');

-- Alta de imagenes solo admin.
drop policy if exists "Imagenes alta admin" on storage.objects;
create policy "Imagenes alta admin"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'carta-imagenes'
    and public.es_admin()
  );

-- Edicion de imagenes solo admin.
drop policy if exists "Imagenes edicion admin" on storage.objects;
create policy "Imagenes edicion admin"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and public.es_admin()
  )
  with check (
    bucket_id = 'carta-imagenes'
    and public.es_admin()
  );

-- Borrado de imagenes solo admin.
drop policy if exists "Imagenes baja admin" on storage.objects;
create policy "Imagenes baja admin"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and public.es_admin()
  );

-- ----------------------------------------------------------------------------
-- 5. Realtime de la carta (por si el proyecto se recreo)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'carta'
  ) then
    alter publication supabase_realtime add table public.carta;
  end if;
end $$;
