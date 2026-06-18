-- ============================================================
-- Ola 2 · LEAK-FIX de métricas de campaña (SEGURIDAD). SOLO cerrar el leak — NO el feature.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cierra fuga VIVA. Probes red-first P283–P290.
--
-- LEAK VIVO (confirmado): v_metricas_campana_pais y v_metricas_campana_resumen son NO-invoker
-- (security_invoker off → ignoran la RLS de campana_metricas) y tienen SELECT a anon+authenticated
-- → CUALQUIERA, incl. anon sin login, ve métricas (impresiones/clicks/CTR/usuarios) de TODAS las
-- empresas. Ambas leen solo campana_metricas (+ campanas_publicitarias + configuracion_pais);
-- NINGUNA lee campana_vistas.
--
-- MECANISMO: security_invoker=on (NO revoke a authenticated — super_admin comparte ese rol de BD;
-- el filtro es por RLS). Bajo invoker: super_admin conserva todo (RLS super_admin en campana_metricas);
-- no-admin/anon ven 0 métricas (campana_metricas RLS los deniega). Residual no-sensible: v_pais deja
-- ver a país-viewers el CONTEO de campañas activas de su país (campanas_publicitarias ya es país-
-- visible por Pub-B) — sin métricas de rendimiento.
--
-- WRITE-LEAK VIVO: policy "Autenticados registran métricas" (auth.role()='authenticated') + grant
-- INSERT → cualquier authenticated inserta métricas arbitrarias (falsear/contaminar). El logging real
-- va por registrar_campana_metrica (SECURITY DEFINER) → revocar el INSERT directo no lo rompe.
-- campana_vistas lo escribe el paciente por upsert directo → se MANTIENE authenticated INSERT/UPDATE.
-- ============================================================

-- 1) Cerrar el read-leak: las vistas evalúan la RLS del que consulta
ALTER VIEW public.v_metricas_campana_pais    SET (security_invoker = on);
ALTER VIEW public.v_metricas_campana_resumen SET (security_invoker = on);

-- 2) Hygiene: una vista no debe ser escribible
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.v_metricas_campana_pais    FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.v_metricas_campana_resumen FROM PUBLIC, anon, authenticated;

-- 3) campana_metricas: cerrar el write-leak (logging sigue por el RPC DEFINER).
--    SE MANTIENE el grant SELECT (RLS super_admin-only lo gatea; necesario para las vistas invoker).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.campana_metricas FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS "Autenticados registran métricas" ON public.campana_metricas;

-- 4) campana_vistas: anon no escribe (policy ya lo impedía) → revoca; mantiene authenticated
--    INSERT+UPDATE (upsert del paciente, gated por la policy "Paciente crea sus vistas").
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.campana_vistas FROM PUBLIC, anon;
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.campana_vistas FROM authenticated;
