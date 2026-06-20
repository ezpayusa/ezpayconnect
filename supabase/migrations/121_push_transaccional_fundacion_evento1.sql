-- ============================================================
-- Fix push transaccional · FUNDACIÓN + EVENTO 1 (cita). SEGURIDAD. Camino VIVO (l.25).
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Cierra el hueco de enviar-push (edge abierta: cualquier autenticado empuja
-- web-push con destinatarios + contenido/url arbitrarios). Modelo B (l.7): el push es efecto SERVER-SIDE
-- de la notificación in-app GATEADA. Decisiones Oscar: D1 B uniforme · D2 push-en-RPC con pg_net (NO
-- trigger por tabla: doble-empujaría para 2-8 aún sin migrar) · D3 allowlist accion_url por CHECK +
-- contenido server-side · D5 evento-por-evento.
--
-- Esta migración = FUNDACIÓN (idempotencia + CHECK url + secreto + helper pg_net) + EVENTO 1 como patrón
-- (notificar_cita_paciente). NO cierra aún el INSERT directo a las tablas (paso FINAL tras migrar los 8).
-- accion_url CHECK: recon confirmó 0 filas no-conformes en ambas tablas → entra sin romper datos vivos.
-- ============================================================

-- 0) Idempotencia del push (la edge marca push_enviado; no re-empuja)
ALTER TABLE public.notificaciones            ADD COLUMN IF NOT EXISTS push_enviado timestamptz;
ALTER TABLE public.notificaciones_pacientes  ADD COLUMN IF NOT EXISTS push_enviado timestamptz;

-- 1) accion_url allowlist (ruta interna; sin esquema/host → cierra phishing). 0 violaciones (recon).
ALTER TABLE public.notificaciones            DROP CONSTRAINT IF EXISTS notif_accion_url_interna;
ALTER TABLE public.notificaciones            ADD  CONSTRAINT notif_accion_url_interna
  CHECK (accion_url IS NULL OR accion_url ~ '^/[A-Za-z0-9/_-]*$');
ALTER TABLE public.notificaciones_pacientes  DROP CONSTRAINT IF EXISTS notif_pac_accion_url_interna;
ALTER TABLE public.notificaciones_pacientes  ADD  CONSTRAINT notif_pac_accion_url_interna
  CHECK (accion_url IS NULL OR accion_url ~ '^/[A-Za-z0-9/_-]*$');

-- 2) Secretos pg_net→edge (schema private = NO expuesto por PostgREST). Poblado FUERA DE BANDA por Oscar:
--    INSERT push_edge_url + push_secret (el mismo secret = env PUSH_NOTIF_SECRET de la edge). Vacío = push no-op.
CREATE TABLE IF NOT EXISTS private.app_secrets (nombre text PRIMARY KEY, valor text NOT NULL);
ALTER TABLE private.app_secrets ENABLE ROW LEVEL SECURITY;   -- sin policy = deny-all (defensa extra)
REVOKE ALL ON private.app_secrets FROM PUBLIC, anon, authenticated;

-- 3) Helper interno: dispara el push best-effort vía pg_net. NUNCA rompe la tx del evento transaccional.
CREATE OR REPLACE FUNCTION private.push_notificar(p_tabla text, p_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_tabla NOT IN ('notificaciones','notificaciones_pacientes') THEN RETURN; END IF;  -- allowlist dura (defensa)
  SELECT valor INTO v_url    FROM private.app_secrets WHERE nombre='push_edge_url';
  SELECT valor INTO v_secret FROM private.app_secrets WHERE nombre='push_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;   -- no configurado → no-op (in-app ya quedó)
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type','application/json','x-push-secret', v_secret),
    body    := jsonb_build_object('notification_id', p_id, 'tabla', p_tabla)
  );
EXCEPTION WHEN others THEN RETURN;   -- best-effort: el push jamás tumba el evento
END;
$function$;
REVOKE EXECUTE ON FUNCTION private.push_notificar(text,text) FROM PUBLIC, anon, authenticated;

