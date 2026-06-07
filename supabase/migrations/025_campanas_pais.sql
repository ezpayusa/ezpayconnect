-- ============================================
-- Migración 025: Campañas Publicitarias por País
-- ============================================
-- 1. Tabla de configuración de precios por país para planes de publicidad
-- 2. Agregar pais_id a campana_metricas
-- 3. Actualizar función registrar_campana_metrica
-- 4. Vistas de métricas por país
-- 5. RLS policies actualizadas

-- ============================================
-- 1. TABLA: planes_publicidad_config
-- ============================================
CREATE TABLE IF NOT EXISTS planes_publicidad_config (
  id SERIAL PRIMARY KEY,
  pais_id UUID NOT NULL REFERENCES configuracion_pais(id) ON DELETE CASCADE,
  plan_publicidad_id INTEGER NOT NULL REFERENCES planes_publicidad(id) ON DELETE CASCADE,
  precio_local NUMERIC(12,2) NOT NULL,
  moneda_local TEXT NOT NULL DEFAULT 'GTQ',
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(pais_id, plan_publicidad_id)
);

COMMENT ON TABLE planes_publicidad_config IS 'Configuración de precios de planes de publicidad por país y moneda local';

-- Datos iniciales: Guatemala con precios actuales
INSERT INTO planes_publicidad_config (pais_id, plan_publicidad_id, precio_local, moneda_local, activo)
SELECT
  'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'::UUID,
  pp.id,
  pp.precio,
  pp.moneda,
  true
FROM planes_publicidad pp
WHERE pp.activo = true
ON CONFLICT (pais_id, plan_publicidad_id) DO NOTHING;

-- ============================================
-- 2. AGREGAR pais_id a campana_metricas
-- ============================================
ALTER TABLE campana_metricas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id);

-- Actualizar registros existentes desde campanas_publicitarias
UPDATE campana_metricas cm
SET pais_id = cp.pais_id
FROM campanas_publicitarias cp
WHERE cm.campana_id = cp.id
  AND cm.pais_id IS NULL;

-- ============================================
-- 3. ACTUALIZAR FUNCIÓN registrar_campana_metrica
-- ============================================
CREATE OR REPLACE FUNCTION registrar_campana_metrica(
  p_campana_id INTEGER,
  p_perfil_id UUID DEFAULT NULL,
  p_paciente_id INTEGER DEFAULT NULL,
  p_tipo_perfil TEXT DEFAULT 'desconocido',
  p_sesion_id TEXT DEFAULT NULL,
  p_clickeado BOOLEAN DEFAULT false,
  p_contexto TEXT DEFAULT NULL,
  p_pais_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pais_id UUID;
BEGIN
  -- Si no se pasa pais_id, obtenerlo de la campaña
  IF p_pais_id IS NULL THEN
    SELECT pais_id INTO v_pais_id FROM campanas_publicitarias WHERE id = p_campana_id;
  ELSE
    v_pais_id := p_pais_id;
  END IF;

  INSERT INTO campana_metricas (
    campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, clickeado, contexto, pais_id
  ) VALUES (
    p_campana_id, p_perfil_id, p_paciente_id, p_tipo_perfil, p_sesion_id, p_clickeado, p_contexto, v_pais_id
  );
END;
$$;

-- ============================================
-- 4. VISTAS DE MÉTRICAS
-- ============================================

-- Vista resumen por campaña (actualizada con país)
DROP VIEW IF EXISTS v_metricas_campana_resumen;
CREATE OR REPLACE VIEW v_metricas_campana_resumen AS
SELECT
  c.pais_id,
  cm.campana_id,
  COUNT(*) FILTER (WHERE cm.clickeado = false) AS impresiones,
  COUNT(*) FILTER (WHERE cm.clickeado = true) AS clicks,
  COUNT(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos,
  MIN(cm.visto_at) AS primera_impresion,
  MAX(cm.visto_at) AS ultima_impresion
FROM campana_metricas cm
JOIN campanas_publicitarias c ON c.id = cm.campana_id
GROUP BY c.pais_id, cm.campana_id;

-- Vista resumen agregado por país
CREATE OR REPLACE VIEW v_metricas_campana_pais AS
SELECT
  c.pais_id,
  p.nombre AS pais_nombre,
  p.codigo AS pais_codigo,
  COUNT(DISTINCT c.id) FILTER (WHERE c.activa = true AND c.fecha_fin >= CURRENT_DATE) AS campanas_activas,
  COUNT(DISTINCT c.id) AS total_campanas,
  COUNT(cm.id) FILTER (WHERE cm.clickeado = false) AS impresiones_totales,
  COUNT(cm.id) FILTER (WHERE cm.clickeado = true) AS clicks_totales,
  COUNT(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos,
  CASE
    WHEN COUNT(cm.id) FILTER (WHERE cm.clickeado = false) > 0
    THEN ROUND(
      COUNT(cm.id) FILTER (WHERE cm.clickeado = true)::numeric /
      COUNT(cm.id) FILTER (WHERE cm.clickeado = false)::numeric * 100,
      2
    )
    ELSE 0
  END AS ctr_porcentaje
FROM campanas_publicitarias c
LEFT JOIN campana_metricas cm ON cm.campana_id = c.id
LEFT JOIN configuracion_pais p ON p.id = c.pais_id
GROUP BY c.pais_id, p.nombre, p.codigo;

-- ============================================
-- 5. RLS POLICIES
-- ============================================

-- planes_publicidad_config
ALTER TABLE planes_publicidad_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cualquiera ve config activa" ON planes_publicidad_config;
CREATE POLICY "Cualquiera ve config activa" ON planes_publicidad_config
  FOR SELECT USING (activo = true);

DROP POLICY IF EXISTS "Admin gestiona config" ON planes_publicidad_config;
CREATE POLICY "Admin gestiona config" ON planes_publicidad_config
  FOR ALL USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('super_admin', 'admin', 'admin_publicidad')
    )
  );

-- campana_metricas: actualizar policy de admin
DROP POLICY IF EXISTS "Admin ve métricas" ON campana_metricas;
CREATE POLICY "Admin ve métricas" ON campana_metricas
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('super_admin', 'admin', 'admin_publicidad')
    )
  );
