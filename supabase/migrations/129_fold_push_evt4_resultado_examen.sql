-- ============================================================
-- Fix push transaccional · EVENTO 4 FOLD (resultado de examen → push server-side). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P411–P413. notificar_resultado_examen está VIVO en prod
-- (lo llama useLaboratorio:158) → esta migración cambia comportamiento de inmediato.
--
-- CUTOVER SIN DOBLE (lo ejecuta Oscar): (1) merge del hook a main (deja de llamar enviar-push) → Vercel;
-- (2) acto seguido aplicar ESTA migración (la función empieza a empujar). Invertir = doble push.
--
-- Cambio: tras cada insert (paciente / médico), empujar por id vía private.push_notificar (edge gateado
-- enviar-push-notificacion, que re-deriva del row → contenido mínimo al lock screen). Reemplaza el enviar-push
-- del hook (que mandaba ids+contenido del caller por el edge abierto). NUNCA push_notificar con id NULL.
--
-- l.50: CREATE OR REPLACE NO preserva atributos → RE-DECLARO SECURITY DEFINER + SET search_path=''.
-- l.39: refs del cuerpo calificadas (public.*/private.*), incl. las nuevas.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_paciente_auth uuid; v_pid integer; v_mid uuid;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  -- gate: SOLO el lab dueño de la orden (null-safe IS DISTINCT FROM → fail-closed)
  IF v.laboratorio_id IS DISTINCT FROM public.mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- PACIENTE: insert DIRECTO (relación = dueño de la orden). tipo 'examen' (válido en el CHECK). push por id.
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen listo', 'Tu examen '||COALESCE(v.tipo,'')||' ya tiene resultado.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    SELECT auth_user_id INTO v_paciente_auth FROM public.pacientes WHERE id = v.paciente_id;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;  -- FOLD evt4
  END IF;
  -- MÉDICO: notificaciones (sin CHECK de tipo; preserva 'examen_resultado')
  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
              'El laboratorio subió el resultado de '||COALESCE(v.tipo,'')||' ('||COALESCE(v.paciente_nombre,'paciente')||').', '/medico/citas')
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;  -- FOLD evt4
  END IF;
  RETURN jsonb_build_object('medico', v.medico_id, 'paciente', v_paciente_auth);   -- back-compat (el hook lo ignora)
END;
$function$;
