-- ============================================================
-- Fix push transaccional · EVENTO 7 (cancelación de cita por el paciente → médico + admins clínica). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P395–P403. Espejo de evt5 + claim de idempotencia (evt6).
-- RPC nuevo → dormant hasta su hook (lleva push desde el inicio).
--
-- Destinatarios = {médico, admins} (replica useWebAppCitas:146/:162; médico ahora in-app+push, antes push-only
-- por el FK auth.users — el guard lo resuelve). GATE actor=PACIENTE dueño (derivado de auth.uid, anti-spoof).
-- 'cancelada' es estado TERMINAL → claim atómico (notificado_cancelacion) anti re-spam, DESPUÉS de los gates.
-- PHI: contenido mínimo, motivo NO en el cuerpo (queda en cita.motivo_cancelacion tras accion_url+auth).
-- ============================================================

ALTER TABLE public.citas ADD COLUMN IF NOT EXISTS notificado_cancelacion boolean DEFAULT false;  -- idempotencia

CREATE OR REPLACE FUNCTION public.notificar_cancelacion(p_cita_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_cita RECORD; v_nombre text; v_msg text; v_fecha text; v_nid uuid; rec record;
BEGIN
  -- (1) cargar
  SELECT * INTO v_cita FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- (2) GATE caller = paciente dueño (derivado de auth.uid; sin param). COALESCE fail-closed.
  IF NOT COALESCE(
       private.tiene_rol(ARRAY['super_admin'])
    OR v_cita.paciente_id IN (SELECT id FROM public.pacientes WHERE auth_user_id = auth.uid())
  , false) THEN RAISE EXCEPTION 'No autorizado para notificar esta cancelación' USING ERRCODE = 'PT002'; END IF;
  -- (3) GATE estado: solo cancelación real
  IF v_cita.estado <> 'cancelada' THEN RAISE EXCEPTION 'Cita no está cancelada' USING ERRCODE = 'PT004'; END IF;
  -- (4) CLAIM idempotencia (terminal → anti re-spam), tras los gates
  UPDATE public.citas SET notificado_cancelacion = true WHERE id = p_cita_id AND notificado_cancelacion IS NOT TRUE;
  IF NOT FOUND THEN RETURN; END IF;
  -- (5) contenido server, SIN motivo
  v_fecha  := to_char(v_cita.fecha, 'DD/MM/YYYY');
  v_nombre := COALESCE((SELECT trim(nombre || ' ' || COALESCE(apellido,'')) FROM public.pacientes WHERE id = v_cita.paciente_id), 'Un paciente');
  v_msg    := v_nombre || ' canceló su cita del ' || v_fecha || '.';
  -- MÉDICO (in-app+push) con guard auth.users (médico de 'medicos' sin auth → skip sin abortar; eco evt5)
  IF v_cita.medico_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_cita.medico_id) THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v_cita.medico_id, 'cita_cancelada', 'Cita cancelada por el paciente', v_msg, '/medico/citas')
      RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END IF;
  -- ADMINS de la clínica (in-app+push)
  IF v_cita.clinica_id IS NOT NULL THEN
    FOR rec IN SELECT user_id FROM public.obtener_admins_clinica(v_cita.clinica_id) LOOP
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
        VALUES (rec.user_id, 'cita_cancelada', 'Cita cancelada por el paciente', v_msg, '/clinica/citas')
        RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);
    END LOOP;
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_cancelacion(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_cancelacion(bigint) TO authenticated;   -- lo llama el paciente; gate interno

-- 'cancelada' NO es terminal: asignar_medico_cita / actualizar_estado_cita pueden REACTIVAR (cancelada→agendada/…).
-- Sin reset, una 2ª cancelación quedaría sin notif (flag ya en true). Trigger catch-all: al salir de 'cancelada'
-- resetea notificado_cancelacion (caza TODOS los caminos de reactivación, presentes y futuros). l.40: OF estado.
CREATE OR REPLACE FUNCTION private.reset_notificado_cancelacion()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF OLD.estado = 'cancelada' AND NEW.estado <> 'cancelada' THEN
    NEW.notificado_cancelacion := false;   -- reactivación → permite re-notificar una futura cancelación
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_reset_notif_cancel ON public.citas;
CREATE TRIGGER trg_reset_notif_cancel BEFORE UPDATE OF estado ON public.citas
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
  EXECUTE FUNCTION private.reset_notificado_cancelacion();
