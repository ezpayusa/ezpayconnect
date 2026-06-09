-- ============================================
-- Migración 035: Fix PostgREST schema cache + funciones RPC
-- Problema: PostgREST no reconoce varias tablas/columnas
-- Solución: Funciones RPC que bypassan el schema cache
-- ============================================

-- ============================================
-- 0. Asegurar que medicos tiene todas las columnas que el frontend espera
-- ============================================
DO $$
BEGIN
  -- Agregar foto_url si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'foto_url'
  ) THEN
    ALTER TABLE medicos ADD COLUMN foto_url TEXT;
  END IF;

  -- Agregar activo si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'activo'
  ) THEN
    ALTER TABLE medicos ADD COLUMN activo BOOLEAN NOT NULL DEFAULT true;
  END IF;

  -- Agregar pais_id si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'pais_id'
  ) THEN
    ALTER TABLE medicos ADD COLUMN pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================
-- 1. Asegurar que medico_clinicas existe y clinica_id sea UUID
-- ============================================
DO $$
BEGIN
  -- Crear medico_clinicas si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_name = 'medico_clinicas'
  ) THEN
    CREATE TABLE medico_clinicas (
      id SERIAL PRIMARY KEY,
      medico_id UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
      clinica_id UUID NOT NULL REFERENCES clinicas(id) ON DELETE CASCADE,
      es_principal BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(medico_id, clinica_id)
    );
    
    ALTER TABLE medico_clinicas ENABLE ROW LEVEL SECURITY;
    
    CREATE POLICY "Service role all medico_clinicas" ON medico_clinicas
      FOR ALL USING (true) WITH CHECK (true);
  ELSE
    -- La tabla existe, verificar que clinica_id sea UUID
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'medico_clinicas' AND column_name = 'clinica_id'
      AND data_type = 'integer'
    ) THEN
      -- La columna es INTEGER, necesitamos convertirla a UUID
      ALTER TABLE medico_clinicas DROP CONSTRAINT IF EXISTS medico_clinicas_clinica_id_fkey;
      ALTER TABLE medico_clinicas ALTER COLUMN clinica_id TYPE UUID USING NULL;
      ALTER TABLE medico_clinicas ADD CONSTRAINT medico_clinicas_clinica_id_fkey
        FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- ============================================
-- 2. Función RPC: Listar médicos por país
-- ============================================
CREATE OR REPLACE FUNCTION listar_medicos_por_pais(p_pais_id UUID DEFAULT NULL)
RETURNS TABLE (
  id UUID,
  nombre_completo TEXT,
  especialidad TEXT,
  foto_url TEXT,
  activo BOOLEAN,
  pais_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Primero: médicos de la tabla medicos (invitados por clínicas)
  RETURN QUERY
  SELECT 
    m.id,
    m.nombre_completo,
    m.especialidad,
    m.foto_url,
    m.activo,
    m.pais_id
  FROM medicos m
  WHERE (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
    AND m.activo = true;

  -- Segundo: médicos de perfiles que NO están en medicos (registro directo)
  RETURN QUERY
  SELECT 
    p.id,
    p.nombre_completo,
    NULL::TEXT,
    p.avatar_url,
    p.activo,
    p.pais_id
  FROM perfiles p
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (p_pais_id IS NULL OR p.pais_id = p_pais_id OR p.pais_id IS NULL)
    AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id);
END;
$$;

-- ============================================
-- 3. Función RPC: Listar clínicas por país
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
-- 4. Función RPC: Obtener clínicas de un médico
-- ============================================
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
-- 5. Función RPC: Obtener datos de médicos por IDs
-- ============================================
CREATE OR REPLACE FUNCTION obtener_medicos_por_ids(p_medico_ids UUID[])
RETURNS TABLE (
  id UUID,
  nombre_completo TEXT,
  especialidad TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Primero: tabla medicos
  RETURN QUERY
  SELECT 
    m.id,
    m.nombre_completo,
    m.especialidad
  FROM medicos m
  WHERE m.id = ANY(p_medico_ids);

  -- Segundo: perfiles con rol medico que no están en medicos
  RETURN QUERY
  SELECT 
    p.id,
    p.nombre_completo,
    NULL::TEXT
  FROM perfiles p
  WHERE p.id = ANY(p_medico_ids)
    AND p.rol = 'medico'
    AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id);
END;
$$;

-- ============================================
-- 6. Función RPC: Buscar médicos por nombre/especialidad
-- ============================================
CREATE OR REPLACE FUNCTION buscar_medicos(
  p_query TEXT DEFAULT NULL,
  p_pais_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
  id UUID,
  nombre_completo TEXT,
  especialidad TEXT,
  foto_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Primero: tabla medicos
  RETURN QUERY
  SELECT 
    m.id,
    m.nombre_completo,
    m.especialidad,
    m.foto_url
  FROM medicos m
  WHERE m.activo = true
    AND (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
    AND (
      p_query IS NULL 
      OR p_query = ''
      OR m.nombre_completo ILIKE '%' || p_query || '%'
      OR m.especialidad ILIKE '%' || p_query || '%'
    );

  -- Segundo: perfiles con rol medico que no están en medicos
  RETURN QUERY
  SELECT 
    p.id,
    p.nombre_completo,
    NULL::TEXT,
    p.avatar_url
  FROM perfiles p
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (p_pais_id IS NULL OR p.pais_id = p_pais_id OR p.pais_id IS NULL)
    AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id)
    AND (
      p_query IS NULL 
      OR p_query = ''
      OR p.nombre_completo ILIKE '%' || p_query || '%'
    )
  ORDER BY nombre_completo
  LIMIT p_limit;
END;
$$;

-- ============================================
-- 7. Función RPC: Obtener clínica principal de un médico
-- ============================================
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
-- 8. Función RPC: Obtener médicos de una clínica
-- ============================================
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
  SELECT 
    mc.medico_id,
    mc.es_principal
  FROM medico_clinicas mc
  WHERE mc.clinica_id = p_clinica_id;
END;
$$;

-- ============================================
-- 9. Función RPC: Contar médicos por país
-- ============================================
CREATE OR REPLACE FUNCTION contar_medicos_por_pais(p_pais_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM medicos
  WHERE p_pais_id IS NULL OR pais_id = p_pais_id;
  RETURN v_count;
END;
$$;

-- ============================================
-- 10. Función RPC: Contar médicos por IDs
-- ============================================
CREATE OR REPLACE FUNCTION contar_medicos_por_ids(p_medico_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM medicos
  WHERE id = ANY(p_medico_ids);
  RETURN v_count;
END;
$$;

-- ============================================
-- 11. Función RPC: Asociar médico a clínica
-- ============================================
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
-- 12. Función RPC: Obtener perfil por ID
-- ============================================
CREATE OR REPLACE FUNCTION obtener_perfil(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  rol TEXT,
  nombre_completo TEXT,
  email TEXT,
  telefono TEXT,
  avatar_url TEXT,
  pais_id UUID,
  activo BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.rol::TEXT,
    p.nombre_completo,
    p.email,
    p.telefono,
    p.avatar_url,
    p.pais_id,
    p.activo,
    p.created_at,
    p.updated_at
  FROM perfiles p
  WHERE p.id = p_user_id;
END;
$$;

-- ============================================
-- 13. Trigger para notificar a PostgREST que recargue schema
-- ============================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
