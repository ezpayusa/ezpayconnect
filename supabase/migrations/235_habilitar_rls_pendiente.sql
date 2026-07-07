-- ============================================================================
-- Migración 235: Habilitar RLS pendiente + REVOKE de grants por defecto
-- ============================================================================
-- Cierra A3 de AUDITORIA-PROFUNDA-2026-07-05.md. NO es una vuln viva: se verificó
-- contra la BD de producción (probes de solo lectura 2026-07-05/07) que las 6
-- tablas YA tienen relrowsecurity=true y policies activas. A3 es DRIFT repo↔prod:
--
--   * NINGÚN `ENABLE ROW LEVEL SECURITY` para estas 6 tablas existe en el repo
--     (las policies vienen de migs 070/073/076/078, pero el ENABLE se aplicó
--     fuera de migraciones). En un rebuild limpio las policies nacerían inertes.
--   * `001_inicial.sql:243` tiene `ALTER TABLE medicamentos DISABLE ROW LEVEL
--     SECURITY;` explícito, nunca re-habilitado en el repo → en un rebuild,
--     `medicamentos` nacería SIN RLS y (por default de Supabase) con CRUD a
--     `authenticated` = catálogo de fármacos escribible por cualquiera.
--   * Ningún `REVOKE` sobre estas tablas: `anon` tiene grants (varios con CRUD
--     completo, incl. las 2 de PHI) que son INERTES hoy (no hay policy para anon)
--     pero son un gap de defensa en profundidad.
--
-- Esta migración hace el estado seguro de prod REPRODUCIBLE desde migraciones y
-- endurece los grants por defecto. Es idempotente (ENABLE de tabla ya habilitada
-- y REVOKE de privilegio no poseído son no-ops) y en prod los ENABLE son no-ops.
--
-- Alcance decidido tras verificar grants + policies + write-paths de la app:
--   - REVOKE ALL FROM anon en las 6: `anon` no tiene NINGUNA policy en estas
--     tablas → cero cambio de comportamiento, solo cierra grants inertes.
--   - medicamentos: `authenticated` queda en SELECT (catálogo). Los writes NO
--     tienen path en la app (0 `.from('medicamentos').insert/update/delete`, 0
--     RPC runtime; sólo el seed de 001) → revocar no rompe nada. Deja inerte la
--     policy `medicamentos_write_admin` (nadie la ejerce).
--   - historial_medico / recetas_avanzadas / farmacias / farmacia_medicamentos:
--     NO se tocan los grants de escritura de `authenticated` — son LOAD-BEARING
--     (policies INSERT-médico / UPDATE-tenant / ALL-superadmin dependen de ellos).
--   - TRUNCATE a `authenticated` en las 6: TRUNCATE bypassa RLS y no tiene uso
--     legítimo desde el cliente (PostgREST no lo expone) → se revoca defensivo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) ENABLE ROW LEVEL SECURITY (idempotente; no-op en prod, ya están ON)
--    `IF EXISTS` protege contra un rebuild parcial donde la tabla no exista aún.
-- ----------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.historial_medico       ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.recetas_avanzadas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.dispensaciones          ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.farmacias               ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.farmacia_medicamentos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.medicamentos            ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2) REVOKE ALL FROM anon en las 6 (grants inertes; cero policy para anon)
-- ----------------------------------------------------------------------------
REVOKE ALL ON public.historial_medico       FROM anon;
REVOKE ALL ON public.recetas_avanzadas       FROM anon;
REVOKE ALL ON public.dispensaciones          FROM anon;
REVOKE ALL ON public.farmacias               FROM anon;
REVOKE ALL ON public.farmacia_medicamentos   FROM anon;
REVOKE ALL ON public.medicamentos            FROM anon;

-- ----------------------------------------------------------------------------
-- 3) medicamentos: authenticated queda SELECT-only (sin write path en la app)
-- ----------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.medicamentos FROM authenticated;
-- REFERENCES/TRIGGER: no expuestos por PostgREST, pero se revocan para dejar
-- medicamentos ESTRICTAMENTE SELECT-only a authenticated (catálogo de solo lectura).
REVOKE REFERENCES, TRIGGER ON public.medicamentos FROM authenticated;
-- (SELECT se conserva: useRecetas.ts lee el catálogo. La policy admin-only de
--  escritura queda inerte; si en el futuro hay un panel de catálogo, exponer un
--  RPC DEFINER o re-grantear con REVOKE de anon garantizado.)

-- ----------------------------------------------------------------------------
-- 4) TRUNCATE defensivo: quitar de authenticated en las 5 restantes
--    (bypassa RLS; sin uso legítimo desde cliente). No toca SELECT/INSERT/
--     UPDATE/DELETE, que son load-bearing vía las policies de cada tabla.
-- ----------------------------------------------------------------------------
REVOKE TRUNCATE ON public.historial_medico       FROM authenticated;
REVOKE TRUNCATE ON public.recetas_avanzadas       FROM authenticated;
REVOKE TRUNCATE ON public.dispensaciones          FROM authenticated;
REVOKE TRUNCATE ON public.farmacias               FROM authenticated;
REVOKE TRUNCATE ON public.farmacia_medicamentos   FROM authenticated;

-- ============================================================================
-- Verificación post-aplicación (probes de solo lectura):
--   RLS ON en las 6:
--     SELECT relname, relrowsecurity FROM pg_class
--      WHERE relnamespace='public'::regnamespace
--        AND relname IN ('historial_medico','recetas_avanzadas','dispensaciones',
--                        'farmacias','farmacia_medicamentos','medicamentos');
--   anon sin privilegios en las 6:
--     SELECT table_name, grantee, privilege_type FROM information_schema.role_table_grants
--      WHERE table_schema='public' AND grantee='anon'
--        AND table_name IN ('historial_medico','recetas_avanzadas','dispensaciones',
--                           'farmacias','farmacia_medicamentos','medicamentos');  -- 0 filas
--   medicamentos: authenticated sólo SELECT:
--     SELECT privilege_type FROM information_schema.role_table_grants
--      WHERE table_schema='public' AND table_name='medicamentos' AND grantee='authenticated';
-- ============================================================================
