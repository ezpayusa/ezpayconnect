-- ============================================================
-- Fix confused-deputy · HELPER enviar-notificacion → 6 RPCs gateados (in-app). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P414–P418. Los 6 RPCs nuevos → DORMANT hasta sus hooks.
-- Reemplazan los 7 call-sites del helper crearNotificacionInApp (edge abierto enviar-notificacion).
-- Comunes: DEFINER + sp '' (l.39 refs calificadas); REVOKE anon/PUBLIC + GRANT authenticated; IN-APP ONLY
-- (sin push_notificar); contenido server-compuesto desde el REF (cero texto del caller); accion_url interna.
-- Guard huérfano INERTE (cuentas_proveedor.id FK→auth.users; no se prueba ruta inalcanzable, l.49).
-- Helpers inner sp-safe: private.tiene_rol (sp ''), mi_empresa_proveedor / obtener_usuarios_empresa /
-- obtener_admins_ezpay (sp 'public') → no heredan ''.
-- ============================================================

-- idempotencia para evt7 (campaña enviada → anti-spam a admins EzPay)
ALTER TABLE public.solicitudes_campana ADD COLUMN IF NOT EXISTS notificado_envio boolean NOT NULL DEFAULT false;

-- ----- GRUPO A: admin EzPay → users de empresa (gate tiene_rol; estado leído del ref) -----

CREATE OR REPLACE FUNCTION public.notificar_empresa_estado(p_empresa_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_estado text; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado INTO v_estado FROM public.empresas_proveedoras WHERE id = p_empresa_id;
  IF NOT FOUND OR v_estado IS NULL THEN RETURN; END IF;
  v_titulo := CASE WHEN v_estado = 'activa' THEN 'Empresa aprobada' ELSE 'Estado de tu empresa actualizado' END;
  v_msg := CASE WHEN v_estado = 'activa' THEN 'Tu empresa fue aprobada. Ya puedes operar en EzPayConnect.'
                ELSE 'El estado de tu empresa cambió a: ' || v_estado || '.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(p_empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'empresa', v_titulo, v_msg, '/proveedor/dashboard');
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notificar_pago_resultado(p_pago_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, empresa_id INTO v FROM public.pagos_proveedor WHERE id = p_pago_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('verificado','rechazado') THEN RETURN; END IF;  -- estado notificable
  v_titulo := CASE WHEN v.estado = 'verificado' THEN 'Pago verificado' ELSE 'Pago rechazado' END;
  v_msg := CASE WHEN v.estado = 'verificado' THEN 'Tu pago fue verificado y el servicio quedó activo.'
                ELSE 'Tu pago fue rechazado. Revisa el comprobante o contacta a EzPayConnect.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'pago', v_titulo, v_msg, '/proveedor/pagos');
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notificar_campana_resultado(p_solicitud_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, titulo, empresa_id, notas_admin INTO v FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('publicada','rechazada') THEN RETURN; END IF;  -- estado notificable
  IF v.estado = 'publicada' THEN
    v_titulo := 'Campaña aprobada';
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue aprobada y publicada.';
  ELSE
    v_titulo := 'Campaña rechazada';
    -- notas_admin PERSISTIDO en el ref (no param del caller) → se incluye si existe
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue rechazada.' || COALESCE(' Motivo: ' || NULLIF(v.notas_admin,''), '');
  END IF;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'campana', v_titulo, v_msg, '/proveedor/publicidad/campanas');
  END LOOP;
END;
$function$;

-- ----- GRUPO B: proveedor → admins EzPay (gate dueño + estado; idempotencia) -----

CREATE OR REPLACE FUNCTION public.notificar_campana_enviada(p_solicitud_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_count int; v_msg text; rec record;
BEGIN
  SELECT estado, empresa_id, monto_pagado INTO v FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller dueño de la empresa de la solicitud + estado='enviada'. COALESCE fail-closed.
  IF NOT COALESCE(v.empresa_id = public.mi_empresa_proveedor() AND v.estado = 'enviada', false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- CLAIM idempotencia (tras el gate; l.54: denegado NO quema el flag)
  UPDATE public.solicitudes_campana SET notificado_envio = true WHERE id = p_solicitud_id AND notificado_envio = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN RETURN; END IF;
  v_msg := 'Una empresa envió una campaña a revisión por ' || COALESCE(v.monto_pagado::text, 's/d') || '.';
  FOR rec IN SELECT user_id FROM public.obtener_admins_ezpay() LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'campana', 'Nueva solicitud de publicidad', v_msg, '/admin-ezpay/solicitudes-campana');
  END LOOP;
END;
$function$;

-- re-submission (rechazada/borrador → enviada) resetea el flag → re-notifica. dormant-safe (flag no se consume hasta el hook).
CREATE OR REPLACE FUNCTION private.reset_notificado_envio()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF NEW.estado = 'enviada' AND OLD.estado IS DISTINCT FROM 'enviada' THEN
    NEW.notificado_envio := false;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_reset_notif_envio ON public.solicitudes_campana;
CREATE TRIGGER trg_reset_notif_envio BEFORE UPDATE OF estado ON public.solicitudes_campana
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
  EXECUTE FUNCTION private.reset_notificado_envio();

-- ----- GRUPO C: visitas -----

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
END;
$function$;

CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = admin/editor de la empresa de la visita. COALESCE fail-closed.
  IF NOT COALESCE((SELECT true FROM public.cuentas_proveedor WHERE id = auth.uid() AND empresa_id = v.empresa_id
                   AND activo = true AND rol_en_empresa IN ('admin','editor') LIMIT 1), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  IF v.estado NOT IN ('confirmada','cancelada') THEN RETURN; END IF;  -- estado notificable (resultado)
  -- GATE RELACIÓN: cuenta_proveedor_id es caller-libre en el INSERT de visitas (l.52) → exigir que pertenezca
  -- a la empresa de la visita; si no → SKIP sin abortar (espejo evt6/P394).
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;
  IF v.estado = 'confirmada' THEN v_tipo := 'visita_aprobada'; v_titulo := 'Visita aprobada'; v_msg := 'Tu visita propuesta fue confirmada.';
  ELSE v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.'; END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, '/proveedor/visitador');
END;
$function$;

-- ----- grants comunes (REVOKE anon/PUBLIC + GRANT authenticated) -----
DO $grants$ DECLARE fn text; BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.notificar_empresa_estado(uuid)','public.notificar_pago_resultado(uuid)','public.notificar_campana_resultado(uuid)',
    'public.notificar_campana_enviada(uuid)','public.notificar_visita_propuesta(uuid)','public.notificar_visita_resultado(uuid)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
  END LOOP;
END $grants$;
