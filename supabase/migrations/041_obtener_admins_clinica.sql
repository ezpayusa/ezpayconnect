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

-- Devuelve los miembros de la clínica que pueden gestionar/aprobar citas:
-- admin_clinica o super_admin (los médicos normales NO se incluyen aquí; ellos
-- ya reciben su propio aviso "Nueva cita solicitada" cuando son el médico
-- elegido). Así un super_admin que administra la clínica también recibe el aviso.
CREATE OR REPLACE FUNCTION obtener_admins_clinica(p_clinica_id UUID)
RETURNS TABLE (user_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT mc.medico_id
  FROM medico_clinicas mc
  JOIN perfiles p ON p.id = mc.medico_id
  WHERE mc.clinica_id = p_clinica_id
    AND p.rol IN ('admin_clinica', 'super_admin');
$$;

GRANT EXECUTE ON FUNCTION obtener_admins_clinica(UUID) TO authenticated;
