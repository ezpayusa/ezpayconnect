-- ============================================================================
-- Migración 229 (BACKFILL): re-provisiona la fila `pacientes` de 2 usuarios reales
-- que quedaron huérfanos por el bug de registro (insert client-side bloqueado por RLS
-- al no haber sesión con email-confirm ON). Opción A: fila mínima (email + país default,
-- nombre/apellido en blanco); el usuario completa el resto desde su perfil.
-- Idempotente: el NOT EXISTS evita duplicar si se corre dos veces.
-- ============================================================================

BEGIN;

INSERT INTO public.pacientes (auth_user_id, email, nombre, apellido, pais_id, activo)
SELECT u.id, u.email, '', '', 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'::uuid, true
FROM auth.users u
WHERE u.email IN ('alesecond098@gmail.com', 'oscarabadgutierreztomas@gmail.com')
  AND NOT EXISTS (SELECT 1 FROM public.pacientes p WHERE p.auth_user_id = u.id);

COMMIT;
