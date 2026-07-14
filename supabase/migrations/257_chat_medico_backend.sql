-- 257: lado MÉDICO del chat (chat_mensajes). Hasta ahora solo existía el lado paciente:
--   2 policies ("Paciente ve sus mensajes" SELECT, "Paciente envía mensajes" INSERT) + notificar_chat(integer).
-- El médico no tenía forma de leer/responder. Esta migración agrega 4 objetos, todos ADITIVOS:
--   1) policy SELECT mínima para que Realtime le entregue al médico SUS hilos.
--   2) listar_hilos_chat_medico()  — hilos del médico con último mensaje + no-leídos.
--   3) leer_hilo_chat_medico(pac)  — mensajes del hilo + marca leídos los del paciente.
--   4) enviar_mensaje_chat_medico(pac, texto) — inserta respuesta del médico, devuelve id.
-- Hilo = par (paciente_id, medico_id). Autorización real = medico_id=auth.uid() + private.paciente_relacion_medico.
-- Notificación: NO se llama notificar_chat aquí; el front la invoca best-effort DESPUÉS con el id devuelto (igual que el paciente).
-- Errcodes PT0xx por consistencia con notificar_chat (PT001/PT002).

-- ── OBJETO 1: policy SELECT mínima para el médico ──────────────────────────────
-- Aditiva. NO toca las 2 policies del paciente. Un médico solo ve filas donde él es medico_id
-- Y existe relación con el paciente. paciente_id NULL o medico_id ajeno → no matchea.
-- Realtime respeta RLS → el médico recibe SOLO sus hilos.
CREATE POLICY "Medico ve mensajes de sus pacientes"
ON public.chat_mensajes FOR SELECT
USING (
  medico_id = auth.uid()
  AND private.paciente_relacion_medico(paciente_id, medico_id)
);

-- ── OBJETO 2: listar hilos del médico ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.listar_hilos_chat_medico()
 RETURNS TABLE(
   paciente_id          integer,
   paciente_nombre      text,
   paciente_apellido    text,
   paciente_foto_path   text,
   ultimo_mensaje       text,
   ultimo_at            timestamptz,
   no_leidos            bigint
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT010'; END IF;

  RETURN QUERY
  SELECT
    hilos.pid,
    pa.nombre,
    pa.apellido,
    pa.foto_path,
    ult.mensaje,
    ult.created_at,
    COALESCE(nl.n, 0)::bigint
  FROM (
    -- un hilo por paciente donde este médico es el medico_id Y hay relación
    SELECT DISTINCT cm.paciente_id AS pid
    FROM public.chat_mensajes cm
    WHERE cm.medico_id = v_uid
      AND private.paciente_relacion_medico(cm.paciente_id, v_uid)
  ) hilos
  JOIN public.pacientes pa ON pa.id = hilos.pid
  JOIN LATERAL (
    SELECT m.mensaje, m.created_at
    FROM public.chat_mensajes m
    WHERE m.medico_id = v_uid AND m.paciente_id = hilos.pid
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT 1
  ) ult ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS n
    FROM public.chat_mensajes m
    WHERE m.medico_id = v_uid AND m.paciente_id = hilos.pid
      AND m.remitente = 'paciente' AND m.leido = false
  ) nl ON true
  ORDER BY ult.created_at DESC;
END;
$function$;

REVOKE ALL     ON FUNCTION public.listar_hilos_chat_medico()      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.listar_hilos_chat_medico()      FROM anon;
GRANT  EXECUTE ON FUNCTION public.listar_hilos_chat_medico()      TO authenticated;

-- ── OBJETO 3: leer un hilo + marcar leídos ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.leer_hilo_chat_medico(p_paciente_id integer)
 RETURNS TABLE(
   id          integer,
   remitente   text,
   mensaje     text,
   leido       boolean,
   created_at  timestamptz
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT011'; END IF;
  IF NOT private.paciente_relacion_medico(p_paciente_id, v_uid) THEN
    RAISE EXCEPTION 'No autorizado: sin relación con ese paciente' USING ERRCODE = 'PT011';
  END IF;

  -- marca leídos los mensajes DEL PACIENTE en este hilo (corre como DEFINER → sin policy UPDATE)
  UPDATE public.chat_mensajes AS cm
     SET leido = true
   WHERE cm.paciente_id = p_paciente_id
     AND cm.medico_id   = v_uid
     AND cm.remitente   = 'paciente'
     AND cm.leido       = false;

  RETURN QUERY
  SELECT cm.id, cm.remitente, cm.mensaje, cm.leido, cm.created_at
  FROM public.chat_mensajes cm
  WHERE cm.paciente_id = p_paciente_id
    AND cm.medico_id   = v_uid
  ORDER BY cm.created_at ASC, cm.id ASC;
END;
$function$;

REVOKE ALL     ON FUNCTION public.leer_hilo_chat_medico(integer)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.leer_hilo_chat_medico(integer)  FROM anon;
GRANT  EXECUTE ON FUNCTION public.leer_hilo_chat_medico(integer)  TO authenticated;

-- ── OBJETO 4: enviar mensaje del médico ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enviar_mensaje_chat_medico(p_paciente_id integer, p_mensaje text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_id  integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT012'; END IF;
  IF NOT private.paciente_relacion_medico(p_paciente_id, v_uid) THEN
    RAISE EXCEPTION 'No autorizado: sin relación con ese paciente' USING ERRCODE = 'PT013';
  END IF;
  IF btrim(COALESCE(p_mensaje, '')) = '' THEN
    RAISE EXCEPTION 'Mensaje vacío' USING ERRCODE = 'PT014';
  END IF;

  INSERT INTO public.chat_mensajes (paciente_id, medico_id, remitente, mensaje, leido)
  VALUES (p_paciente_id, v_uid, 'medico', btrim(p_mensaje), false)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL     ON FUNCTION public.enviar_mensaje_chat_medico(integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enviar_mensaje_chat_medico(integer, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.enviar_mensaje_chat_medico(integer, text) TO authenticated;
