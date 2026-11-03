-- ============================================================================
-- Piedra Mora - Fase 0 - Respaldo previo de la carta
-- ============================================================================
-- Objetivo:
--   Guardar una copia de la fila actual de public.carta antes de migrar IDs.
--   La tabla queda en el schema "backups", que no esta expuesto por PostgREST.
--
-- Cuando ejecutarlo:
--   Despues de exportar la carta real desde el panel admin (Exportar JSON) y
--   antes de ejecutar 001 y 002.
--
-- Idempotente:
--   Se puede ejecutar varias veces. El "on conflict do nothing" conserva el
--   primer respaldo y nunca lo pisa con una version ya migrada.
-- ============================================================================

create schema if not exists backups;

create table if not exists backups.carta_fase0 (
  id integer primary key,
  contenido jsonb not null,
  respaldado_at timestamptz not null default now()
);

-- La tabla de respaldo no debe ser accesible desde el frontend.
revoke all on schema backups from anon, authenticated;
alter table backups.carta_fase0 enable row level security;
revoke all on backups.carta_fase0 from anon, authenticated;

insert into backups.carta_fase0 (id, contenido)
select id, contenido
from public.carta
where id = 1
on conflict (id) do nothing;

do $$
declare
  v_filas integer;
begin
  select count(*) into v_filas from backups.carta_fase0 where id = 1;

  if v_filas = 0 then
    raise notice 'No se encontro la fila id=1 en public.carta. Revisar antes de continuar.';
  else
    raise notice 'Respaldo listo en backups.carta_fase0 para la fila id=1.';
  end if;
end $$;
