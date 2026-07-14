-- 259: marcar-leído del lado PACIENTE (espejo de leer_hilo_chat_medico, mig 257).
-- El paciente NO tiene policy UPDATE en chat_mensajes → su .update() directo afecta 0 filas
-- silenciosamente y el mensaje del médico nunca queda leido=true. Esta RPC DEFINER lo resuelve:
-- marca leídos SOLO los mensajes del MÉDICO en el hilo (paciente_id, medico_id) del caller.
-- Errcodes PT030/PT031/PT032 (familia PT).
CREATE OR REPLACE FUNCTION public.marcar_leido_chat_paciente(p_medico_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_pid integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT030'; END IF;

  SELECT p.id INTO v_pid FROM public.pacientes p WHERE p.auth_user_id = v_uid LIMIT 1;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'No autorizado: el usuario no es un paciente' USING ERRCODE = 'PT031'; END IF;

  IF NOT private.paciente_relacion_medico(v_pid, p_medico_id) THEN
    RAISE EXCEPTION 'No autorizado: sin relación con ese médico' USING ERRCODE = 'PT032';
  END IF;

  -- marca leídos SOLO los mensajes del médico en ESE hilo (espejo del lado médico)
  UPDATE public.chat_mensajes AS cm
     SET leido = true
   WHERE cm.paciente_id = v_pid
     AND cm.medico_id   = p_medico_id
     AND cm.remitente   = 'medico'
     AND cm.leido       = false;
END;
$function$;

REVOKE ALL     ON FUNCTION public.marcar_leido_chat_paciente(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.marcar_leido_chat_paciente(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.marcar_leido_chat_paciente(uuid) TO authenticated;
