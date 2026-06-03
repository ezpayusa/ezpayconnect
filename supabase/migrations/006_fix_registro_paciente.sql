-- ============================================
-- Migración 006: Fix registro de pacientes desde portal
-- ============================================

-- 1. Hacer medico_id opcional para pacientes que se registran solos
ALTER TABLE pacientes ALTER COLUMN medico_id DROP NOT NULL;

-- 2. Política RLS: Usuario puede crear su propio perfil de paciente
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente crea su perfil' AND tablename = 'pacientes'
  ) THEN
    CREATE POLICY "Paciente crea su perfil" ON pacientes
      FOR INSERT WITH CHECK (auth_user_id = auth.uid());
  END IF;
END $$;

-- 3. Política RLS: Usuario puede actualizar su propio perfil
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente actualiza su perfil' AND tablename = 'pacientes'
  ) THEN
    CREATE POLICY "Paciente actualiza su perfil" ON pacientes
      FOR UPDATE USING (auth_user_id = auth.uid());
  END IF;
END $$;
