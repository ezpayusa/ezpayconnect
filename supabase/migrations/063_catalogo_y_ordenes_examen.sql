-- ============================================================
-- 063 · Catálogo de exámenes del laboratorio + orden agrupada
-- ============================================================

-- ------------------------------------------------------------
-- 1. Catálogo de exámenes que ofrece cada laboratorio
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS examenes_catalogo (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  laboratorio_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  nombre         TEXT NOT NULL,
  categoria      TEXT,            -- opcional: Hematología, Química, Orina…
  activo         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_catalogo_lab ON examenes_catalogo(laboratorio_id);

ALTER TABLE examenes_catalogo ENABLE ROW LEVEL SECURITY;

-- El laboratorio gestiona su propio catálogo
DROP POLICY IF EXISTS catalogo_lab_all ON examenes_catalogo;
CREATE POLICY catalogo_lab_all ON examenes_catalogo
  FOR ALL USING (laboratorio_id = mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = mi_empresa_proveedor());

-- Cualquier usuario autenticado (médico) puede leer el catálogo activo
DROP POLICY IF EXISTS catalogo_read_activos ON examenes_catalogo;
CREATE POLICY catalogo_read_activos ON examenes_catalogo
  FOR SELECT USING (activo = true);

-- ------------------------------------------------------------
-- 2. Orden de examen (cabecera) — agrupa varios ítems
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ordenes_examen (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  laboratorio_id     UUID REFERENCES empresas_proveedoras(id) ON DELETE SET NULL,
  clinica_id         UUID REFERENCES clinicas(id) ON DELETE SET NULL,
  medico_id          UUID REFERENCES perfiles(id) ON DELETE SET NULL,
  paciente_id        BIGINT,            -- pacientes.id (sin FK: cabecera denormalizada)
  origen             TEXT NOT NULL DEFAULT 'medico',   -- 'medico' | 'walk_in'
  prioridad          TEXT NOT NULL DEFAULT 'normal',   -- 'normal' | 'urgente'
  instrucciones      TEXT,              -- observaciones/instrucciones para el lab
  paciente_nombre    TEXT,
  paciente_documento TEXT,
  paciente_telefono  TEXT,
  medico_nombre      TEXT,
  clinica_nombre     TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ordenes_lab     ON ordenes_examen(laboratorio_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_medico  ON ordenes_examen(medico_id);

ALTER TABLE ordenes_examen ENABLE ROW LEVEL SECURITY;

-- El laboratorio ve/gestiona sus órdenes
DROP POLICY IF EXISTS ordenes_lab_all ON ordenes_examen;
CREATE POLICY ordenes_lab_all ON ordenes_examen
  FOR ALL USING (laboratorio_id = mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = mi_empresa_proveedor());

-- El médico ve/crea sus órdenes
DROP POLICY IF EXISTS ordenes_medico_all ON ordenes_examen;
CREATE POLICY ordenes_medico_all ON ordenes_examen
  FOR ALL USING (medico_id = auth.uid())
  WITH CHECK (medico_id = auth.uid());

-- ------------------------------------------------------------
-- 3. examenes pasa a ser ÍTEM de una orden (cada examen = 1 fila,
--    con su propio estado y resultado). orden_id agrupa la hoja.
-- ------------------------------------------------------------
ALTER TABLE examenes
  ADD COLUMN IF NOT EXISTS orden_id UUID REFERENCES ordenes_examen(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_examenes_orden ON examenes(orden_id);
