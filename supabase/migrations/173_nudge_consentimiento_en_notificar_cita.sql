-- 173 nudge de consentimiento como 2da notificación en notificar_cita_paciente
-- APPEND-ONLY de comportamiento: no rompe el flujo de notificación de cita existente.
-- 1) amplía CHECK tipo con 'nudge_consentimiento'  2) índice de throttle  3) inserta bloque nudge en la función.
-- El nudge es best-effort: si el gate de permisos_pendientes_paciente rechaza al caller, NO tumba la notif de cita.

-- 1.a) ampliar el CHECK de tipo (conserva todos los valores previos + nuevo)
ALTER TABLE public.notificaciones_pacientes DROP CONSTRAINT IF EXISTS notificaciones_pacientes_tipo_check;
ALTER TABLE public.notificaciones_pacientes ADD CONSTRAINT notificaciones_pacientes_tipo_check
  CHECK (tipo = ANY (ARRAY['cita','receta','examen','mensaje','general','promocion','nudge_consentimiento']));

-- 1.b) índice para throttle por (paciente, tipo, fecha)
CREATE INDEX IF NOT EXISTS idx_notif_pac_tipo_fecha
  ON public.notificaciones_pacientes (paciente_id, tipo, created_at DESC);

-- 1.c) reescribir notificar_cita_paciente con el bloque de nudge insertado
CREATE OR REPLACE FUNCTION public.notificar_cita_paciente(p_cita_id bigint, p_evento text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_c RECORD; v_titulo text; v_msg text; v_fecha text; v_hora text; v_id integer; v_auth uuid; v_medico text;
        v_pend jsonb; v_nudge_id integer;
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
  -- NUDGE de consentimiento: solo en eventos de bienvenida a la cita, con throttle 7 días por (paciente,tipo)
  IF p_evento IN ('confirmada','asignada') THEN
    -- throttle: no insertar si ya hubo un nudge a este paciente en los últimos 7 días
    IF NOT EXISTS (
      SELECT 1 FROM public.notificaciones_pacientes
      WHERE paciente_id = v_c.paciente_id
        AND tipo = 'nudge_consentimiento'
        AND created_at > now() - interval '7 days'
    ) THEN
      -- best-effort: el gate de permisos_pendientes_paciente puede rechazar al caller; nunca tumbar la notif de cita
      BEGIN
        v_pend := public.permisos_pendientes_paciente(v_c.paciente_id);
      EXCEPTION WHEN OTHERS THEN
        v_pend := NULL;  -- sin nudge
      END;
      IF v_pend IS NOT NULL AND jsonb_array_length(v_pend) > 0 THEN
        INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
          VALUES (
            v_c.paciente_id,
            'nudge_consentimiento',
            'Tienes autorizaciones pendientes',
            'Para completar tu atención, revisa y firma tus autorizaciones en la app. Si prefieres, puedes hacerlo presencialmente el día de tu consulta presentando tu DPI.',
            '/paciente/autorizaciones',
            false
          )
          RETURNING id INTO v_nudge_id;
        PERFORM private.push_notificar('notificaciones_pacientes', v_nudge_id::text);
      END IF;
    END IF;
  END IF;
  -- in-app general (otros paneles) — reemplaza enviar-notificacion; SIN push (evita doble)
  v_auth := (SELECT auth_user_id FROM public.pacientes WHERE id = v_c.paciente_id);
  IF v_auth IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v_auth, 'cita_'||p_evento, v_titulo, v_msg, '/paciente/citas');
  END IF;
  RETURN v_id;
END;
$function$;
