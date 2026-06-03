-- ============================================
-- Migración 009: Permitir agendar citas desde portal del paciente
-- ============================================

-- 1. Hacer medico_id opcional en citas (paciente agenda sin médico asignado)
ALTER TABLE citas ALTER COLUMN medico_id DROP NOT NULL;

-- 2. Agregar estado 'solicitada' al ENUM de citas
-- PostgreSQL no permite modificar ENUMs directamente, hay que usar ALTER TYPE
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum WHERE enumlabel = 'solicitada'
    AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'cita_estado')
  ) THEN
    ALTER TYPE cita_estado ADD VALUE 'solicitada';
  END IF;
END $$;

-- 3. Política RLS: Paciente puede crear citas para sí mismo
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente crea sus citas' AND tablename = 'citas'
  ) THEN
    CREATE POLICY "Paciente crea sus citas" ON citas
      FOR INSERT WITH CHECK (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;
END $$;
