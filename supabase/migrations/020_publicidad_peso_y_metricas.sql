-- ============================================
-- Migración 020: Peso proporcional + Métricas universales de campañas
-- ============================================

-- 0. Agregar peso a planes_publicidad para configurar rotación
ALTER TABLE planes_publicidad
  ADD COLUMN IF NOT EXISTS peso INTEGER NOT NULL DEFAULT 1;

UPDATE planes_publicidad SET peso = 1 WHERE id = 1;
UPDATE planes_publicidad SET peso = 2 WHERE id = 2;
UPDATE planes_publicidad SET peso = 5 WHERE id = 3;

-- 1. Agregar peso a campanas_publicitarias para rotación proporcional al plan
ALTER TABLE campanas_publicitarias
  ADD COLUMN IF NOT EXISTS peso INTEGER NOT NULL DEFAULT 1;

COMMENT ON COLUMN campanas_publicitarias.peso IS 'Peso para rotación del banner. Plan Básico=1, Profesional=2, Premium=5';

-- Actualizar pesos existentes basados en solicitudes_campana plan_publicidad_id
UPDATE campanas_publicitarias cp
SET peso = COALESCE(
  (SELECT pp.orden FROM solicitudes_campana sc
   JOIN planes_publicidad pp ON pp.id = sc.plan_publicidad_id
   WHERE sc.titulo = cp.titulo AND sc.descripcion = cp.descripcion
   LIMIT 1),
  1
);

-- 2. Tabla de métricas universales (impresiones y clicks)
-- Pacientes, médicos, admins, visitadores — todos quedan registrados
CREATE TABLE IF NOT EXISTS campana_metricas (
  id SERIAL PRIMARY KEY,
  campana_id INTEGER NOT NULL REFERENCES campanas_publicitarias(id) ON DELETE CASCADE,
  perfil_id UUID, -- auth.users.id para médicos, admins, visitadores
  paciente_id INTEGER, -- para pacientes (nullable)
  tipo_perfil TEXT NOT NULL DEFAULT 'desconocido', -- paciente, medico, admin, visitador
  sesion_id TEXT, -- identificador de sesión para frequency capping
  visto_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  clickeado BOOLEAN NOT NULL DEFAULT false,
  contexto TEXT -- 'dashboard', 'recetas', 'examenes', 'login', etc.
);

-- Índices para rendimiento y reportes
CREATE INDEX IF NOT EXISTS idx_metricas_campana ON campana_metricas(campana_id);
CREATE INDEX IF NOT EXISTS idx_metricas_perfil ON campana_metricas(perfil_id);
CREATE INDEX IF NOT EXISTS idx_metricas_paciente ON campana_metricas(paciente_id);
CREATE INDEX IF NOT EXISTS idx_metricas_visto_at ON campana_metricas(visto_at);
CREATE INDEX IF NOT EXISTS idx_metricas_sesion ON campana_metricas(sesion_id);

-- RLS
ALTER TABLE campana_metricas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin ve métricas" ON campana_metricas;
CREATE POLICY "Admin ve métricas" ON campana_metricas
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_publicidad')
    )
  );

-- Insertar métricas libremente desde frontend (se filtra por lógica de negocio)
DROP POLICY IF EXISTS "Autenticados registran métricas" ON campana_metricas;
CREATE POLICY "Autenticados registran métricas" ON campana_metricas
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- 3. Vista resumen para reportes del proveedor
CREATE OR REPLACE VIEW v_metricas_campana_resumen AS
SELECT
  campana_id,
  COUNT(*) FILTER (WHERE clickeado = false) AS impresiones,
  COUNT(*) FILTER (WHERE clickeado = true) AS clicks,
  COUNT(DISTINCT COALESCE(perfil_id::text, paciente_id::text)) AS usuarios_unicos,
  MIN(visto_at) AS primera_impresion,
  MAX(visto_at) AS ultima_impresion
FROM campana_metricas
GROUP BY campana_id;

-- 4. Función para registrar métrica desde frontend o edge function
CREATE OR REPLACE FUNCTION registrar_campana_metrica(
  p_campana_id INTEGER,
  p_perfil_id UUID DEFAULT NULL,
  p_paciente_id INTEGER DEFAULT NULL,
  p_tipo_perfil TEXT DEFAULT 'desconocido',
  p_sesion_id TEXT DEFAULT NULL,
  p_clickeado BOOLEAN DEFAULT false,
  p_contexto TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO campana_metricas (
    campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, clickeado, contexto
  ) VALUES (
    p_campana_id, p_perfil_id, p_paciente_id, p_tipo_perfil, p_sesion_id, p_clickeado, p_contexto
  );
END;
$$;
