-- ============================================
-- Migración 033: Preferencias de paciente (médico primario y clínica primaria)
-- EzPayConnect
-- ============================================

-- 1. Agregar campos de preferencia a pacientes
ALTER TABLE pacientes
  ADD COLUMN IF NOT EXISTS medico_primario_id UUID REFERENCES perfiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS clinica_primaria_id INTEGER REFERENCES clinicas(id) ON DELETE SET NULL;

-- 2. Índices para búsqueda rápida
CREATE INDEX IF NOT EXISTS idx_pacientes_medico_primario ON pacientes(medico_primario_id);
CREATE INDEX IF NOT EXISTS idx_pacientes_clinica_primaria ON pacientes(clinica_primaria_id);

-- 3. Política RLS: paciente puede ver su propio médico primario y clínica primaria
-- (ya cubierto por las políticas existentes de pacientes)

COMMENT ON COLUMN pacientes.medico_primario_id IS 'Médico preferido del paciente para pre-selección en agendado';
COMMENT ON COLUMN pacientes.clinica_primaria_id IS 'Clínica preferida del paciente para pre-selección en agendado';
