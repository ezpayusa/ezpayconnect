-- ============================================
-- Migración 038: Corregir inconsistencia de tipos INTEGER vs UUID
-- Problema: clinicas.id es INTEGER (SERIAL) desde migración 001,
-- pero migraciones 034/035 intentaron usar UUID para clinica_id.
-- Solución: Alinear TODOS los tipos de clinica_id a INTEGER.
-- ============================================

-- ============================================
-- 1. Verificar tipo de clinicas.id
-- ============================================
DO $$
DECLARE
  v_clinicas_id_type TEXT;
BEGIN
  SELECT data_type INTO v_clinicas_id_type
  FROM information_schema.columns
  WHERE table_name = 'clinicas' AND column_name = 'id';

  IF v_clinicas_id_type != 'integer' AND v_clinicas_id_type != 'bigint' THEN
    RAISE EXCEPTION 'clinicas.id no es INTEGER (es %). Esta migración asume INTEGER.', v_clinicas_id_type;
  END IF;
END $$;

-- ============================================
-- 2. Corregir citas.clinica_id
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'citas' AND column_name = 'clinica_id';

  IF v_tipo_actual IS NULL THEN
    -- No existe, crearla como INTEGER
    ALTER TABLE citas ADD COLUMN clinica_id INTEGER REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'citas.clinica_id creada como INTEGER';
  ELSIF v_tipo_actual = 'uuid' THEN
    -- Es UUID, necesitamos convertir a INTEGER
    -- Primero eliminar FK si existe
    ALTER TABLE citas DROP CONSTRAINT IF EXISTS citas_clinica_id_fkey;
    -- Convertir a INTEGER (valores UUID se perderán, pasarán a NULL)
    ALTER TABLE citas ALTER COLUMN clinica_id TYPE INTEGER USING NULL;
    -- Recrear FK
    ALTER TABLE citas ADD CONSTRAINT citas_clinica_id_fkey
      FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'citas.clinica_id convertida de UUID a INTEGER';
  ELSE
    RAISE NOTICE 'citas.clinica_id ya es %, dejando como está', v_tipo_actual;
  END IF;
END $$;

-- ============================================
-- 3. Corregir medico_clinicas.clinica_id
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'medico_clinicas' AND column_name = 'clinica_id';

  IF v_tipo_actual IS NULL THEN
    -- No existe, crear tabla completa
    CREATE TABLE IF NOT EXISTS medico_clinicas (
      id SERIAL PRIMARY KEY,
      medico_id UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
      clinica_id INTEGER NOT NULL REFERENCES clinicas(id) ON DELETE CASCADE,
      es_principal BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(medico_id, clinica_id)
    );
    ALTER TABLE medico_clinicas ENABLE ROW LEVEL SECURITY;
    CREATE POLICY IF NOT EXISTS "Service role all medico_clinicas" ON medico_clinicas
      FOR ALL USING (true) WITH CHECK (true);
    RAISE NOTICE 'medico_clinicas creada con clinica_id INTEGER';
  ELSIF v_tipo_actual = 'uuid' THEN
    -- Es UUID, convertir a INTEGER
    ALTER TABLE medico_clinicas DROP CONSTRAINT IF EXISTS medico_clinicas_clinica_id_fkey;
    ALTER TABLE medico_clinicas DROP CONSTRAINT IF EXISTS medico_clinicas_medico_id_clinica_id_key;
    -- Convertir a INTEGER (valores UUID se perderán, pasarán a NULL)
    ALTER TABLE medico_clinicas ALTER COLUMN clinica_id TYPE INTEGER USING NULL;
    -- Recrear constraints
    ALTER TABLE medico_clinicas ADD CONSTRAINT medico_clinicas_clinica_id_fkey
      FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE CASCADE;
    ALTER TABLE medico_clinicas ADD CONSTRAINT medico_clinicas_medico_id_clinica_id_key
      UNIQUE (medico_id, clinica_id);
    -- Eliminar filas donde clinica_id quedó NULL (ya no son válidas)
    DELETE FROM medico_clinicas WHERE clinica_id IS NULL;
    RAISE NOTICE 'medico_clinicas.clinica_id convertida de UUID a INTEGER';
  ELSE
    RAISE NOTICE 'medico_clinicas.clinica_id ya es %, dejando como está', v_tipo_actual;
  END IF;
