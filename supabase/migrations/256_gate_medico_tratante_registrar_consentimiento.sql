-- 256: gemelo simétrico de mig 255, en la ESCRITURA del consentimiento (Revocar + conceder presencial).
-- registrar_consentimiento (mig 170) en vía presencial exigía tiene_rol(medico/asistente) AND
-- paciente_en_clinica_de → el médico tratante de consultorio (dueño de la cita, paciente SIN clínica
-- primaria y cita con clinica_id NULL) no podía Revocar ni registrar consentimiento presencial.
-- Fix ADITIVO: fallback por médico tratante dueño de una cita del paciente (igual que 255 en la lectura).
-- Cuerpo idéntico al remoto (mig 170); lo ÚNICO cambiado es el bloque OR EXISTS dentro de v_es_staff.
CREATE OR REPLACE FUNCTION public.registrar_consentimiento(p_paciente_id bigint, p_permiso_codigo text, p_concedido boolean, p_via text, p_documento_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid         uuid;
  v_version     int;
  v_id          bigint;
  v_es_paciente boolean;
  v_es_staff    boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF p_via IS NULL OR p_via NOT IN ('app','presencial_firma','presencial_papel')
  THEN RAISE EXCEPTION 'Vía inválida'; END IF;

  v_es_paciente := COALESCE(private.paciente_es_mio(p_paciente_id), false);
  v_es_staff    := private.tiene_rol(ARRAY['medico','asistente_medico'])
               AND (
                    private.paciente_en_clinica_de(p_paciente_id::integer)
                    OR EXISTS (  -- (256) fallback aditivo, espejo de mig 255: médico tratante dueño de una cita del paciente
                         SELECT 1 FROM public.citas c
                         WHERE c.paciente_id = p_paciente_id
                           AND c.medico_id = auth.uid()
                       )
                   );

  -- Gate doble: app ⇒ el caller es el paciente; presencial ⇒ el caller es staff con pertenencia.
  IF p_via = 'app' THEN
    IF NOT v_es_paciente THEN RAISE EXCEPTION 'No autorizado: vía app requiere ser el paciente'; END IF;
  ELSE
    IF NOT v_es_staff THEN RAISE EXCEPTION 'No autorizado: vía presencial requiere staff con pertenencia'; END IF;
  END IF;

  -- Defensivo (confinamiento): si se enlaza un documento, debe ser de ESTE paciente.
  IF p_documento_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.documentos_paciente d
                   WHERE d.id = p_documento_id AND d.paciente_id = p_paciente_id)
    THEN RAISE EXCEPTION 'Documento no pertenece al paciente'; END IF;
  END IF;

  -- permiso_version = la versión ACTIVA más alta del código.
  SELECT cp.version INTO v_version
    FROM public.consentimiento_permisos cp
    WHERE cp.codigo = p_permiso_codigo AND cp.activo = true
    ORDER BY cp.version DESC
    LIMIT 1;
  IF v_version IS NULL THEN RAISE EXCEPTION 'Permiso inexistente o inactivo: %', p_permiso_codigo; END IF;

  -- Append-only: SIEMPRE INSERT (conceder o revocar = nueva fila).
  INSERT INTO public.consentimientos
    (paciente_id, permiso_codigo, permiso_version, concedido, via, capturado_por, documento_id)
  VALUES
    (p_paciente_id, p_permiso_codigo, v_version, p_concedido, p_via, v_uid, p_documento_id)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id, 'permiso_codigo', p_permiso_codigo, 'permiso_version', v_version,
    'concedido', p_concedido, 'via', p_via
  );
END;
$function$;
