-- ============================================
-- Migración: RLS para portal del paciente + tabla examenes
-- Idempotente: puede ejecutarse varias veces sin error
-- ============================================

-- ============================================
-- 1. Políticas RLS para que pacientes lean sus propios datos
-- ============================================

DO $$
BEGIN
  -- Paciente puede ver sus propias citas
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve sus citas' AND tablename = 'citas'
  ) THEN
    CREATE POLICY "Paciente ve sus citas" ON citas
      FOR SELECT USING (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;

  -- Paciente puede ver sus propias recetas
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve sus recetas' AND tablename = 'recetas'
  ) THEN
    CREATE POLICY "Paciente ve sus recetas" ON recetas
      FOR SELECT USING (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;

  -- Paciente puede ver items de sus recetas
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve items de sus recetas' AND tablename = 'receta_items'
  ) THEN
    CREATE POLICY "Paciente ve items de sus recetas" ON receta_items
      FOR SELECT USING (receta_id IN (
        SELECT r.id FROM recetas r
        JOIN pacientes p ON r.paciente_id = p.id
        WHERE p.auth_user_id = auth.uid()
      ));
  END IF;

  -- Paciente puede ver su propio perfil
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve su perfil' AND tablename = 'pacientes'
  ) THEN
    CREATE POLICY "Paciente ve su perfil" ON pacientes
      FOR SELECT USING (auth_user_id = auth.uid());
  END IF;
END $$;

-- ============================================
-- 2. Tabla de exámenes médicos
-- ============================================

-- Crear tipo ENUM solo si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'examen_estado'
  ) THEN
    CREATE TYPE examen_estado AS ENUM ('pendiente', 'completado', 'revision');
  END IF;
END $$;

-- Crear tabla examenes
CREATE TABLE IF NOT EXISTS examenes (
  id SERIAL PRIMARY KEY,
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
  medico_id UUID REFERENCES perfiles(id) ON DELETE SET NULL,
  tipo TEXT NOT NULL,
  descripcion TEXT,
  fecha_solicitud DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_resultado DATE,
  estado examen_estado NOT NULL DEFAULT 'pendiente',
  resultados TEXT,
  archivo_url TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_examenes_paciente ON examenes(paciente_id);
CREATE INDEX IF NOT EXISTS idx_examenes_estado ON examenes(estado);

-- RLS para examenes
ALTER TABLE examenes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Médico ve exámenes de sus pacientes
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Medico ve examenes de sus pacientes' AND tablename = 'examenes'
  ) THEN
    CREATE POLICY "Medico ve examenes de sus pacientes" ON examenes
      FOR ALL USING (medico_id = auth.uid());
  END IF;

  -- Paciente ve sus propios exámenes
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve sus examenes' AND tablename = 'examenes'
  ) THEN
    CREATE POLICY "Paciente ve sus examenes" ON examenes
      FOR SELECT USING (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;
END $$;
