-- ============================================
-- Migración 036: Agregar columnas faltantes a perfiles y medicos
-- Problema: Las tablas en producción no tienen todas las columnas que el código espera
-- Solución: Agregar columnas que faltan sin destruir datos existentes
-- ============================================

-- ============================================
-- 1. Asegurar que perfiles tiene todas las columnas necesarias
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'perfiles' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE perfiles ADD COLUMN avatar_url TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'perfiles' AND column_name = 'telefono'
  ) THEN
    ALTER TABLE perfiles ADD COLUMN telefono TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'perfiles' AND column_name = 'pais_id'
  ) THEN
    ALTER TABLE perfiles ADD COLUMN pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'perfiles' AND column_name = 'activo'
  ) THEN
    ALTER TABLE perfiles ADD COLUMN activo BOOLEAN NOT NULL DEFAULT true;
  END IF;
END $$;

-- ============================================
-- 2. Asegurar que medicos tiene todas las columnas necesarias
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'foto_url'
  ) THEN
    ALTER TABLE medicos ADD COLUMN foto_url TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'telefono'
  ) THEN
    ALTER TABLE medicos ADD COLUMN telefono TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'especialidad'
  ) THEN
    ALTER TABLE medicos ADD COLUMN especialidad TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'pais_id'
  ) THEN
    ALTER TABLE medicos ADD COLUMN pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'medicos' AND column_name = 'activo'
  ) THEN
    ALTER TABLE medicos ADD COLUMN activo BOOLEAN NOT NULL DEFAULT true;
  END IF;
END $$;

-- ============================================
-- 3. Recrear funciones RPC con las columnas ahora garantizadas
-- ============================================

-- 3.1 Listar médicos por país (UNION elimina duplicados automáticamente)
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
  RETURN QUERY
  SELECT m.id, m.nombre_completo, m.especialidad, m.foto_url, m.activo, m.pais_id
  FROM medicos m
  WHERE (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
    AND m.activo = true
  UNION
  SELECT p.id, p.nombre_completo, NULL::TEXT, p.avatar_url, p.activo, p.pais_id
  FROM perfiles p
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (p_pais_id IS NULL OR p.pais_id = p_pais_id OR p.pais_id IS NULL)
    AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id)
  ORDER BY nombre_completo;
END;
$$;

-- 3.2 Obtener médicos por IDs (UNION elimina duplicados)
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
  RETURN QUERY
  SELECT m.id, m.nombre_completo, m.especialidad
  FROM medicos m WHERE m.id = ANY(p_medico_ids)
  UNION
  SELECT p.id, p.nombre_completo, NULL::TEXT
  FROM perfiles p
  WHERE p.id = ANY(p_medico_ids) AND p.rol = 'medico'
    AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id);
END;
$$;

-- 3.3 Buscar médicos (UNION elimina duplicados)
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
  RETURN QUERY
  SELECT * FROM (
    SELECT m.id, m.nombre_completo, m.especialidad, m.foto_url
    FROM medicos m
    WHERE m.activo = true
      AND (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
      AND (p_query IS NULL OR p_query = ''
        OR m.nombre_completo ILIKE '%' || p_query || '%'
        OR m.especialidad ILIKE '%' || p_query || '%')
    UNION
    SELECT p.id, p.nombre_completo, NULL::TEXT, p.avatar_url
    FROM perfiles p
    WHERE p.rol = 'medico' AND p.activo = true
      AND (p_pais_id IS NULL OR p.pais_id = p_pais_id OR p.pais_id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id)
      AND (p_query IS NULL OR p_query = '' OR p.nombre_completo ILIKE '%' || p_query || '%')
  ) combined
  ORDER BY nombre_completo
  LIMIT p_limit;
END;
$$;

-- 3.4 Obtener perfil por ID
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
  SELECT p.id, p.rol::TEXT, p.nombre_completo, p.email, p.telefono,
         p.avatar_url, p.pais_id, p.activo, p.created_at, p.updated_at
  FROM perfiles p
  WHERE p.id = p_user_id;
END;
$$;

-- ============================================
-- 4. Función RPC: Asignar médico a cita (bypass RLS)
-- ============================================
CREATE OR REPLACE FUNCTION asignar_medico_cita(
  p_cita_id INTEGER,
  p_medico_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE citas
  SET medico_id = p_medico_id, estado = 'agendada'
  WHERE id = p_cita_id;
END;
$$;

-- ============================================
-- 5. Función RPC: Actualizar estado de cita (bypass RLS)
-- ============================================
CREATE OR REPLACE FUNCTION actualizar_estado_cita(
  p_cita_id INTEGER,
  p_estado TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE citas
  SET estado = p_estado
  WHERE id = p_cita_id;
END;
$$;

-- ============================================
-- 6. Recargar schema cache de PostgREST
-- ============================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
