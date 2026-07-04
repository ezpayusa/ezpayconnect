-- ============================================================================
-- Migración 225: notificar a la CLÍNICA del médico (o al médico, fallback) cuando una visita de
--                visitador es APROBADA, y cuando una visita ya conocida por la clínica es CANCELADA.
-- ============================================================================
-- GAP: hoy notificar_visita_resultado avisa solo al VISITADOR; el lado clínico/médico nunca se entera
-- de una visita aprobada, ni de su cancelación. Diseño confirmado (Oscar):
--  · Destinatarios = staff (perfiles.rol IN secretaria/asistente_medico) de la clínica PRINCIPAL del
--    médico, EXCLUYENDO al médico; si no hay ninguno → el médico (fallback). Fuente única: el helper
--    public.destinatarios_visita_clinica (lo usan las RPCs para in-app/push y la edge para email).
--  · Canal = in-app (notificaciones) + push (private.push_notificar) + email (private.email_notificar →
--    edge notificar-email con tipos nuevos aprobada_clinica/cancelada_clinica). Contenido SERVER-SIDE.
--  · Aprobación: SOLO estado='confirmada' (no propuesta ni rechazada). Cancelación: SOLO si el estado
--    previo ∈ (confirmada/aprobada/pendiente) — no si venía de 'propuesta' (nadie del lado clínico la vio).
--  · Idempotencia: 2 columnas claim independientes (email_aprobada_clinica_enviado / email_cancelacion_enviado).
-- OJO: obtener_personal_clinica (mig 163) NO es reusable acá — tiene gate por auth.uid()=admin_clinica,
-- y el caller de estas RPCs es el visitador/proveedor → fallaría. Por eso el helper nuevo sin gate
-- (interno; solo lo invocan RPCs ya gateadas + la edge con service_role).
-- visitas_agendadas.medico_id FK→perfiles (=auth.users.id) → in-app al médico no necesita guard extra.
-- ============================================================================

BEGIN;

-- 1) Claims de idempotencia (independientes de los de mig 224).
ALTER TABLE public.visitas_agendadas
  ADD COLUMN IF NOT EXISTS email_aprobada_clinica_enviado timestamptz,
  ADD COLUMN IF NOT EXISTS email_cancelacion_enviado      timestamptz;

-- 2) Helper compartido (fuente única de destinatarios). SIN gate de auth: es interno, lo llaman las
--    RPCs gateadas (in-app/push) y la edge notificar-email (email, con service_role).
CREATE OR REPLACE FUNCTION public.destinatarios_visita_clinica(p_visita_id uuid)
RETURNS TABLE(usuario_id uuid, email text, nombre_completo text, es_medico boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_medico uuid; v_clinica uuid;
BEGIN
  SELECT medico_id INTO v_medico FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF v_medico IS NULL THEN RETURN; END IF;
  -- clínica PRINCIPAL del médico
  SELECT clinica_id INTO v_clinica FROM public.medico_clinicas
    WHERE medico_id = v_medico AND es_principal = true LIMIT 1;
  IF v_clinica IS NOT NULL THEN
    RETURN QUERY
      SELECT p.id, p.email, p.nombre_completo, false
      FROM public.medico_clinicas mc JOIN public.perfiles p ON p.id = mc.medico_id
      WHERE mc.clinica_id = v_clinica
        AND p.rol IN ('secretaria','asistente_medico')
        AND p.id <> v_medico;
    IF FOUND THEN RETURN; END IF;   -- hubo staff → el médico NO recibe (sin redundancia)
  END IF;
  -- fallback: el propio médico
  RETURN QUERY SELECT p.id, p.email, p.nombre_completo, true FROM public.perfiles p WHERE p.id = v_medico;
END;
$function$;
REVOKE ALL     ON FUNCTION public.destinatarios_visita_clinica(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.destinatarios_visita_clinica(uuid) TO service_role;

-- 3) email_notificar: ampliar allowlist con los 2 tipos nuevos (resto idéntico a mig 224).
CREATE OR REPLACE FUNCTION private.email_notificar(p_visita_id uuid, p_tipo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_tipo NOT IN ('propuesta','aprobada','rechazada','aprobada_clinica','cancelada_clinica') THEN RETURN; END IF;
  SELECT valor INTO v_url    FROM private.app_secrets WHERE nombre='email_edge_url';
  SELECT valor INTO v_secret FROM private.app_secrets WHERE nombre='email_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;   -- no configurado → no-op (seguro por defecto)
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type','application/json','x-email-secret', v_secret),
    body    := jsonb_build_object('visita_id', p_visita_id, 'tipo', p_tipo)
  );
EXCEPTION WHEN others THEN RETURN;   -- best-effort
END;
$function$;

-- 4) notificar_visita_resultado: (A) notif al visitador INTACTA + (B) NUEVO bloque clínica en 'confirmada'.
CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text; v_email_tipo text;
        v_medico_nom text; v_empresa_nom text; v_fecha text; v_hora text; v_clinica_msg text; v_nid uuid; rec record;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado, medico_id, fecha_visita, hora_inicio
    INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = admin/editor de la empresa de la visita. COALESCE fail-closed.
  IF NOT COALESCE((SELECT true FROM public.cuentas_proveedor WHERE id = auth.uid() AND empresa_id = v.empresa_id
                   AND activo = true AND rol_en_empresa IN ('admin','editor') LIMIT 1), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  IF v.estado NOT IN ('confirmada','rechazada') THEN RETURN; END IF;
  -- GATE RELACIÓN: cuenta_proveedor_id pertenece a la empresa (si no → skip sin abortar)
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;

  -- (A) Notif al VISITADOR (comportamiento EXISTENTE, sin cambios).
  IF v.estado = 'confirmada' THEN
    v_tipo := 'visita_aprobada';  v_titulo := 'Visita aprobada';  v_msg := 'Tu visita propuesta fue confirmada.'; v_email_tipo := 'aprobada';
  ELSIF v.estado = 'rechazada' THEN
    v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.'; v_email_tipo := 'rechazada';
  END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, '/proveedor/visitador');
  UPDATE public.visitas_agendadas SET email_resultado_enviado = now()
    WHERE id = p_visita_id AND email_resultado_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, v_email_tipo); END IF;

  -- (B) NUEVO: notif a CLÍNICA/MÉDICO — SOLO en aprobación (confirmada). Claim idempotente propio.
  IF v.estado = 'confirmada' THEN
    UPDATE public.visitas_agendadas SET email_aprobada_clinica_enviado = now()
      WHERE id = p_visita_id AND email_aprobada_clinica_enviado IS NULL;
    IF FOUND THEN
      v_medico_nom  := COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = v.medico_id), 'el médico');
      v_empresa_nom := COALESCE((SELECT nombre_empresa FROM public.empresas_proveedoras WHERE id = v.empresa_id), 'un laboratorio');
      v_fecha := to_char(v.fecha_visita, 'DD/MM/YYYY'); v_hora := substr(v.hora_inicio::text, 1, 5);
      v_clinica_msg := 'Se aprobó una visita de ' || v_empresa_nom || ' con ' || v_medico_nom || ' el ' || v_fecha || ' a las ' || v_hora || '.';
      FOR rec IN SELECT usuario_id, es_medico FROM public.destinatarios_visita_clinica(p_visita_id) LOOP
        INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
          VALUES (rec.usuario_id, 'visita_clinica_aprobada', 'Visita de laboratorio aprobada', v_clinica_msg,
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);   -- push best-effort
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'aprobada_clinica');  -- email fan-out (edge re-deriva)
    END IF;
  END IF;
