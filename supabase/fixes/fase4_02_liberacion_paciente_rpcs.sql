-- FASE 4 — Gate "liberado al paciente" (bloque 2/3: RPCs + split de notificacion).

-- (A) Liberar UN examen: valida autoridad del medico, exige estado completado, setea flags, avisa al paciente.
CREATE OR REPLACE FUNCTION public.liberar_examen_al_paciente(p_examen_id integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_pid integer;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Examen inexistente' USING ERRCODE='PT002'; END IF;
  IF NOT ( v.medico_id = auth.uid()
        OR private.medico_atiende_paciente((v.paciente_id)::bigint)
        OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
        OR private.tiene_rol(ARRAY['super_admin'::text]) ) THEN
    RAISE EXCEPTION 'No autorizado para liberar este examen' USING ERRCODE='PT002'; END IF;
  IF v.estado::text <> 'completado' THEN
    RAISE EXCEPTION 'El examen aun no tiene resultado cargado' USING ERRCODE='PT002'; END IF;
  IF v.liberado_al_paciente THEN
    RETURN jsonb_build_object('examen', v.id, 'ya_liberado', true); END IF;
  UPDATE public.examenes SET liberado_al_paciente=true, fecha_liberacion=now(), liberado_por=auth.uid()
   WHERE id = v.id;
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen disponible',
              'Tu medico libero un resultado de examen. Ya puedes verlo.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
  RETURN jsonb_build_object('examen', v.id, 'liberado', true);
END; $function$;

-- (B) Liberar toda la ORDEN (bulk): libera los completados-no-liberados que el caller pueda liberar, UNA sola notificacion.
CREATE OR REPLACE FUNCTION public.liberar_orden_al_paciente(p_orden_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_count integer; v_pac integer; v_nid integer;
BEGIN
  WITH upd AS (
    UPDATE public.examenes e
       SET liberado_al_paciente=true, fecha_liberacion=now(), liberado_por=auth.uid()
     WHERE e.orden_id = p_orden_id
       AND e.estado::text = 'completado'
       AND e.liberado_al_paciente = false
       AND ( e.medico_id = auth.uid()
          OR private.medico_atiende_paciente((e.paciente_id)::bigint)
          OR (e.clinica_id IS NOT NULL AND private.es_admin_clinica(e.clinica_id))
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
     RETURNING e.paciente_id
  )
  SELECT count(*), max(paciente_id) INTO v_count, v_pac FROM upd;
  IF COALESCE(v_count,0) = 0 THEN RETURN jsonb_build_object('liberados', 0); END IF;
  IF v_pac IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v_pac, 'examen', 'Resultados de examen disponibles',
              'Tu medico libero resultados de examen. Ya puedes verlos.', '/paciente/examenes', false)
      RETURNING id INTO v_nid;
    IF v_nid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_nid::text); END IF;
  END IF;
  RETURN jsonb_build_object('liberados', v_count);
END; $function$;

-- (C) Vista del PACIENTE (enmascarada): bypassa RLS pero SOLO devuelve los examenes del caller.
--     Para completado-no-liberado: estado -> 'en_proceso' y resultados/archivo/notas/fecha en NULL ("en revision").
CREATE OR REPLACE FUNCTION public.paciente_examenes()
 RETURNS TABLE (id integer, tipo text, descripcion text, fecha_solicitud date, fecha_resultado date,
                estado text, resultados text, archivo_url text, notas text, created_at timestamptz,
                medico_nombre text, liberado_al_paciente boolean, en_revision boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT e.id, e.tipo, e.descripcion, e.fecha_solicitud,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.fecha_resultado END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN 'en_proceso' ELSE e.estado::text END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.resultados END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.archivo_url END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.notas END,
    e.created_at, p.nombre_completo, e.liberado_al_paciente,
    (e.estado::text='completado' AND NOT e.liberado_al_paciente) AS en_revision
  FROM public.examenes e
  LEFT JOIN public.perfiles p ON p.id = e.medico_id
  WHERE e.paciente_id IN (SELECT pac.id FROM public.pacientes pac WHERE pac.auth_user_id = auth.uid())
  ORDER BY e.fecha_solicitud DESC;
$function$;

-- (D) Split: al subir el resultado se avisa SOLO al medico. El aviso al paciente se movio a (A)/(B).
CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_mid uuid;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  IF v.laboratorio_id IS DISTINCT FROM public.mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='PT002'; END IF;
  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
              'Un paciente tiene un resultado de examen nuevo para revisar.', '/medico/citas')
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;
  END IF;
  RETURN jsonb_build_object('medico', v.medico_id);
END; $function$;

-- Grants
REVOKE ALL ON FUNCTION public.liberar_examen_al_paciente(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.liberar_orden_al_paciente(uuid)      FROM PUBLIC;
REVOKE ALL ON FUNCTION public.paciente_examenes()                  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.liberar_examen_al_paciente(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.liberar_orden_al_paciente(uuid)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.paciente_examenes()                  TO authenticated;
