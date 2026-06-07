-- ============================================
-- Migración 024: Sistema de Invitaciones para Médicos y Clínicas
-- EzPayConnect
-- ============================================

-- ============================================
-- 1. Tabla: Invitaciones para Médicos
-- ============================================
CREATE TABLE IF NOT EXISTS invitaciones_medico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  pais_id UUID NOT NULL REFERENCES configuracion_pais(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  nombre_completo TEXT NOT NULL,
  telefono TEXT,
  especialidad TEXT,
  clinica_id INTEGER REFERENCES clinicas(id) ON DELETE SET NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'usada', 'expirada', 'cancelada')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  used_at TIMESTAMPTZ,
  created_by UUID REFERENCES perfiles(id) ON DELETE SET NULL
);

COMMENT ON TABLE invitaciones_medico IS 'Invitaciones pre-autorizadas para registro de médicos';

CREATE INDEX IF NOT EXISTS idx_invitaciones_medico_token ON invitaciones_medico(token);
CREATE INDEX IF NOT EXISTS idx_invitaciones_medico_pais ON invitaciones_medico(pais_id);
CREATE INDEX IF NOT EXISTS idx_invitaciones_medico_estado ON invitaciones_medico(estado);
CREATE INDEX IF NOT EXISTS idx_invitaciones_medico_email ON invitaciones_medico(email);

ALTER TABLE invitaciones_medico ENABLE ROW LEVEL SECURITY;

-- Solo super_admin y admin pueden crear/ver invitaciones
DROP POLICY IF EXISTS invitaciones_medico_admin_all ON invitaciones_medico;
CREATE POLICY invitaciones_medico_admin_all
  ON invitaciones_medico FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol IN ('super_admin', 'admin', 'admin_pais')
    )
  );

-- Service role puede todo (para Edge Functions)
DROP POLICY IF EXISTS invitaciones_medico_service_all ON invitaciones_medico;
CREATE POLICY invitaciones_medico_service_all
  ON invitaciones_medico FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================
-- 2. Tabla: Invitaciones para Clínicas
-- ============================================
CREATE TABLE IF NOT EXISTS invitaciones_clinica (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  pais_id UUID NOT NULL REFERENCES configuracion_pais(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  nombre_clinica TEXT NOT NULL,
  nombre_contacto TEXT,
  direccion TEXT,
  telefono TEXT,
  num_medicos INTEGER DEFAULT 1,
  num_secretarias INTEGER DEFAULT 0,
  num_admin INTEGER DEFAULT 0,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'usada', 'expirada', 'cancelada')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  used_at TIMESTAMPTZ,
  created_by UUID REFERENCES perfiles(id) ON DELETE SET NULL
);

COMMENT ON TABLE invitaciones_clinica IS 'Invitaciones pre-autorizadas para registro de clínicas';

CREATE INDEX IF NOT EXISTS idx_invitaciones_clinica_token ON invitaciones_clinica(token);
CREATE INDEX IF NOT EXISTS idx_invitaciones_clinica_pais ON invitaciones_clinica(pais_id);
CREATE INDEX IF NOT EXISTS idx_invitaciones_clinica_estado ON invitaciones_clinica(estado);
CREATE INDEX IF NOT EXISTS idx_invitaciones_clinica_email ON invitaciones_clinica(email);

ALTER TABLE invitaciones_clinica ENABLE ROW LEVEL SECURITY;

-- Solo super_admin y admin pueden crear/ver invitaciones
DROP POLICY IF EXISTS invitaciones_clinica_admin_all ON invitaciones_clinica;
CREATE POLICY invitaciones_clinica_admin_all
  ON invitaciones_clinica FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol IN ('super_admin', 'admin', 'admin_pais')
    )
  );

-- Service role puede todo (para Edge Functions)
DROP POLICY IF EXISTS invitaciones_clinica_service_all ON invitaciones_clinica;
CREATE POLICY invitaciones_clinica_service_all
  ON invitaciones_clinica FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================
-- 3. Funciones SQL para registro desde invitación
-- ============================================

