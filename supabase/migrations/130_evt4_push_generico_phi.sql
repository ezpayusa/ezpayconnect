-- ============================================================
-- Fix push transaccional · EVENTO 4 — cuerpo de push GENÉRICO (PHI fuera del lock screen). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Precedente evt5/evt7: el contenido que el edge re-deriva del row va al lock screen
-- → debe ser mínimo. Hoy el mensaje incluye el TIPO de examen (paciente) y TIPO + NOMBRE del paciente (médico)
-- → PHI expuesta en notificación push. mig 130 genericiza SOLO el mensaje almacenado de las 2 filas; el detalle
-- (tipo, paciente) vive in-app tras la accion_url. titulo + accion_url sin cambios.
--
-- l.50: CREATE OR REPLACE NO preserva atributos → RE-DECLARO SECURITY DEFINER + SET search_path=''. l.39 refs calificadas.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_paciente_auth uuid; v_pid integer; v_mid uuid;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  -- gate: SOLO el lab dueño de la orden (null-safe IS DISTINCT FROM → fail-closed)
  IF v.laboratorio_id IS DISTINCT FROM public.mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- PACIENTE: insert DIRECTO (relación = dueño de la orden). tipo 'examen'. mensaje GENÉRICO (sin tipo). push por id.
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen listo', 'Tienes un nuevo resultado de examen disponible.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    SELECT auth_user_id INTO v_paciente_auth FROM public.pacientes WHERE id = v.paciente_id;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
  -- MÉDICO: notificaciones (tipo 'examen_resultado'). mensaje GENÉRICO (sin tipo ni nombre). push por id.
  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo', 'Un paciente tiene un resultado de examen nuevo.', '/medico/citas')
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;
  END IF;
  RETURN jsonb_build_object('medico', v.medico_id, 'paciente', v_paciente_auth);   -- back-compat (el hook lo ignora)
END;
$function$;
