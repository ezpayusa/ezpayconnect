-- ============================================================
-- Fix push transaccional · EVENTO 2 (useClinicaCitas). SEGURIDAD. Camino VIVO (l.25).
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. El gate de notificar_cita_paciente YA cubre el path clínica
-- (citas.clinica_id ∈ clinicas_del_usuario = obtener_clinica_usuario ∪ medico_clinicas) y ya es
-- COALESCE(...,false) fail-closed (probado por P360/P362) → 0 cambio de gate. Lo único que falta es
-- el evento 'asignada' (la clínica asigna médico a la cita), que el CASE no contemplaba. Esta migración
-- SOLO extiende el vocabulario de eventos (CREATE OR REPLACE, contenido server-side). Mensajes
-- generalizados (trigger-neutral: vale para médico [evt1] y clínica [evt2]). 'asignada' compone el
-- nombre del médico server-side (join medicos). Sin tocar gate/grants/push.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notificar_cita_paciente(p_cita_id bigint, p_evento text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_c RECORD; v_titulo text; v_msg text; v_fecha text; v_hora text; v_id integer; v_auth uuid; v_medico text;
BEGIN
  SELECT * INTO v_c FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE de targeting (sin cambios): médico de la cita / staff de su clínica / super_admin. COALESCE fail-closed.
  IF NOT COALESCE(
       private.tiene_rol(ARRAY['super_admin'])
    OR v_c.medico_id = auth.uid()
    OR (v_c.clinica_id IS NOT NULL AND v_c.clinica_id IN (SELECT private.clinicas_del_usuario()))
  , false) THEN RAISE EXCEPTION 'No autorizado para notificar esta cita' USING ERRCODE = 'PT002'; END IF;
  v_fecha := to_char(v_c.fecha, 'DD/MM/YYYY'); v_hora := substr(v_c.hora_inicio::text, 1, 5);
  CASE p_evento
    WHEN 'confirmada'   THEN v_titulo := 'Cita confirmada';          v_msg := 'Tu cita para el '||v_fecha||' a las '||v_hora||' ha sido confirmada.';
    WHEN 'cancelada'    THEN v_titulo := 'Cita cancelada';           v_msg := 'Tu cita para el '||v_fecha||' a las '||v_hora||' ha sido cancelada. Por favor agenda una nueva cita.';
    WHEN 'en_curso'     THEN v_titulo := 'Tu consulta ha comenzado'; v_msg := 'El médico te ha llamado a consulta para tu cita del '||v_fecha||' a las '||v_hora||'.';
    WHEN 'completada'   THEN v_titulo := 'Consulta completada';      v_msg := 'Tu consulta del '||v_fecha||' a las '||v_hora||' ha finalizado. Revisa tus recetas y órdenes si aplica.';
    WHEN 'recordatorio' THEN v_titulo := 'Recordatorio de cita';     v_msg := 'Recordatorio: tienes una cita el '||v_fecha||' a las '||v_hora||'.';
    WHEN 'asignada'     THEN
      v_medico := COALESCE((SELECT nombre_completo FROM public.medicos WHERE id = v_c.medico_id), 'tu médico');
      v_titulo := 'Médico asignado a tu cita';
      v_msg := 'Tu cita para el '||v_fecha||' a las '||v_hora||' ha sido asignada al Dr. '||v_medico||'.';
    ELSE RAISE EXCEPTION 'Evento de cita inválido: %', p_evento USING ERRCODE = 'PT003';
  END CASE;
  -- in-app campanita del paciente (webapp) + push best-effort
  INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
    VALUES (v_c.paciente_id, 'cita', v_titulo, v_msg, '/paciente/citas', false)
    RETURNING id INTO v_id;
  PERFORM private.push_notificar('notificaciones_pacientes', v_id::text);
  -- in-app general (otros paneles) — reemplaza enviar-notificacion; SIN push (evita doble)
  v_auth := (SELECT auth_user_id FROM public.pacientes WHERE id = v_c.paciente_id);
  IF v_auth IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v_auth, 'cita_'||p_evento, v_titulo, v_msg, '/paciente/citas');
  END IF;
  RETURN v_id;
END;
$function$;
