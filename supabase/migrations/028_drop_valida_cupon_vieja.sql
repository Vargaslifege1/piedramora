-- ============================================================================
-- 028_drop_valida_cupon_vieja.sql
-- Elimina la firma vieja de valida_cupon (6 parametros, con p_subtotal que
-- mandaba el navegador).
-- ============================================================================
-- APLICAR RECIEN DESPUES de: (1) aplicar la 027 y (2) PUBLICAR el main.js nuevo
-- (el que llama a valida_cupon con p_items). Si se aplica antes, la pagina
-- publicada vieja deja de poder validar cupones.
-- ANTES DE APLICAR: hacer un BACKUP de la base.
--
-- Idempotente (drop function if exists). No toca la firma nueva de 027.
-- ============================================================================

drop function if exists public.valida_cupon(text, text, numeric, text, text, text);
