-- ============================================================
-- Fix push transaccional · EVENTO 6 (chat paciente↔médico). SEGURIDAD. Camino VIVO.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P385–P393. RPC nuevo SIMÉTRICO → dormant hasta su hook (lleva push
-- desde el inicio). El hook (useWebAppChat) cablea SOLO paciente→médico; la rama médico→paciente queda lista
-- pero dormant (se activa cuando exista UI de chat del lado médico).
--
-- ORDEN OBLIGATORIO: (1) cargar v_msg → (2) GATE (caller=remitente) → (3) CLAIM idempotencia → (4) notificar.
-- El gate ANTES del claim: si el claim corriera primero, un no-remitente quemaría 'notificado' (UPDATE DEFINER
-- bypassa RLS) y suprimiría la notif del remitente legítimo.
--
-- GATE: caller = REMITENTE del mensaje (derivado de auth.uid), COALESCE fail-closed (+super_admin). remitente
-- es NOT NULL + CHECK paciente/medico; el ELSE (inválido) DENIEGA igual (defensa). Destinatario = el OTRO
-- participante, derivado del mensaje. Contenido server-compuesto SIN el texto crudo (cierra el leak actual del
-- hook, que mandaba mensaje.slice(0,100) al push). Guard médico-huérfano (eco evt5): si no está en auth.users,
-- se salta su fila sin abortar. push_notificar por id + claim atómico de la edge.
-- ============================================================

ALTER TABLE public.chat_mensajes ADD COLUMN IF NOT EXISTS notificado boolean DEFAULT false;  -- idempotencia por mensaje

CREATE OR REPLACE FUNCTION public.notificar_chat(p_mensaje_id integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_msg RECORD; v_nombre text; v_nid uuid; v_pid integer;
BEGIN
  -- (1) cargar
  SELECT * INTO v_msg FROM public.chat_mensajes WHERE id = p_mensaje_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Mensaje no encontrado' USING ERRCODE = 'PT001'; END IF;
  -- (2) GATE: caller = remitente (ANTES del claim). COALESCE fail-closed.
  IF NOT COALESCE(
    CASE v_msg.remitente
      WHEN 'paciente' THEN private.tiene_rol(ARRAY['super_admin']) OR v_msg.paciente_id IN (SELECT id FROM public.pacientes WHERE auth_user_id = auth.uid())
      WHEN 'medico'   THEN private.tiene_rol(ARRAY['super_admin']) OR v_msg.medico_id = auth.uid()
      ELSE false
    END, false) THEN RAISE EXCEPTION 'No autorizado para notificar este mensaje' USING ERRCODE = 'PT002'; END IF;
  -- (2.5) GATE RELACIÓN: el medico_id del mensaje es libre en el INSERT RLS de chat_mensajes (solo gatea
  -- paciente_id) → un paciente podría nombrar a CUALQUIER médico y spamearlo. Exigir relación legítima
  -- paciente↔médico (cita o médico primario/asignado). Sin relación → SKIP (no notifica a médico ajeno,
  -- SIN reclamar el flag). Va DESPUÉS del caller-gate y ANTES del claim. EXISTS = no-null (sin l.36, DEFINER).
  IF NOT (
       EXISTS (SELECT 1 FROM public.citas c WHERE c.paciente_id = v_msg.paciente_id AND c.medico_id = v_msg.medico_id)
    OR EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = v_msg.paciente_id AND (p.medico_primario_id = v_msg.medico_id OR p.medico_id = v_msg.medico_id))
  ) THEN RETURN; END IF;
  -- (3) CLAIM idempotencia (tras los gates): solo el primero notifica
  UPDATE public.chat_mensajes SET notificado = true WHERE id = p_mensaje_id AND notificado IS NOT TRUE;
  IF NOT FOUND THEN RETURN; END IF;   -- ya notificado (retry/doble) → no-op
  -- (4) notificar al OTRO participante, derivado del mensaje; contenido server, SIN texto crudo
  IF v_msg.remitente = 'paciente' THEN
    -- destinatario = médico (guard auth.users; eco evt5: médico sin auth → skip sin abortar)
    v_nombre := COALESCE((SELECT trim(nombre || ' ' || COALESCE(apellido,'')) FROM public.pacientes WHERE id = v_msg.paciente_id), 'un paciente');
    IF v_msg.medico_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_msg.medico_id) THEN
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
        VALUES (v_msg.medico_id, 'mensaje', 'Nuevo mensaje', 'Tienes un nuevo mensaje de '||v_nombre||'.', '/medico/chat')
        RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);
    END IF;
  ELSE
    -- remitente='medico' → destinatario = paciente (rama dormant hasta UI de chat médico)
    v_nombre := COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = v_msg.medico_id), 'tu médico');
    IF v_msg.paciente_id IS NOT NULL THEN
      INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
        VALUES (v_msg.paciente_id, 'mensaje', 'Nuevo mensaje', 'Tienes un nuevo mensaje de '||v_nombre||'.', '/paciente/chat', false)
        RETURNING id INTO v_pid;
      PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text);
    END IF;
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_chat(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_chat(integer) TO authenticated;   -- lo llama el remitente; gate interno
