-- ============================================================
-- 065 · Las RPC de notificación devuelven los auth user_ids de
--       los destinatarios, para que el frontend dispare enviar-push.
-- ============================================================

-- notificar_laboratorio: además de insertar la notificación in-app,
-- devuelve los ids (auth.users) de las cuentas activas del laboratorio.
DROP FUNCTION IF EXISTS notificar_laboratorio(UUID, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION notificar_laboratorio(
  p_laboratorio_id UUID, p_tipo TEXT, p_titulo TEXT,
  p_mensaje TEXT DEFAULT NULL, p_accion_url TEXT DEFAULT NULL
) RETURNS UUID[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ids UUID[];
BEGIN
  INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
  SELECT cp.id, p_tipo, p_titulo, p_mensaje, p_accion_url
  FROM cuentas_proveedor cp
  WHERE cp.empresa_id = p_laboratorio_id AND cp.activo = true;

  SELECT array_agg(cp.id) INTO v_ids
  FROM cuentas_proveedor cp
  WHERE cp.empresa_id = p_laboratorio_id AND cp.activo = true;

  RETURN COALESCE(v_ids, ARRAY[]::UUID[]);
END $$;
GRANT EXECUTE ON FUNCTION notificar_laboratorio(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- notificar_resultado_examen: inserta avisos in-app (médico + paciente) y
-- devuelve {medico, paciente} con sus auth user_ids (los que existan) para push.
DROP FUNCTION IF EXISTS notificar_resultado_examen(INTEGER);
CREATE OR REPLACE FUNCTION notificar_resultado_examen(p_examen_id INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v examenes%ROWTYPE;
  v_paciente_auth UUID;
BEGIN
  SELECT * INTO v FROM examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;

  -- Solo el laboratorio dueño de la orden puede disparar el aviso
  IF v.laboratorio_id IS DISTINCT FROM mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF v.paciente_id IS NOT NULL THEN
    PERFORM notificar_paciente(
      v.paciente_id, 'examen_resultado', 'Resultado de examen listo',
      'Tu examen ' || v.tipo || ' ya tiene resultado.', '/paciente/examenes');
    SELECT auth_user_id INTO v_paciente_auth FROM pacientes WHERE id = v.paciente_id;
  END IF;

  IF v.medico_id IS NOT NULL THEN
    INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
      'El laboratorio subió el resultado de ' || v.tipo || ' (' || COALESCE(v.paciente_nombre, 'paciente') || ').',
      '/medico/citas');
  END IF;

  RETURN jsonb_build_object('medico', v.medico_id, 'paciente', v_paciente_auth);
END $$;
GRANT EXECUTE ON FUNCTION notificar_resultado_examen(INTEGER) TO authenticated;
