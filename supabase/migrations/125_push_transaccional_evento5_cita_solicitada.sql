-- ============================================================
-- Fix push transaccional · EVENTO 5 (cita solicitada por el paciente → médico + admins clínica). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P377–P382. RPC nuevo → dormant en main hasta su hook (lleva push
-- desde el inicio, sin split).
--
-- GATE actor = PACIENTE dueño de la cita, DERIVADO de auth.uid (anti-spoof, l.5/l.8): el paciente solo puede
-- notificar sobre SU cita. NO acepta paciente_id del caller; NO usa "∈ mis pacientes" (ese es el predicado del
-- médico). COALESCE fail-closed (+ super_admin). Anti re-spam: sólo estado='solicitada' (el momento del request).
--
-- Destinatarios DERIVADOS de la cita (cero recipient del caller): médico (citas.medico_id) + admins de la clínica
-- (obtener_admins_clinica(citas.clinica_id)), AMBOS con push. PHI MÍNIMO: título + nombre del paciente; el MOTIVO
-- NO va en el cuerpo (la edge re-deriva → lock screen; el médico lo ve tras accion_url + auth). Igual criterio evt4.
--
-- l.39: todas las refs calificadas; obtener_admins_clinica tiene su propio search_path='public' (auto-contenido)
-- → seguro desde un outer ''. tipo 'cita_nueva' sin CHECK que violar (notificaciones sólo tiene CHECK de url).
-- ============================================================

CREATE OR REPLACE FUNCTION public.notificar_cita_solicitada(p_cita_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_cita RECORD; v_nombre text; v_nid uuid; rec record;
BEGIN
  SELECT * INTO v_cita FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE actor = paciente dueño (derivado de auth.uid; sin param del caller). COALESCE fail-closed.
  IF NOT COALESCE(
       private.tiene_rol(ARRAY['super_admin'])
    OR v_cita.paciente_id IN (SELECT id FROM public.pacientes WHERE auth_user_id = auth.uid())
  , false) THEN RAISE EXCEPTION 'No autorizado para notificar esta cita' USING ERRCODE = 'PT002'; END IF;
  -- anti re-spam: sólo en el momento de la solicitud
  IF v_cita.estado <> 'solicitada' THEN RAISE EXCEPTION 'Cita no está en estado solicitada' USING ERRCODE = 'PT004'; END IF;
  -- PHI mínimo: nombre del paciente; SIN motivo en el cuerpo
  v_nombre := COALESCE((SELECT nombre || ' ' || COALESCE(apellido,'') FROM public.pacientes WHERE id = v_cita.paciente_id), 'Un paciente');
  v_nombre := trim(v_nombre);
  -- MÉDICO (si la cita lo tiene Y es un auth.user válido). citas.medico_id→medicos, pero
  -- notificaciones.usuario_id→auth.users: un médico de seed sin auth haría FK-fail y abortaría TODO
  -- (incl. admins). El guard lo salta (no es notificable de todos modos) → resiliencia (los admins igual reciben).
  IF v_cita.medico_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_cita.medico_id) THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v_cita.medico_id, 'cita_nueva', 'Nueva cita solicitada', v_nombre || ' solicitó una cita.', '/medico/citas')
      RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END IF;
  -- ADMINS de la clínica (derivados; in-app + push)
  IF v_cita.clinica_id IS NOT NULL THEN
    FOR rec IN SELECT user_id FROM public.obtener_admins_clinica(v_cita.clinica_id) LOOP
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
        VALUES (rec.user_id, 'cita_nueva', 'Nueva solicitud de cita', v_nombre || ' solicitó una cita (pendiente de aprobación).', '/clinica/citas')
        RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);
    END LOOP;
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_cita_solicitada(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_cita_solicitada(bigint) TO authenticated;   -- lo llama el paciente; gate interno
