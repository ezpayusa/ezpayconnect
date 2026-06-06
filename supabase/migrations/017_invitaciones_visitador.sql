-- ============================================
-- INVITACIONES DE VISITADORES MÉDICOS
-- Admin genera token → comparte por WhatsApp
-- Visitador usa token para registrarse
-- ============================================

CREATE TABLE IF NOT EXISTS invitaciones_visitador (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  nombre_completo TEXT NOT NULL,
  telefono TEXT,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'usada', 'expirada')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invitaciones_token ON invitaciones_visitador(token);
CREATE INDEX idx_invitaciones_empresa ON invitaciones_visitador(empresa_id);
CREATE INDEX idx_invitaciones_estado ON invitaciones_visitador(estado);

-- RLS: solo admins de la empresa pueden ver/crear invitaciones de su empresa
ALTER TABLE invitaciones_visitador ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invitaciones_select_admin"
  ON invitaciones_visitador FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM cuentas_proveedor cp
      WHERE cp.id = auth.uid()
        AND cp.empresa_id = invitaciones_visitador.empresa_id
        AND cp.activo = true
        AND cp.rol_en_empresa IN ('admin', 'editor')
    )
  );

CREATE POLICY "invitaciones_insert_admin"
  ON invitaciones_visitador FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM cuentas_proveedor cp
      WHERE cp.id = auth.uid()
        AND cp.empresa_id = invitaciones_visitador.empresa_id
        AND cp.activo = true
        AND cp.rol_en_empresa IN ('admin', 'editor')
    )
  );

-- No se necesita política pública: la validación de token se hace via Edge Function con service_role

-- Función para registrar visitador desde invitación (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION registrar_visitador_desde_invitacion(
  p_token UUID,
  p_user_id UUID,
  p_email TEXT,
  p_nombre_completo TEXT,
  p_telefono TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invitacion RECORD;
  v_empresa_id UUID;
BEGIN
  -- Buscar invitación válida
  SELECT * INTO v_invitacion
  FROM invitaciones_visitador
  WHERE token = p_token
    AND estado = 'pendiente'
    AND expires_at > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitación no válida o expirada';
  END IF;

  v_empresa_id := v_invitacion.empresa_id;

  -- Verificar que el user_id no esté ya en cuentas_proveedor
  IF EXISTS (SELECT 1 FROM cuentas_proveedor WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Este usuario ya tiene una cuenta de proveedor';
  END IF;

  -- Crear cuenta de proveedor para el visitador
  INSERT INTO cuentas_proveedor (
    id,
    empresa_id,
    email,
    nombre_completo,
    telefono,
    rol_en_empresa,
    activo
  ) VALUES (
    p_user_id,
    v_empresa_id,
    p_email,
    p_nombre_completo,
    COALESCE(p_telefono, v_invitacion.telefono),
    'visitador_medico',
    true
  );

  -- Marcar invitación como usada
  UPDATE invitaciones_visitador
  SET estado = 'usada'
  WHERE id = v_invitacion.id;

  RETURN v_empresa_id;
END;
$$;

-- Función para obtener invitaciones con conteo de estado
CREATE OR REPLACE FUNCTION get_invitaciones_empresa(p_empresa_id UUID)
RETURNS TABLE (
  id UUID,
  token UUID,
  email TEXT,
  nombre_completo TEXT,
  telefono TEXT,
  estado TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    i.id,
    i.token,
    i.email,
    i.nombre_completo,
    i.telefono,
    i.estado,
    i.expires_at,
    i.created_at
  FROM invitaciones_visitador i
  WHERE i.empresa_id = p_empresa_id
  ORDER BY i.created_at DESC;
END;
$$;
