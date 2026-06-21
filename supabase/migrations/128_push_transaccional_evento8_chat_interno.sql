-- ============================================================
-- Fix push transaccional · EVENTO 8 (chat interno proveedor → otros miembros de la conversación). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P405–P410. RPC nuevo → dormant hasta su hook.
--
-- El hueco actual: MensajesPage llama destinatarios_conversacion (ids al cliente) + enviar-push (abierto) con
-- cuerpo.slice(0,120) = LEAK de texto crudo + confused-deputy. El INSERT del mensaje ya es seguro:
-- chat_mensajes_internos NO tiene policy de INSERT → solo entra por enviar_mensaje_chat (DEFINER, autor_id=auth.uid()
-- server-set, gateado es_miembro_conversacion). → autor_id NO es libre (a diferencia del medico_id de evt6).
--
-- GATE = AUTOR ÚNICAMENTE (sin +super_admin): el invariante auth.uid()=autor es LOAD-BEARING para la derivación
-- (destinatarios_conversacion excluye auth.uid() + gatea es_miembro). Bajo un caller sa-no-autor excluiría al
-- principal equivocado y es_miembro(sa) fallaría → derivación vacía. Recipients DERIVADOS de la membresía (cero del
-- caller) → targeting arbitrario estructuralmente imposible. Contenido server SIN texto crudo.
--
-- LECCIÓN 39: notificar_chat_interno corre sp ''; sus inners public.destinatarios_conversacion y
-- public.es_miembro_conversacion ya llevan SET search_path='public' propio (verificado) → no heredan ''.
-- ============================================================

ALTER TABLE public.chat_mensajes_internos ADD COLUMN IF NOT EXISTS notificado boolean NOT NULL DEFAULT false;  -- idempotencia

CREATE OR REPLACE FUNCTION public.notificar_chat_interno(p_mensaje_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_msg RECORD; v_autor text; v_nid uuid; v_count int; rec record;
BEGIN
  -- (1) cargar
  SELECT * INTO v_msg FROM public.chat_mensajes_internos WHERE id = p_mensaje_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Mensaje no encontrado' USING ERRCODE = 'PT001'; END IF;
  -- (2) GATE = AUTOR ÚNICAMENTE (autor_id server-set; invariante load-bearing para la derivación). Sin +sa.
  IF NOT COALESCE(v_msg.autor_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'No autorizado para notificar este mensaje' USING ERRCODE = 'PT002';
  END IF;
  -- (3) CLAIM idempotencia atómico (tras el gate)
  UPDATE public.chat_mensajes_internos SET notificado = true WHERE id = p_mensaje_id AND notificado = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN RETURN; END IF;   -- ya notificado (retry/doble) → no-op
  -- (4) contenido server, SIN texto crudo
  v_autor := COALESCE((SELECT nombre_completo FROM public.cuentas_proveedor WHERE id = v_msg.autor_id), 'un compañero');
  -- recipients DERIVADOS (corre con auth.uid()=autor → excluye self + scope empresa/equipo/directo)
  FOR rec IN SELECT cuenta_id FROM public.destinatarios_conversacion(v_msg.conversacion_id) LOOP
    -- guard auth.users: INERTE (cuentas_proveedor.id_fkey → auth.users ON DELETE CASCADE; ruta inalcanzable). Defensa barata.
    IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = rec.cuenta_id) THEN
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
        VALUES (rec.cuenta_id, 'mensaje_interno', 'Nuevo mensaje', 'Tienes un nuevo mensaje de ' || v_autor || '.', '/proveedor/mensajes')
        RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);   -- tabla allowlisted; NO se toca la edge
    END IF;
  END LOOP;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_chat_interno(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_chat_interno(uuid) TO authenticated;   -- lo llama el autor; gate interno
