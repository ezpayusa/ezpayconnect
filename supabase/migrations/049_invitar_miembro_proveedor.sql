-- ============================================================
-- 049: Invitar miembros del proveedor con cualquier rol
-- ------------------------------------------------------------
-- Hoy solo se podían invitar visitadores. Ahora el admin puede invitar a
-- cualquier rol del catálogo (supervisor, catalogo, marketing, finanzas, etc.)
-- desde "Equipo y Roles". La invitación guarda el rol y el registro lo aplica.
-- ============================================================

-- 1) La invitación ahora lleva el rol destino (default = visitador, retrocompatible).
ALTER TABLE invitaciones_visitador
  ADD COLUMN IF NOT EXISTS rol text NOT NULL DEFAULT 'visitador_medico';

-- 2) El registro desde invitación aplica el rol guardado en la invitación
--    (antes estaba hardcodeado a 'visitador_medico').
CREATE OR REPLACE FUNCTION registrar_visitador_desde_invitacion(
  p_token uuid,
  p_user_id uuid,
  p_email text,
  p_nombre_completo text,
  p_telefono text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invitacion RECORD;
  v_empresa_id UUID;
BEGIN
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

  IF EXISTS (SELECT 1 FROM cuentas_proveedor WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Este usuario ya tiene una cuenta de proveedor';
  END IF;

  INSERT INTO cuentas_proveedor (
    id, empresa_id, email, nombre_completo, telefono, rol_en_empresa, activo
  ) VALUES (
    p_user_id,
    v_empresa_id,
    p_email,
    p_nombre_completo,
    COALESCE(p_telefono, v_invitacion.telefono),
    COALESCE(v_invitacion.rol, 'visitador_medico'),
    true
  );

  UPDATE invitaciones_visitador SET estado = 'usada' WHERE id = v_invitacion.id;

  RETURN v_empresa_id;
END;
$$;

-- 3) RPC para que un admin invite a un miembro con un rol específico.
--    Devuelve el token de la invitación (el frontend arma el link de registro).
CREATE OR REPLACE FUNCTION invitar_miembro_proveedor(
  p_email text,
  p_nombre text,
  p_rol text,
  p_telefono text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_empresa_id uuid;
  v_caller_rol text;
  v_token uuid;
BEGIN
  SELECT empresa_id, rol_en_empresa INTO v_empresa_id, v_caller_rol
  FROM cuentas_proveedor WHERE id = auth.uid();

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede invitar miembros';
  END IF;

  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;

  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;

  INSERT INTO invitaciones_visitador (empresa_id, email, nombre_completo, telefono, rol, estado, expires_at)
  VALUES (v_empresa_id, lower(trim(p_email)), p_nombre, p_telefono, p_rol, 'pendiente', now() + interval '7 days')
  RETURNING token INTO v_token;

  RETURN v_token;
END;
$$;
GRANT EXECUTE ON FUNCTION invitar_miembro_proveedor(text, text, text, text) TO authenticated;
