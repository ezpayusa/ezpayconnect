-- ============================================
-- Migración 039: Corregir inconsistencia de tipos (producción usa UUID)
-- Contexto: clinicas.id es UUID en producción.
-- Esta migración asegura que TODAS las referencias a clinica_id sean UUID.
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

  IF v_clinicas_id_type != 'uuid' THEN
    RAISE EXCEPTION 'clinicas.id no es UUID (es %). Abortando.', v_clinicas_id_type;
  END IF;
END $$;

-- ============================================
-- 2. Asegurar que citas.clinica_id es UUID
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'citas' AND column_name = 'clinica_id';

  IF v_tipo_actual IS NULL THEN
    ALTER TABLE citas ADD COLUMN clinica_id UUID REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'citas.clinica_id creada como UUID';
  ELSIF v_tipo_actual = 'integer' THEN
    ALTER TABLE citas DROP CONSTRAINT IF EXISTS citas_clinica_id_fkey;
    ALTER TABLE citas ALTER COLUMN clinica_id TYPE UUID USING NULL;
    ALTER TABLE citas ADD CONSTRAINT citas_clinica_id_fkey
      FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'citas.clinica_id convertida de INTEGER a UUID';
  ELSE
    RAISE NOTICE 'citas.clinica_id ya es %, dejando como está', v_tipo_actual;
  END IF;
END $$;

-- ============================================
-- 3. Asegurar que medico_clinicas.clinica_id es UUID
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'medico_clinicas' AND column_name = 'clinica_id';

  IF v_tipo_actual IS NULL THEN
    CREATE TABLE IF NOT EXISTS medico_clinicas (
      id SERIAL PRIMARY KEY,
      medico_id UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
      clinica_id UUID NOT NULL REFERENCES clinicas(id) ON DELETE CASCADE,
      es_principal BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(medico_id, clinica_id)
    );
    ALTER TABLE medico_clinicas ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Service role all medico_clinicas" ON medico_clinicas;
    CREATE POLICY "Service role all medico_clinicas" ON medico_clinicas
      FOR ALL USING (true) WITH CHECK (true);
    RAISE NOTICE 'medico_clinicas creada con clinica_id UUID';
  ELSIF v_tipo_actual = 'integer' THEN
    ALTER TABLE medico_clinicas DROP CONSTRAINT IF EXISTS medico_clinicas_clinica_id_fkey;
    ALTER TABLE medico_clinicas DROP CONSTRAINT IF EXISTS medico_clinicas_medico_id_clinica_id_key;
    ALTER TABLE medico_clinicas ALTER COLUMN clinica_id TYPE UUID USING NULL;
    ALTER TABLE medico_clinicas ADD CONSTRAINT medico_clinicas_clinica_id_fkey
      FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE CASCADE;
    ALTER TABLE medico_clinicas ADD CONSTRAINT medico_clinicas_medico_id_clinica_id_key
      UNIQUE (medico_id, clinica_id);
    DELETE FROM medico_clinicas WHERE clinica_id IS NULL;
    RAISE NOTICE 'medico_clinicas.clinica_id convertida de INTEGER a UUID';
  ELSE
    RAISE NOTICE 'medico_clinicas.clinica_id ya es %, dejando como está', v_tipo_actual;
  END IF;
END $$;

-- ============================================
-- 4. Corregir pacientes.clinica_primaria_id a UUID
-- ============================================
DO $$
DECLARE
  v_tipo_actual TEXT;
BEGIN
  SELECT data_type INTO v_tipo_actual
  FROM information_schema.columns
  WHERE table_name = 'pacientes' AND column_name = 'clinica_primaria_id';

  IF v_tipo_actual IS NULL THEN
    ALTER TABLE pacientes ADD COLUMN clinica_primaria_id UUID REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'pacientes.clinica_primaria_id creada como UUID';
  ELSIF v_tipo_actual = 'integer' THEN
    ALTER TABLE pacientes DROP CONSTRAINT IF EXISTS pacientes_clinica_primaria_id_fkey;
    ALTER TABLE pacientes ALTER COLUMN clinica_primaria_id TYPE UUID USING NULL;
    ALTER TABLE pacientes ADD CONSTRAINT pacientes_clinica_primaria_id_fkey
      FOREIGN KEY (clinica_primaria_id) REFERENCES clinicas(id) ON DELETE SET NULL;
    RAISE NOTICE 'pacientes.clinica_primaria_id convertida de INTEGER a UUID';
  END IF;
