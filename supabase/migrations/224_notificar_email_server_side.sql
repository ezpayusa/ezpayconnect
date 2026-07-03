-- ============================================================================
-- Migración 224: notificar-email pasa a server-to-server (calco de push transaccional, mig 121)
-- ============================================================================
-- GAP QUE CIERRA: notificar-email usaba service_role SIN gate y aceptaba to/subject/html ARBITRARIOS
-- del body → cualquier usuario logueado podía enviar emails desde no-reply@ezpayconnect.com (phishing).
-- Modelo (igual que el push, mig 121): el email es un EFECTO SERVER-SIDE de las RPCs de visita YA
-- gateadas (notificar_visita_propuesta / notificar_visita_resultado, ownership fail-closed). El front
-- deja de armar html y de llamar la edge directo; las RPCs disparan el email vía pg_net + secreto
-- compartido (x-email-secret), y la edge re-deriva to/contenido de la fila (no acepta a-quién ni qué).
--
-- Reusa la infra del push: private.app_secrets (ya existe, deny-all) para url+secreto; net.http_post
-- async best-effort. El secreto (filas email_edge_url/email_secret) lo puebla Oscar FUERA DE BANDA;
-- mientras estén vacías, email_notificar es no-op → SEGURO POR DEFECTO.
--
-- Idempotencia: 2 columnas claim en visitas_agendadas (email_propuesta_enviado / email_resultado_enviado)
-- → el email de cada evento se dispara UNA sola vez (retries/dobles llamadas no reenvían).
-- ============================================================================

BEGIN;

-- 1a) Idempotencia: claim por evento (NULL = aún no enviado). Espejo de notificaciones.push_enviado.
ALTER TABLE public.visitas_agendadas
  ADD COLUMN IF NOT EXISTS email_propuesta_enviado timestamptz,
  ADD COLUMN IF NOT EXISTS email_resultado_enviado timestamptz;

-- 1b) Helper: dispara el email best-effort vía pg_net. Calco EXACTO de private.push_notificar (mig 121).
CREATE OR REPLACE FUNCTION private.email_notificar(p_visita_id uuid, p_tipo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_tipo NOT IN ('propuesta','aprobada','rechazada') THEN RETURN; END IF;  -- allowlist dura (defensa)
  SELECT valor INTO v_url    FROM private.app_secrets WHERE nombre='email_edge_url';
  SELECT valor INTO v_secret FROM private.app_secrets WHERE nombre='email_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;   -- no configurado → no-op (seguro por defecto)
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type','application/json','x-email-secret', v_secret),
    body    := jsonb_build_object('visita_id', p_visita_id, 'tipo', p_tipo)
  );
EXCEPTION WHEN others THEN RETURN;   -- best-effort: el email jamás tumba la tx del evento
END;
$function$;
REVOKE EXECUTE ON FUNCTION private.email_notificar(uuid,text) FROM PUBLIC, anon, authenticated;

-- 1c) notificar_visita_propuesta: cuerpo/firma INTACTOS + claim & disparo del email al final.
CREATE OR REPLACE FUNCTION public.notificar_visita_propuesta(p_visita_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; rec record;
BEGIN
  SELECT empresa_id, propuesta_por INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = creador de la visita (propuesta_por, col registrada). COALESCE fail-closed.
  IF NOT COALESCE(v.propuesta_por = auth.uid(), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- target: admins/editores de la empresa de la visita (derivado; excluye al proponente)
  FOR rec IN SELECT id FROM public.cuentas_proveedor
             WHERE empresa_id = v.empresa_id AND activo = true AND rol_en_empresa IN ('admin','editor') AND id <> auth.uid() LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.id, 'visita_propuesta', 'Nueva visita propuesta', 'Tienes una nueva visita propuesta para revisar.', '/proveedor/visitador/admin-aprobar');
  END LOOP;
  -- EMAIL server-side (best-effort, una sola vez por claim idempotente). El resto del cuerpo NO cambió.
  UPDATE public.visitas_agendadas SET email_propuesta_enviado = now()
    WHERE id = p_visita_id AND email_propuesta_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, 'propuesta'); END IF;
END;
$function$;

-- 1d) notificar_visita_resultado: cuerpo/firma INTACTOS + deriva tipo de email de la rama de estado
--     existente (confirmada→aprobada, rechazada→rechazada) + claim & disparo.
CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text; v_email_tipo text;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = admin/editor de la empresa de la visita. COALESCE fail-closed.
  IF NOT COALESCE((SELECT true FROM public.cuentas_proveedor WHERE id = auth.uid() AND empresa_id = v.empresa_id
                   AND activo = true AND rol_en_empresa IN ('admin','editor') LIMIT 1), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  IF v.estado NOT IN ('confirmada','rechazada') THEN RETURN; END IF;  -- estado notificable (resultado real)
  -- GATE RELACIÓN: cuenta_proveedor_id caller-libre en el INSERT de visitas → exigir que pertenezca a la empresa
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;
  -- rama fail-closed por estado del ref (deriva también el tipo de email)
  IF v.estado = 'confirmada' THEN
    v_tipo := 'visita_aprobada';  v_titulo := 'Visita aprobada';  v_msg := 'Tu visita propuesta fue confirmada.'; v_email_tipo := 'aprobada';
  ELSIF v.estado = 'rechazada' THEN
    v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.'; v_email_tipo := 'rechazada';
  END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, '/proveedor/visitador');
  -- EMAIL server-side (best-effort, una sola vez por claim). El resto del cuerpo NO cambió.
  UPDATE public.visitas_agendadas SET email_resultado_enviado = now()
    WHERE id = p_visita_id AND email_resultado_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, v_email_tipo); END IF;
END;
$function$;

COMMIT;
