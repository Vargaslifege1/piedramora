-- ============================================================================
-- Piedra Mora - Fase 0 - Rollback opcional de la carta
-- ============================================================================
-- Objetivo:
--   Restaurar public.carta id=1 desde backups.carta_fase0.
--
-- Importante:
--   Esto revierte SOLO el contenido JSON de la carta (IDs y campos agotado).
--   No revierte RLS, Storage, triggers ni indices. Para eso hay que aplicar
--   las politicas anteriores a mano.
--
-- Cuando ejecutarlo:
--   Solo si la migracion de IDs rompio algo y se necesita volver atras.
-- ============================================================================

do $$
declare
  v_existe integer;
  v_actualizadas integer;
begin
  select count(*) into v_existe
  from backups.carta_fase0
  where id = 1;

  if v_existe = 0 then
    raise exception 'No existe respaldo en backups.carta_fase0 para id=1.';
  end if;

  update public.carta c
     set contenido = b.contenido,
         updated_at = now()
    from backups.carta_fase0 b
   where c.id = b.id
     and b.id = 1;

  get diagnostics v_actualizadas = row_count;

  if v_actualizadas = 0 then
    raise exception 'No existe la fila id=1 en public.carta. No se pudo restaurar.';
  end if;

  raise notice 'Carta restaurada desde backups.carta_fase0.';
end $$;
