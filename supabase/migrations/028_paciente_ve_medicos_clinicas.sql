-- ============================================
-- Migración 028: Permitir que pacientes vean médicos y clínicas de su país
-- Necesario para agendar citas desde el portal del paciente
-- ============================================

-- ============================================
-- 1. MEDICOS — Paciente ve médicos de su país
-- ============================================
DROP POLICY IF EXISTS "Paciente ve medicos de su pais" ON medicos;
CREATE POLICY "Paciente ve medicos de su pais" ON medicos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pacientes pa
      WHERE pa.auth_user_id = auth.uid()
      AND pa.pais_id = medicos.pais_id
    )
    OR EXISTS (
      SELECT 1 FROM perfiles p
      WHERE p.id = auth.uid()
      AND p.pais_id = medicos.pais_id
    )
  );

-- ============================================
-- 2. CLINICAS — Paciente ve clínicas de su país
-- ============================================
DROP POLICY IF EXISTS "Paciente ve clinicas de su pais" ON clinicas;
CREATE POLICY "Paciente ve clinicas de su pais" ON clinicas
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pacientes pa
      WHERE pa.auth_user_id = auth.uid()
      AND pa.pais_id = clinicas.pais_id
    )
    OR EXISTS (
      SELECT 1 FROM perfiles p
      WHERE p.id = auth.uid()
      AND p.pais_id = clinicas.pais_id
    )
  );
