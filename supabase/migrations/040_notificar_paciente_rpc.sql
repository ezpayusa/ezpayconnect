-- ============================================================
-- 040: RPC para crear notificaciones in-app del paciente (campanita del webapp)
-- ------------------------------------------------------------
-- La tabla notificaciones_pacientes tiene RLS que SOLO permite al propio
-- paciente (paciente_id IN pacientes del auth.uid()). Por eso clínica/médico
-- no pueden insertar notificaciones para el paciente desde su sesión.
-- Este RPC corre con SECURITY DEFINER para saltar el RLS de forma controlada,
-- igual que el resto de RPCs del proyecto (crear_cita, obtener_citas_clinica…).
-- ============================================================

CREATE OR REPLACE FUNCTION notificar_paciente(
  p_paciente_id INTEGER,
  p_tipo TEXT,
  p_titulo TEXT,
  p_mensaje TEXT DEFAULT NULL,
  p_accion_url TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id INTEGER;
BEGIN
  INSERT INTO notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
  VALUES (p_paciente_id, p_tipo, p_titulo, p_mensaje, p_accion_url, false)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION notificar_paciente(INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;