END;
$function$;

-- 5) cancelar_visita: lógica EXISTENTE intacta + NUEVO bloque clínica si el estado previo lo ameritaba.
CREATE OR REPLACE FUNCTION public.cancelar_visita(p_visita_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_visita RECORD; v_prev text;
        v_medico_nom text; v_empresa_nom text; v_fecha text; v_hora text; v_clinica_msg text; v_nid uuid; rec record;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Visita no encontrada'); END IF;
  -- Ownership: super_admin o el visitador dueño. COALESCE fail-open-guard.
  IF NOT ( private.tiene_rol(ARRAY['super_admin']) OR COALESCE(v_visita.cuenta_proveedor_id = auth.uid(), false) ) THEN
    RAISE EXCEPTION 'No autorizado para cancelar esta visita';
  END IF;
  v_prev := v_visita.estado;
  -- Máquina de estados (regla de ventana idéntica).
  IF v_visita.estado = 'propuesta' THEN
    NULL;
  ELSIF v_visita.estado IN ('confirmada', 'aprobada', 'pendiente') THEN
    IF NOT (v_visita.fecha_limite_cancelacion IS NULL OR CURRENT_DATE <= v_visita.fecha_limite_cancelacion) THEN
      RETURN jsonb_build_object('error', 'Ya pasó la fecha límite para cancelar esta visita');
    END IF;
  ELSE
    RETURN jsonb_build_object('error', 'Esta visita no se puede cancelar en su estado actual');
  END IF;

  UPDATE public.visitas_agendadas SET estado = 'cancelada' WHERE id = p_visita_id;

  -- NUEVO: notif a clínica/médico SOLO si el estado previo era conocido por el lado clínico
  -- (confirmada/aprobada/pendiente). NO si venía de 'propuesta'. Claim idempotente propio.
  IF v_prev IN ('confirmada','aprobada','pendiente') THEN
    UPDATE public.visitas_agendadas SET email_cancelacion_enviado = now()
      WHERE id = p_visita_id AND email_cancelacion_enviado IS NULL;
    IF FOUND THEN
      v_medico_nom  := COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = v_visita.medico_id), 'el médico');
      v_empresa_nom := COALESCE((SELECT nombre_empresa FROM public.empresas_proveedoras WHERE id = v_visita.empresa_id), 'un laboratorio');
      v_fecha := to_char(v_visita.fecha_visita, 'DD/MM/YYYY'); v_hora := substr(v_visita.hora_inicio::text, 1, 5);
      v_clinica_msg := 'Se canceló la visita de ' || v_empresa_nom || ' con ' || v_medico_nom || ' del ' || v_fecha || ' a las ' || v_hora || '.';
      FOR rec IN SELECT usuario_id, es_medico FROM public.destinatarios_visita_clinica(p_visita_id) LOOP
        INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
          VALUES (rec.usuario_id, 'visita_clinica_cancelada', 'Visita de laboratorio cancelada', v_clinica_msg,
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'cancelada_clinica');
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'estado', 'cancelada');
END;
$function$;

COMMIT;