END $$;

-- ============================================
-- 5. Recrear crear_cita con UUID para clinica_id
-- ============================================
DROP FUNCTION IF EXISTS crear_cita(
  INTEGER, UUID, INTEGER, DATE, TIME, TIME, TEXT, TEXT, TEXT, UUID
);
DROP FUNCTION IF EXISTS crear_cita(
  INTEGER, UUID, UUID, DATE, TIME, TIME, TEXT, TEXT, TEXT, UUID
);
DROP FUNCTION IF EXISTS crear_cita;

CREATE OR REPLACE FUNCTION crear_cita(
  p_paciente_id INTEGER,
  p_medico_id UUID DEFAULT NULL,
  p_clinica_id UUID DEFAULT NULL,
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

COMMENT ON FUNCTION crear_cita IS 'Crea una cita médica. clinica_id es UUID para coincidir con clinicas.id en producción.';

-- ============================================
-- 6. Recrear funciones RPC con UUID para clínica
-- ============================================
CREATE OR REPLACE FUNCTION listar_clinicas_por_pais(p_pais_id UUID DEFAULT NULL)
RETURNS TABLE (
  id UUID,
  nombre TEXT,
  pais_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.nombre, c.pais_id
  FROM clinicas c
  WHERE p_pais_id IS NULL OR c.pais_id = p_pais_id
  ORDER BY c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION obtener_clinicas_medico(p_medico_id UUID)
RETURNS TABLE (
  clinica_id UUID,
  clinica_nombre TEXT,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT mc.clinica_id, c.nombre, mc.es_principal
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_medico_id;
END;
$$;

CREATE OR REPLACE FUNCTION obtener_medicos_clinica(p_clinica_id UUID)
RETURNS TABLE (
  medico_id UUID,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT mc.medico_id, mc.es_principal
  FROM medico_clinicas mc
  WHERE mc.clinica_id = p_clinica_id;
END;
$$;

CREATE OR REPLACE FUNCTION obtener_clinica_principal_medico(p_medico_id UUID)
RETURNS TABLE (
  clinica_id UUID,
  es_principal BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT mc.clinica_id, mc.es_principal
  FROM medico_clinicas mc
  WHERE mc.medico_id = p_medico_id AND mc.es_principal = true
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION asociar_medico_clinica(
  p_medico_id UUID,
  p_clinica_id UUID,
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
-- 7. Función RPC: Obtener citas de una clínica (UUID)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_citas_clinica(p_clinica_id UUID DEFAULT NULL)
RETURNS TABLE (
  id INTEGER,
  medico_id UUID,
  paciente_id INTEGER,
  clinica_id UUID,
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
    c.clinica_id = p_clinica_id
    OR c.medico_id IN (SELECT mc.medico_id FROM medico_clinicas mc WHERE mc.clinica_id = p_clinica_id)
    OR (c.medico_id IS NULL AND c.estado IN ('solicitada', 'agendada') 
        AND (p_clinica_id IS NULL OR c.clinica_id IS NULL))
  ORDER BY c.fecha, c.hora_inicio;
END;
$$;

-- ============================================
-- 8. Función RPC: Obtener clínica de un usuario (UUID)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_clinica_usuario(p_user_id UUID)
RETURNS TABLE (
  clinica_id UUID,
  clinica_nombre TEXT,
  es_admin BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT mc.clinica_id, c.nombre, false
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_user_id AND mc.es_principal = true
  LIMIT 1;

  RETURN QUERY
  SELECT mc.clinica_id, c.nombre, true
  FROM medico_clinicas mc
  JOIN clinicas c ON c.id = mc.clinica_id
  WHERE mc.medico_id = p_user_id
  LIMIT 1;
END;
$$;

-- ============================================
-- 9. Recargar schema cache de PostgREST
-- ============================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
