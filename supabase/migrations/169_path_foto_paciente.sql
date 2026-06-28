-- 169 · path_foto_paciente — deriva server-side la clínica del paciente y devuelve el PATH canónico de la foto.
-- El front NO arma el path con la clínica del USUARIO (frágil multi-clínica): llama este RPC → obtiene el
-- path → sube a ese path exacto (jpeg, upsert:true) → llama set_foto_paciente con el MISMO path.
-- Patrón DEFINER (calcado de capturar_signo_vital/set_foto_paciente). Gate IDÉNTICO a set_foto_paciente,
-- para que quien pueda OBTENER el path sea exactamente quien podrá ESCRIBIRLO.
-- v_clinica = intersección (clínicas del paciente ∩ clínicas del caller): preferencia clinica_primaria_id,
-- fallback clinica_id de una cita compartida. Siempre ∈ clinicas_de(caller) → el 1er segmento del path pasa
-- la storage policy de mig 168 y set_foto_paciente lo acepta. Círculo cerrado.
CREATE OR REPLACE FUNCTION public.path_foto_paciente(p_paciente_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid     uuid;
  v_clinica uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Gate fail-closed IDÉNTICO a set_foto_paciente (misma audiencia).
  IF NOT (
       private.tiene_rol(ARRAY['medico','asistente_medico'])
   AND private.paciente_en_clinica_de(p_paciente_id::integer)
  ) THEN
    RAISE EXCEPTION 'No autorizado: rol o pertenencia';
  END IF;

  -- Preferencia: clinica_primaria_id del paciente SI está en las clínicas del caller.
  SELECT pa.clinica_primaria_id INTO v_clinica
    FROM public.pacientes pa
    WHERE pa.id = p_paciente_id
      AND pa.clinica_primaria_id IN (SELECT private.clinicas_de(v_uid));

  -- Fallback: clinica_id de alguna cita del paciente que esté en las clínicas del caller (determinístico).
  IF v_clinica IS NULL THEN
    SELECT c.clinica_id INTO v_clinica
      FROM public.citas c
      WHERE c.paciente_id = p_paciente_id
        AND c.clinica_id IN (SELECT private.clinicas_de(v_uid))
      ORDER BY c.clinica_id
      LIMIT 1;
  END IF;

  IF v_clinica IS NULL THEN RAISE EXCEPTION 'Sin clínica compartida con el paciente'; END IF;

  RETURN jsonb_build_object(
    'path', v_clinica::text || '/' || p_paciente_id::text || '/perfil.jpg',
    'clinica_id', v_clinica,
    'paciente_id', p_paciente_id
  );
END;
$function$;
REVOKE ALL    ON FUNCTION public.path_foto_paciente(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.path_foto_paciente(bigint) TO authenticated;
