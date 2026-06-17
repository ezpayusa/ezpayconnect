-- ============================================================
-- PAÍS #4 (ÚLTIMO) · farmacias — reestructurar lectura por rol (SEGURIDAD, alto blast)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) → smoke al aplicar.
-- Probes red-first (P216–P223).
--
-- Hoy: 3 policies SELECT USING(true) (anon + 2 authenticated) → CUALQUIERA ve TODAS las
-- farmacias (cross-país y cross-empresa). Se reestructura por rol:
--   · proveedor  → empresa_id = mi_empresa_proveedor() (su empresa; NUNCA país)
--   · médico/clínico → pais_id = mi_pais() AND mi_empresa_proveedor() IS NULL (su país)
--   · super_admin → ya cubierto por farmacias_write_admin (ALL)
--   · anon → SIN policy (la anon era vestigial; ningún lector anon en src/)
--
-- LECCIÓN 12: la exclusión de proveedor en la rama país usa el helper DEFINER
-- private.mi_empresa_proveedor() IS NULL (canónico, fail-closed), NO un NOT EXISTS crudo
-- sobre cuentas_proveedor (ese se evalúa con la RLS del caller → podría fallar-abierto y
-- re-meter al proveedor en la rama país = leak cross-tenant).
--
-- NO se tocan: farmacias_write_admin (ALL super_admin) ni farmacias_tenant_update (UPDATE).
-- pais_id ya existe en la fila (predicado directo, sin helper); 0 filas NULL (sin backfill).
-- ============================================================

-- 1) DROP las 3 USING(true)
DROP POLICY IF EXISTS "Allow anon read farmacias" ON public.farmacias;
DROP POLICY IF EXISTS "Allow authenticated read farmacias" ON public.farmacias;
DROP POLICY IF EXISTS "ver_farmacias" ON public.farmacias;

-- 2) Proveedor → su empresa (NUNCA país)
DROP POLICY IF EXISTS "farmacias_select_proveedor" ON public.farmacias;
CREATE POLICY "farmacias_select_proveedor" ON public.farmacias
  FOR SELECT TO authenticated
  USING (COALESCE(empresa_id = public.mi_empresa_proveedor(), false));

-- 3) Médico/clínico (NO proveedor) → su país (fail-closed)
DROP POLICY IF EXISTS "farmacias_select_pais" ON public.farmacias;
CREATE POLICY "farmacias_select_pais" ON public.farmacias
  FOR SELECT TO authenticated
  USING (
    pais_id = private.mi_pais()
    AND public.mi_empresa_proveedor() IS NULL   -- excluye proveedores (lección 12, DEFINER canónico)
  );

-- super_admin: SELECT cubierto por farmacias_write_admin (ALL super_admin) — sin cambio.
