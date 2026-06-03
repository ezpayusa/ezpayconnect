-- ============================================
-- Migración: RLS para portal del paciente + tabla examenes
-- ============================================

-- ============================================
-- 1. Políticas RLS para que pacientes lean sus propios datos
-- ============================================

-- Paciente puede ver sus propias citas
CREATE POLICY IF NOT EXISTS "Paciente ve sus citas" ON citas
  FOR SELECT USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));

-- Paciente puede ver sus propias recetas
CREATE POLICY IF NOT EXISTS "Paciente ve sus recetas" ON recetas
  FOR SELECT USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));

-- Paciente puede ver items de sus recetas
CREATE POLICY IF NOT EXISTS "Paciente ve items de sus recetas" ON receta_items
  FOR SELECT USING (receta_id IN (
    SELECT r.id FROM recetas r
    JOIN pacientes p ON r.paciente_id = p.id
    WHERE p.auth_user_id = auth.uid()
  ));

-- Paciente puede ver su propio perfil
CREATE POLICY IF NOT EXISTS "Paciente ve su perfil" ON pacientes
  FOR SELECT USING (auth_user_id = auth.uid());

-- ============================================
-- 2. Tabla de exámenes médicos
-- ============================================
CREATE TYPE examen_estado AS ENUM ('pendiente', 'completado', 'revision');

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

-- Médico ve exámenes de sus pacientes
CREATE POLICY IF NOT EXISTS "Medico ve examenes de sus pacientes" ON examenes
  FOR ALL USING (medico_id = auth.uid());

-- Paciente ve sus propios exámenes
CREATE POLICY IF NOT EXISTS "Paciente ve sus examenes" ON examenes
  FOR SELECT USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));