END $$;

-- ============================================
-- 4. Asegurar que pacientes.clinica_primaria_id es INTEGER
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'pacientes' AND column_name = 'clinica_primaria_id';

  IF v_tipo_actual IS NULL THEN
    ALTER TABLE pacientes ADD COLUMN clinica_primaria_id INTEGER REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'pacientes.clinica_primaria_id creada como INTEGER';
  ELSIF v_tipo_actual = 'uuid' THEN
    ALTER TABLE pacientes DROP CONSTRAINT IF EXISTS pacientes_clinica_primaria_id_fkey;
    ALTER TABLE pacientes ALTER COLUMN clinica_primaria_id TYPE INTEGER USING NULL;
    ALTER TABLE pacientes ADD CONSTRAINT pacientes_clinica_primaria_id_fkey
      FOREIGN KEY (clinica_primaria_id) REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'pacientes.clinica_primaria_id convertida de UUID a INTEGER';
  END IF;
END $$;

-- ============================================
-- 5. Actualizar función crear_cita para aceptar INTEGER en clinica_id
-- ============================================
DROP FUNCTION IF EXISTS crear_cita(
  INTEGER, UUID, UUID, DATE, TIME, TIME, TEXT, TEXT, TEXT, UUID
);
DROP FUNCTION IF EXISTS crear_cita(
  INTEGER, UUID, INTEGER, DATE, TIME, TIME, TEXT, TEXT, TEXT, UUID
);
DROP FUNCTION IF EXISTS crear_cita;

