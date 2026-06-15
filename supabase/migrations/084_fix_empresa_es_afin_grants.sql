-- ============================================================
-- INCREMENTO 3 (paneles) · Fix de privilegios de private.empresa_es_afin
-- ------------------------------------------------------------
-- Rama: paneles/empresas-afines. Endurecimiento posterior a 083 (no se edita 083
-- ya aplicada/commiteada).
--
-- Contexto: 083 concedió EXECUTE de private.empresa_es_afin a anon porque la policy
-- "Médico ve productos activos" era TO public y un anon que leyera productos_empresa
-- evaluaría el helper. Revisión del frontend: NINGÚN flujo anónimo lee
-- productos_empresa (useBusquedaMedicamentos corre autenticado; el resto es
-- proveedor/admin autenticado). Por tanto:
--   1) Se REVOCA EXECUTE de anon/PUBLIC (mínimo privilegio): el helper queda solo
--      para authenticated + service_role.
--   2) Se restringe "Médico ve productos activos" a TO authenticated, de modo que
--      anon NO evalúe el helper (evita un 42501 latente) y obtenga 0 filas limpio.
-- empresa_es_afin conserva SECURITY DEFINER + search_path='' (verificado, intacto).
-- ============================================================

REVOKE EXECUTE ON FUNCTION private.empresa_es_afin(uuid) FROM anon, PUBLIC;
-- (authenticated y service_role conservan EXECUTE: los lectores legítimos son autenticados)

DROP POLICY IF EXISTS "Médico ve productos activos" ON public.productos_empresa;
CREATE POLICY "Médico ve productos activos" ON public.productos_empresa
  FOR SELECT TO authenticated
  USING (
    estado = 'activo'
    AND NOT COALESCE(private.empresa_es_afin(empresa_id), false)
  );
