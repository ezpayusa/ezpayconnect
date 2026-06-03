-- ============================================
-- Migración: Tablas del Portal del Paciente
-- ============================================

-- 1. Agregar auth_user_id a pacientes para vincular con auth.users
ALTER TABLE IF EXISTS pacientes
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id);

-- Índice para búsqueda rápida
CREATE INDEX IF NOT EXISTS idx_pacientes_auth_user_id ON pacientes(auth_user_id);

-- 2. Tabla de mensajes de chat paciente-médico
CREATE TABLE IF NOT EXISTS chat_mensajes (
  id SERIAL PRIMARY KEY,
  paciente_id INTEGER REFERENCES pacientes(id) ON DELETE CASCADE,
  medico_id UUID REFERENCES perfiles(id) ON DELETE CASCADE,
  remitente TEXT NOT NULL CHECK (remitente IN ('paciente', 'medico')),
  mensaje TEXT NOT NULL,
  leido BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_paciente ON chat_mensajes(paciente_id);
CREATE INDEX IF NOT EXISTS idx_chat_medico ON chat_mensajes(medico_id);
CREATE INDEX IF NOT EXISTS idx_chat_created ON chat_mensajes(created_at DESC);

-- 3. Tabla de notificaciones del paciente
CREATE TABLE IF NOT EXISTS notificaciones_pacientes (
  id SERIAL PRIMARY KEY,
  paciente_id INTEGER REFERENCES pacientes(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('cita', 'receta', 'examen', 'mensaje', 'general')),
  titulo TEXT NOT NULL,
  mensaje TEXT,
  leida BOOLEAN DEFAULT false,
  accion_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_paciente ON notificaciones_pacientes(paciente_id);
CREATE INDEX IF NOT EXISTS idx_notif_leida ON notificaciones_pacientes(leida);

-- 4. Tabla de tokens push notification
CREATE TABLE IF NOT EXISTS push_tokens (
  id SERIAL PRIMARY KEY,
  paciente_id INTEGER REFERENCES pacientes(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  plataforma TEXT NOT NULL CHECK (plataforma IN ('web', 'android', 'ios')),
  activo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_paciente ON push_tokens(paciente_id);

-- ============================================
-- RLS Policies (seguridad)
-- ============================================

-- Políticas para chat_mensajes
ALTER TABLE chat_mensajes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Paciente ve sus mensajes" ON chat_mensajes
  FOR SELECT USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));

CREATE POLICY "Paciente envía mensajes" ON chat_mensajes
  FOR INSERT WITH CHECK (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));

-- Políticas para notificaciones_pacientes
ALTER TABLE notificaciones_pacientes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Paciente ve sus notificaciones" ON notificaciones_pacientes
  FOR ALL USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));

-- Políticas para push_tokens
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Paciente gestiona sus tokens" ON push_tokens
  FOR ALL USING (paciente_id IN (
    SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
  ));
