-- Piedra Mora · estructura completa para Supabase
-- Ejecutar completo en: Supabase Dashboard > SQL Editor > New query
-- Incluye tabla de carta, administradores y bucket público para imágenes.

create table if not exists public.admins (
  email text primary key
);

alter table public.admins enable row level security;

drop policy if exists "Admins lectura" on public.admins;
create policy "Admins lectura"
  on public.admins
  for select
  to authenticated
  using (true);

insert into public.admins (email)
values ('lichivargas2005@gmail.com')
on conflict (email) do nothing;

create table if not exists public.carta (
  id integer primary key,
  contenido jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.carta enable row level security;

drop policy if exists "Carta lectura publica" on public.carta;
create policy "Carta lectura publica"
  on public.carta
  for select
  using (true);

drop policy if exists "Carta escritura admin" on public.carta;
create policy "Carta escritura admin"
  on public.carta
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  )
  with check (
    exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  );

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

drop policy if exists "Imagenes lectura publica" on storage.objects;
create policy "Imagenes lectura publica"
  on storage.objects
  for select
  using (bucket_id = 'carta-imagenes');

drop policy if exists "Imagenes alta admin" on storage.objects;
create policy "Imagenes alta admin"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'carta-imagenes'
    and exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  );

drop policy if exists "Imagenes edicion admin" on storage.objects;
create policy "Imagenes edicion admin"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  )
  with check (
    bucket_id = 'carta-imagenes'
    and exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  );

drop policy if exists "Imagenes baja admin" on storage.objects;
create policy "Imagenes baja admin"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'carta-imagenes'
    and exists (
      select 1
      from public.admins a
      where lower(a.email) = lower(auth.jwt() ->> 'email')
    )
  );

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

-- La fila de public.carta se crea automáticamente al guardar desde admin.html.
