-- ============================================================
-- 058: Dos agendas por médico — disponibilidad por CONTEXTO
-- ------------------------------------------------------------
--  contexto='visitador' : horario para visitadores médicos (slots de 15 min)
--  contexto='paciente'  : horario para pacientes (lo usa el webapp del paciente)
-- Las filas existentes se quedan como 'visitador' (es lo que consume hoy el
-- flujo de visitadores; no romper). Además, el admin de clínica puede gestionar
-- la disponibilidad de los médicos de su clínica.
-- ============================================================

ALTER TABLE disponibilidad_medico
  ADD COLUMN IF NOT EXISTS contexto text NOT NULL DEFAULT 'visitador'
  CHECK (contexto IN ('visitador','paciente'));

-- ¿El usuario actual es admin de una clínica que comparte con este médico?
CREATE OR REPLACE FUNCTION admin_clinica_de_medico(p_medico_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM perfiles p WHERE p.id = auth.uid() AND p.rol = 'admin_clinica')
     AND EXISTS (
       SELECT 1 FROM medico_clinicas a
       JOIN medico_clinicas m ON m.clinica_id = a.clinica_id
       WHERE a.medico_id = auth.uid() AND m.medico_id = p_medico_id
     );
$$;
GRANT EXECUTE ON FUNCTION admin_clinica_de_medico(uuid) TO authenticated;

-- El admin de clínica gestiona la disponibilidad de los médicos de su clínica.
DROP POLICY IF EXISTS "Admin clinica gestiona disponibilidad de sus medicos" ON disponibilidad_medico;
CREATE POLICY "Admin clinica gestiona disponibilidad de sus medicos" ON disponibilidad_medico
FOR ALL
USING (admin_clinica_de_medico(medico_id))
WITH CHECK (admin_clinica_de_medico(medico_id));
