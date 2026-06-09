-- ============================================
-- Migración 030: Permitir lectura pública de países activos
-- Necesario para que usuarios no autenticados (registro) vean el selector de país
-- ============================================

-- Asegurar que RLS esté habilitado
ALTER TABLE configuracion_pais ENABLE ROW LEVEL SECURITY;

-- Policy: Cualquiera puede leer países activos (registro, onboarding)
DROP POLICY IF EXISTS "Publico lee paises activos" ON configuracion_pais;
CREATE POLICY "Publico lee paises activos" ON configuracion_pais
  FOR SELECT USING (activo = true);
