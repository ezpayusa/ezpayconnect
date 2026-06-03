-- ============================================
-- Migración 010: Sistema de campañas publicitarias
-- ============================================

-- 1. Tabla de campañas publicitarias
CREATE TABLE IF NOT EXISTS campanas_publicitarias (
  id SERIAL PRIMARY KEY,
  titulo TEXT NOT NULL,
  descripcion TEXT,
  tipo TEXT NOT NULL DEFAULT 'farmacia', -- farmacia, equipo_medico, laboratorio, general
  imagen_url TEXT,
  link_url TEXT,
  fecha_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_fin DATE NOT NULL,
  activa BOOLEAN NOT NULL DEFAULT true,
  condicion_filtro TEXT, -- diabetes, hipertension, null = todos
  genero_filtro TEXT, -- M, F, null = todos
  edad_min INTEGER,
  edad_max INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Tabla de vistas de campañas (tracking opcional)
CREATE TABLE IF NOT EXISTS campana_vistas (
  id SERIAL PRIMARY KEY,
  campana_id INTEGER NOT NULL REFERENCES campanas_publicitarias(id) ON DELETE CASCADE,
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
  visto_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  clickeado BOOLEAN NOT NULL DEFAULT false,
  UNIQUE(campana_id, paciente_id)
);

-- 3. Políticas RLS para campanas_publicitarias
ALTER TABLE campanas_publicitarias ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve campanas activas' AND tablename = 'campanas_publicitarias'
  ) THEN
    CREATE POLICY "Paciente ve campanas activas" ON campanas_publicitarias
      FOR SELECT USING (activa = true AND fecha_fin >= CURRENT_DATE);
  END IF;
END $$;

-- 4. Políticas RLS para campana_vistas
ALTER TABLE campana_vistas ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente crea sus vistas' AND tablename = 'campana_vistas'
  ) THEN
    CREATE POLICY "Paciente crea sus vistas" ON campana_vistas
      FOR INSERT WITH CHECK (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Paciente ve sus vistas' AND tablename = 'campana_vistas'
  ) THEN
    CREATE POLICY "Paciente ve sus vistas" ON campana_vistas
      FOR SELECT USING (paciente_id IN (
        SELECT id FROM pacientes WHERE auth_user_id = auth.uid()
      ));
  END IF;
END $$;

-- 5. Función para enviar notificación promocional a todos los pacientes
CREATE OR REPLACE FUNCTION enviar_notificacion_promocion(
  p_titulo TEXT,
  p_mensaje TEXT,
  p_tipo TEXT DEFAULT 'promocion'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO notificaciones_pacientes (paciente_id, titulo, mensaje, tipo, leida)
  SELECT id, p_titulo, p_mensaje, p_tipo, false
  FROM pacientes;
END;
$$;
