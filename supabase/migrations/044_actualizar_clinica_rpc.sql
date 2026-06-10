-- ============================================================
-- 044: RPC para que el admin de una clínica edite sus datos
-- ------------------------------------------------------------
-- SECURITY DEFINER. Solo permite actualizar la clínica si el usuario es
-- miembro de esa clínica (medico_clinicas) o super_admin.
-- ============================================================

CREATE OR REPLACE FUNCTION actualizar_clinica(
  p_clinica_id UUID,
  p_nombre TEXT,
  p_direccion TEXT DEFAULT NULL,
  p_telefono TEXT DEFAULT NULL,
  p_email TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Autorización: miembro de la clínica o super_admin
  IF NOT (
    EXISTS (SELECT 1 FROM medico_clinicas mc WHERE mc.clinica_id = p_clinica_id AND mc.medico_id = auth.uid())
    OR EXISTS (SELECT 1 FROM perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')
  ) THEN
    RAISE EXCEPTION 'No autorizado para editar esta clínica';
  END IF;

  UPDATE clinicas
  SET nombre = p_nombre,
      direccion = p_direccion,
      telefono = p_telefono,
      email = p_email
  WHERE id = p_clinica_id;
END;
$$;

GRANT EXECUTE ON FUNCTION actualizar_clinica(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;
