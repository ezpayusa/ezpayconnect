-- 255: gemelo de la mig 254, en el consentimiento. estado_consentimiento_paciente (mig 170)
-- solo aceptaba al médico si private.paciente_en_clinica_de(p_paciente_id) → el médico tratante de
-- consultorio (dueño de la cita, paciente SIN clínica primaria y cita con clinica_id NULL) era
-- rechazado con 'No autorizado' (P0001). Fix ADITIVO: fallback por médico tratante dueño de una
-- cita del paciente (esta RPC no recibe p_cita_id, así que se busca por paciente_id + medico_id).
-- Cuerpo idéntico al remoto (mig 170); lo ÚNICO agregado es el bloque OR EXISTS.
CREATE OR REPLACE FUNCTION public.estado_consentimiento_paciente(p_paciente_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF NOT (
       COALESCE(private.paciente_es_mio(p_paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(p_paciente_id::integer) )
    OR EXISTS (  -- (255) fallback aditivo (espejo conceptual de mig 254): médico tratante dueño de una cita con este paciente, aunque la cita no tenga clinica_id
         SELECT 1 FROM public.citas c
         WHERE c.paciente_id = p_paciente_id
           AND c.medico_id = auth.uid()
       )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  ) THEN RAISE EXCEPTION 'No autorizado'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
             jsonb_build_object(
               'codigo', s.permiso_codigo, 'concedido', s.concedido, 'via', s.via,
               'permiso_version', s.permiso_version, 'created_at', s.created_at
             )
           )
    FROM (
      SELECT DISTINCT ON (c.permiso_codigo)
             c.permiso_codigo, c.concedido, c.via, c.permiso_version, c.created_at
      FROM public.consentimientos c
      WHERE c.paciente_id = p_paciente_id
      ORDER BY c.permiso_codigo, c.created_at DESC, c.id DESC  -- id DESC desempata created_at idéntico (vigente = el más nuevo)
    ) s
  ), '[]'::jsonb);
END;
$function$;