-- 4) EVENTO 1 (patrón COMPLETO): notificar_cita_paciente — gateado por relación, contenido SERVER-SIDE.
--    El caller pasa SOLO (cita_id, evento). Reemplaza los TRES caminos del hook: notificar_paciente(raw)
--    + enviar-notificacion(general, target+contenido del caller, hueco gemelo) + enviar-push(lista).
--    Crea AMBOS in-app (campanita paciente + general) server-side; push SOLO desde la campanita (evita doble).
CREATE OR REPLACE FUNCTION public.notificar_cita_paciente(p_cita_id bigint, p_evento text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_c RECORD; v_titulo text; v_msg text; v_fecha text; v_hora text; v_id integer; v_auth uuid;
BEGIN
  SELECT * INTO v_c FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE de targeting: caller debe RELACIONARSE con la cita (su médico / su clínica / super_admin).
  -- COALESCE(...,false) OBLIGATORIO: si clinica_id IS NULL, 'NULL IN (...)' = NULL y 'false OR false OR NULL'
  -- = NULL → 'IF NOT NULL' se saltaría el RAISE = fail-open (lección notificar_laboratorio). Fail-closed.
  IF NOT COALESCE(
       private.tiene_rol(ARRAY['super_admin'])
    OR v_c.medico_id = auth.uid()
    OR (v_c.clinica_id IS NOT NULL AND v_c.clinica_id IN (SELECT private.clinicas_del_usuario()))
  , false) THEN RAISE EXCEPTION 'No autorizado para notificar esta cita' USING ERRCODE = 'PT002'; END IF;
  -- Contenido SERVER-SIDE por evento (el cliente no provee texto libre).
  v_fecha := to_char(v_c.fecha, 'DD/MM/YYYY'); v_hora := substr(v_c.hora_inicio::text, 1, 5);
  CASE p_evento
    WHEN 'confirmada'   THEN v_titulo := 'Cita confirmada';          v_msg := 'Tu cita para el '||v_fecha||' a las '||v_hora||' ha sido confirmada por el médico.';
    WHEN 'cancelada'    THEN v_titulo := 'Cita cancelada';           v_msg := 'Tu cita para el '||v_fecha||' a las '||v_hora||' ha sido cancelada. Por favor agenda una nueva cita.';
    WHEN 'en_curso'     THEN v_titulo := 'Tu consulta ha comenzado'; v_msg := 'El médico te ha llamado a consulta para tu cita del '||v_fecha||' a las '||v_hora||'.';
    WHEN 'completada'   THEN v_titulo := 'Consulta completada';      v_msg := 'Tu consulta del '||v_fecha||' a las '||v_hora||' ha finalizado. Revisa tus recetas y órdenes si aplica.';
    WHEN 'recordatorio' THEN v_titulo := 'Recordatorio de cita';     v_msg := 'Recordatorio: tienes una cita el '||v_fecha||' a las '||v_hora||'.';
    ELSE RAISE EXCEPTION 'Evento de cita inválido: %', p_evento USING ERRCODE = 'PT003';
  END CASE;
  -- in-app campanita del paciente (webapp) + push best-effort
  INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
    VALUES (v_c.paciente_id, 'cita', v_titulo, v_msg, '/paciente/citas', false)
    RETURNING id INTO v_id;
  PERFORM private.push_notificar('notificaciones_pacientes', v_id::text);   -- push server-side, best-effort
  -- in-app general (otros paneles) — reemplaza enviar-notificacion; SIN push (evita doble al mismo usuario)
  v_auth := (SELECT auth_user_id FROM public.pacientes WHERE id = v_c.paciente_id);
  IF v_auth IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v_auth, 'cita_'||p_evento, v_titulo, v_msg, '/paciente/citas');
  END IF;
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_cita_paciente(bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_cita_paciente(bigint,text) TO authenticated;
