-- ============================================================================
-- Migración 237: DROP get_invitaciones_empresa(uuid) — follow-up de C3 (mig 234)
-- ============================================================================
-- Residual 1 de AUDITORIA-PROFUNDA-2026-07-05.md. La función (era 017:116) es
-- superficie MUERTA que devolvía el TOKEN (uuid) de invitación + email + teléfono
-- de cualquier empresa → secuestro de registro. La mig 234 (C3) la dejó REVOCADA
-- de PUBLIC/anon/authenticated (fail-closed) pero NO la dropeó, a la espera de
-- confirmar 0 callers.
--
-- Re-confirmado 2026-07-07 antes del DROP:
--   * 0 callers en el repo (grep src/ + supabase/functions/ + scripts/): sólo
--     aparece en su propia definición (017), el REVOKE (234) y el informe.
--   * 0 referencias internas en prod (ninguna otra función/vista/trigger la usa;
--     pg_depend sin dependientes).
--   * Sigue revocada en prod: anon_exec=false, auth_exec=false, public_exec=false.
--   * Firma exacta en prod: get_invitaciones_empresa(p_empresa_id uuid).
--
-- DROP sin CASCADE a propósito: si (contra lo verificado) existiera un dependiente,
-- el DROP falla en vez de arrastrar objetos. IF EXISTS para ser idempotente.
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_invitaciones_empresa(uuid);

-- ============================================================================
-- Verificación post-aplicación:
--   SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='public' AND p.proname='get_invitaciones_empresa';   -- 0
-- ============================================================================
