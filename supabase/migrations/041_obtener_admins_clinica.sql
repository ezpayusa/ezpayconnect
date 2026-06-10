-- ============================================================
-- 041: RPC para obtener los usuarios admin de una clínica
-- ------------------------------------------------------------
-- Lookup inverso de obtener_clinica_usuario: dado un clinica_id, devuelve
-- los auth_user_id que deben recibir el aviso de nuevas solicitudes de cita.
-- Prefiere usuarios con rol 'admin_clinica'; si no hay ninguno, cae a los
-- miembros principales (es_principal) para no dejar la clínica sin aviso.
-- SECURITY DEFINER: lo invoca el paciente al crear la cita (no puede leer
-- medico_clinicas/perfiles de otros por RLS).
-- ============================================================

CREATE OR REPLACE FUNCTION obtener_admins_clinica(p_clinica_id UUID)
RETURNS TABLE (user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT mc.medico_id
  FROM medico_clinicas mc
  JOIN perfiles p ON p.id = mc.medico_id
  WHERE mc.clinica_id = p_clinica_id
    AND p.rol = 'admin_clinica';

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT DISTINCT mc.medico_id
    FROM medico_clinicas mc
    WHERE mc.clinica_id = p_clinica_id
      AND mc.es_principal = true;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION obtener_admins_clinica(UUID) TO authenticated;
