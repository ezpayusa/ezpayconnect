-- ============================================================
-- 050: RLS por rol DENTRO de la empresa proveedora (confidencialidad real)
-- ------------------------------------------------------------
-- El RLS ya aislaba por empresa. Esto agrega aislamiento por rol:
--  - visitador solo ve SUS visitas (no las de todo el equipo)
--  - pagos visibles solo para roles financieros/gestión (no visitador/catalogo/lectura)
--  - productos los gestiona admin/editor/catalogo
--  - ubicaciones de médicos las gestiona admin/editor/supervisor
-- Usa helpers de la migración 048: mi_empresa_proveedor(), mi_rol_proveedor().
-- ============================================================

-- ---------- VISITAS: visitador ve solo las suyas ----------
DROP POLICY IF EXISTS "Proveedor ve visitas de su empresa" ON visitas_agendadas;
CREATE POLICY "Proveedor ve visitas segun rol" ON visitas_agendadas
FOR SELECT
USING (
  empresa_id = mi_empresa_proveedor()
  AND (
    mi_rol_proveedor() IN ('admin', 'editor', 'supervisor')   -- gestión ve todas
    OR cuenta_proveedor_id = auth.uid()                        -- el visitador asignado
    OR propuesta_por = auth.uid()                              -- o quien la propuso
  )
);

-- ---------- PAGOS: solo roles financieros/gestión ----------
-- (crearPago hace insert().select(), por eso quien paga también debe poder leer)
DROP POLICY IF EXISTS "Proveedor ve pagos de su empresa" ON pagos_proveedor;
CREATE POLICY "Proveedor ve pagos segun rol" ON pagos_proveedor
FOR SELECT
USING (
  empresa_id = mi_empresa_proveedor()
  AND mi_rol_proveedor() IN ('admin', 'editor', 'finanzas', 'marketing', 'supervisor')
);

DROP POLICY IF EXISTS "Proveedor crea pagos" ON pagos_proveedor;
CREATE POLICY "Proveedor crea pagos" ON pagos_proveedor
FOR INSERT
WITH CHECK (
  empresa_id = mi_empresa_proveedor()
  AND mi_rol_proveedor() IN ('admin', 'editor', 'finanzas', 'marketing', 'supervisor')
);

-- ---------- PRODUCTOS: gestión por admin/editor/catalogo ----------
-- (la lectura de productos de la propia empresa la mantiene su política SELECT aparte)
DROP POLICY IF EXISTS "Proveedor admin/editor gestiona productos" ON productos_empresa;
CREATE POLICY "Proveedor gestiona productos segun rol" ON productos_empresa
FOR ALL
USING (
  empresa_id = mi_empresa_proveedor()
  AND mi_rol_proveedor() IN ('admin', 'editor', 'catalogo')
)
WITH CHECK (
  empresa_id = mi_empresa_proveedor()
  AND mi_rol_proveedor() IN ('admin', 'editor', 'catalogo')
);

-- ---------- UBICACIONES MÉDICOS: gestión por admin/editor/supervisor ----------
DROP POLICY IF EXISTS "ubicaciones_insert" ON ubicaciones_medico_proveedor;
DROP POLICY IF EXISTS "ubicaciones_update" ON ubicaciones_medico_proveedor;
DROP POLICY IF EXISTS "ubicaciones_delete" ON ubicaciones_medico_proveedor;

CREATE POLICY "ubicaciones_insert" ON ubicaciones_medico_proveedor
FOR INSERT
WITH CHECK (empresa_id = mi_empresa_proveedor() AND mi_rol_proveedor() IN ('admin', 'editor', 'supervisor'));

CREATE POLICY "ubicaciones_update" ON ubicaciones_medico_proveedor
FOR UPDATE
USING (empresa_id = mi_empresa_proveedor() AND mi_rol_proveedor() IN ('admin', 'editor', 'supervisor'));

CREATE POLICY "ubicaciones_delete" ON ubicaciones_medico_proveedor
FOR DELETE
USING (empresa_id = mi_empresa_proveedor() AND mi_rol_proveedor() IN ('admin', 'editor', 'supervisor'));