CREATE OR REPLACE FUNCTION crear_cita(
  p_paciente_id INTEGER,
  p_medico_id UUID DEFAULT NULL,
  p_clinica_id INTEGER DEFAULT NULL,
  p_fecha DATE DEFAULT NULL,
  p_hora_inicio TIME DEFAULT NULL,
  p_hora_fin TIME DEFAULT NULL,
  p_motivo TEXT DEFAULT NULL,
  p_notas TEXT DEFAULT NULL,
  p_estado TEXT DEFAULT 'agendada',
  p_pais_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cita_id INTEGER;
BEGIN
  INSERT INTO citas (
    paciente_id,
    medico_id,
    clinica_id,
    fecha,
    hora_inicio,
    hora_fin,
    motivo,
    notas,
    estado,
    pais_id
  ) VALUES (
    p_paciente_id,
    p_medico_id,
    p_clinica_id,
    p_fecha,
    p_hora_inicio,
    p_hora_fin,
    p_motivo,
    p_notas,
    p_estado::cita_estado,
    p_pais_id
  )
  RETURNING id INTO v_cita_id;

  RETURN v_cita_id;
END;
$$;

COMMENT ON FUNCTION crear_cita IS 'Crea una cita médica. clinica_id es INTEGER para coincidir con clinicas.id.';

-- ============================================
-- 6. Actualizar funciones RPC: listar_clinicas_por_pais (retorna INTEGER id)
-- ============================================
CREATE OR REPLACE FUNCTION listar_clinicas_por_pais(p_pais_id UUID DEFAULT NULL)
RETURNS TABLE (
  id INTEGER,
  nombre TEXT,
  pais_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id,
    c.nombre,
    c.pais_id
  FROM clinicas c
  WHERE p_pais_id IS NULL OR c.pais_id = p_pais_id
  ORDER BY c.nombre;
END;
$$;

-- ============================================
-- 7. Actualizar funciones RPC: obtener_clinicas_medico (retorna INTEGER clinica_id)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_clinicas_medico(p_medico_id UUID)
RETURNS TABLE (
  clinica_id INTEGER,
  clinica_nombre TEXT,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    mc.clinica_id,
    c.nombre,
    mc.es_principal
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_medico_id;
END;
$$;

-- ============================================
-- 8. Actualizar funciones RPC: obtener_medicos_clinica (acepta INTEGER clinica_id)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_medicos_clinica(p_clinica_id INTEGER)
RETURNS TABLE (
  medico_id UUID,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    mc.medico_id,
    mc.es_principal
  FROM medico_clinicas mc
  WHERE mc.clinica_id = p_clinica_id;
END;
$$;

-- ============================================
-- 9. Actualizar función RPC: obtener_clinica_principal_medico (retorna INTEGER)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_clinica_principal_medico(p_medico_id UUID)
RETURNS TABLE (
  clinica_id INTEGER,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    mc.clinica_id,
    mc.es_principal
  FROM medico_clinicas mc
  WHERE mc.medico_id = p_medico_id
    AND mc.es_principal = true
  LIMIT 1;
END;
$$;

-- ============================================
-- 10. Actualizar función RPC: asociar_medico_clinica (acepta INTEGER)
-- ============================================
CREATE OR REPLACE FUNCTION asociar_medico_clinica(
  p_medico_id UUID,
  p_clinica_id INTEGER,
  p_es_principal BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
  VALUES (p_medico_id, p_clinica_id, p_es_principal)
  ON CONFLICT (medico_id, clinica_id) DO UPDATE SET es_principal = EXCLUDED.es_principal;
END;
$$;

-- ============================================
-- 11. Función RPC: Obtener citas de una clínica (bypass RLS)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_citas_clinica(p_clinica_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  id INTEGER,
  medico_id UUID,
  paciente_id INTEGER,
  clinica_id INTEGER,
  fecha DATE,
  hora_inicio TIME,
  hora_fin TIME,
  motivo TEXT,
  estado TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ,
  paciente_nombre TEXT,
  paciente_apellido TEXT,
  paciente_telefono TEXT,
  paciente_email TEXT,
  paciente_auth_user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id,
    c.medico_id,
    c.paciente_id,
    c.clinica_id,
    c.fecha,
    c.hora_inicio,
    c.hora_fin,
    c.motivo,
    c.estado::TEXT,
    c.notas,
    c.created_at,
    p.nombre AS paciente_nombre,
    p.apellido AS paciente_apellido,
    p.telefono AS paciente_telefono,
    p.email AS paciente_email,
    p.auth_user_id AS paciente_auth_user_id
  FROM citas c
  LEFT JOIN pacientes p ON p.id = c.paciente_id
  WHERE 
    -- Citas asignadas directamente a la clínica
    c.clinica_id = p_clinica_id
    -- O citas de médicos que atienden en la clínica
    OR c.medico_id IN (
      SELECT mc.medico_id FROM medico_clinicas mc WHERE mc.clinica_id = p_clinica_id
    )
    -- O citas sin médico ni clínica (solicitadas desde portal)
    OR (c.medico_id IS NULL AND c.estado IN ('solicitada', 'agendada') 
        AND (p_clinica_id IS NULL OR c.clinica_id IS NULL))
  ORDER BY c.fecha, c.hora_inicio;
END;
$$;

-- ============================================
-- 12. Función RPC: Obtener clínica de un usuario (admin o médico)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_clinica_usuario(p_user_id UUID)
RETURNS TABLE (
  clinica_id INTEGER,
  clinica_nombre TEXT,
  es_admin BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Primero buscar como médico principal
  RETURN QUERY
  SELECT 
    mc.clinica_id,
    c.nombre,
    false
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_user_id
    AND mc.es_principal = true
  LIMIT 1;

  -- Si no encontró, buscar cualquier relación (admin o médico secundario)
  RETURN QUERY
  SELECT 
    mc.clinica_id,
    c.nombre,
    true
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_user_id
  LIMIT 1;
END;
$$;

-- ============================================
-- 13. Recargar schema cache de PostgREST
-- ============================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