-- Registrar médico desde invitación
CREATE OR REPLACE FUNCTION registrar_medico_desde_invitacion(
  p_token UUID,
  p_user_id UUID,
  p_email TEXT,
  p_nombre_completo TEXT,
  p_telefono TEXT DEFAULT NULL,
  p_especialidad TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invitacion RECORD;
  v_pais_id UUID;
  v_clinica_id INTEGER;
BEGIN
  -- Buscar invitación válida
  SELECT * INTO v_invitacion
  FROM invitaciones_medico
  WHERE token = p_token
    AND estado = 'pendiente'
    AND expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitación no válida o expirada';
  END IF;

  v_pais_id := v_invitacion.pais_id;
  v_clinica_id := v_invitacion.clinica_id;

  -- Verificar que el email coincida
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN
    RAISE EXCEPTION 'El email no coincide con la invitación';
  END IF;

  -- Verificar que el usuario no exista ya en medicos
  IF EXISTS (SELECT 1 FROM medicos WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Este usuario ya está registrado como médico';
  END IF;

  -- Crear médico
  INSERT INTO medicos (
    id,
    nombre_completo,
    email,
    telefono,
    especialidad,
    pais_id
  ) VALUES (
    p_user_id,
    p_nombre_completo,
    p_email,
    COALESCE(p_telefono, v_invitacion.telefono),
    COALESCE(p_especialidad, v_invitacion.especialidad),
    v_pais_id
  );

  -- Actualizar perfil con el rol de médico y país
  UPDATE perfiles
  SET rol = 'medico',
      pais_id = v_pais_id,
      nombre_completo = p_nombre_completo
  WHERE id = p_user_id;

  -- Si hay clínica asignada, crear relación
  IF v_clinica_id IS NOT NULL THEN
    INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
    VALUES (p_user_id, v_clinica_id, true)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Marcar invitación como usada
  UPDATE invitaciones_medico
  SET estado = 'usada',
      used_at = NOW()
  WHERE id = v_invitacion.id;

  RETURN p_user_id;
END;
$$;

-- Registrar clínica desde invitación
CREATE OR REPLACE FUNCTION registrar_clinica_desde_invitacion(
  p_token UUID,
  p_user_id UUID,
  p_email TEXT,
  p_nombre_contacto TEXT,
  p_telefono TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invitacion RECORD;
  v_pais_id UUID;
  v_clinica_id INTEGER;
BEGIN
  -- Buscar invitación válida
  SELECT * INTO v_invitacion
  FROM invitaciones_clinica
  WHERE token = p_token
    AND estado = 'pendiente'
    AND expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitación no válida o expirada';
  END IF;

  v_pais_id := v_invitacion.pais_id;

  -- Verificar que el email coincida
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN
    RAISE EXCEPTION 'El email no coincide con la invitación';
  END IF;

  -- Verificar que el usuario no exista ya
  IF EXISTS (SELECT 1 FROM perfiles WHERE id = p_user_id) THEN
    -- Solo actualizar rol y país si ya existe
    UPDATE perfiles
    SET rol = 'admin_clinica',
        pais_id = v_pais_id,
        nombre_completo = COALESCE(p_nombre_contacto, v_invitacion.nombre_contacto)
    WHERE id = p_user_id;
  END IF;

  -- Crear clínica
  INSERT INTO clinicas (
    nombre,
    direccion,
    telefono,
    email,
    pais_id,
    activa
  ) VALUES (
    v_invitacion.nombre_clinica,
    v_invitacion.direccion,
    COALESCE(p_telefono, v_invitacion.telefono),
    p_email,
    v_pais_id,
    true
  )
  RETURNING id INTO v_clinica_id;

  -- Crear relación médico-clínica (el contacto principal es admin de la clínica)
  INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
  VALUES (p_user_id, v_clinica_id, true)
  ON CONFLICT DO NOTHING;

  -- Marcar invitación como usada
  UPDATE invitaciones_clinica
  SET estado = 'usada',
      used_at = NOW()
  WHERE id = v_invitacion.id;

  RETURN v_clinica_id;
END;
$$;
