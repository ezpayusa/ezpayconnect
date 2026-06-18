-- ============================================================
-- Ola 2 · LEAK-FIX v_medicamentos_bajo_stock (SEGURIDAD). Prerequisito de C.2. Mismo patrón que 109.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cierra fuga cross-empresa VIVA. Probes red-first P304–P308.
--
-- LEAK: la vista es NO-invoker (security_invoker OFF, owner postgres) + SELECT a anon/authenticated
-- → bypassa la RLS de farmacia_medicamentos → cualquiera (incl. anon) ve el bajo-stock de TODAS las
-- empresas. Confirmado con fila sembrada: anon ve 1 (PRE). Mientras viva NO-invoker, el confinamiento
-- por sucursal de C.2 sería evadible por esta vista.
--
-- Lee farmacia_medicamentos (RLS: staff ve su empresa vía farm_med_propia_empresa; super_admin todo;
-- anon/no-empresa 0) + farmacias (RLS farmacias_select_proveedor: staff ve su empresa → el LEFT JOIN
-- del nombre resuelve, sin problema estilo campana_vistas).
--
-- MECANISMO: security_invoker=on → la RLS de las tablas base gobierna al que consulta. NO se revoca
-- SELECT de authenticated (super_admin comparte rol; el filtro es RLS). Vista NO-actualizable →
-- los grants de escritura son inertes; se revocan por higiene.
-- ============================================================

ALTER VIEW public.v_medicamentos_bajo_stock SET (security_invoker = on);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.v_medicamentos_bajo_stock FROM PUBLIC, anon, authenticated;
