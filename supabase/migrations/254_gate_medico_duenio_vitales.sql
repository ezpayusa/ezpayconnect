-- 254: fix ADITIVO del gate de PHI de signos vitales. El médico DUEÑO de la cita
-- (citas.medico_id = auth.uid()) hoy es rechazado si no tiene membresía en medico_clinicas
-- (paciente_en_clinica_de = false) → no puede ver ni registrar vitales de su propia consulta.
-- Se agrega una rama OR "médico dueño de la cita" a la condición de pertenencia de ambas RPCs.
-- SIN aflojar nada más: firma, retorno, search_path, SECURITY, mensajes y RAISE sin errcode (P0001) idénticos.

-- ── LECTURA ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.listar_signos_vitales_cita(p_cita_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_paciente integer;
  v_result   jsonb;
BEGIN
  -- Gate fail-closed: rol de captura primero (no filtra existencia de cita a callers no clínicos).
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria']), false) THEN
    RAISE EXCEPTION 'No autorizado: rol';
  END IF;

  -- Derivar el paciente de la cita; si no existe la cita → RAISE.
  SELECT c.paciente_id INTO v_paciente FROM public.citas c WHERE c.id = p_cita_id;
  IF v_paciente IS NULL THEN
    RAISE EXCEPTION 'Cita inexistente';
  END IF;

  -- Pertenencia: el paciente de la cita debe estar en una clínica del caller,
  -- (254) O el caller es el MÉDICO DUEÑO de la cita (medico_id = auth.uid()).
  IF NOT (
    COALESCE(private.paciente_en_clinica_de(v_paciente), false)
    OR EXISTS (SELECT 1 FROM public.citas c WHERE c.id = p_cita_id AND c.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No autorizado: pertenencia';
  END IF;

  -- Serie de la cita, cronológica (fecha_toma ASC). Incluye nombre del capturador (JOIN perfiles).
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.fecha_toma ASC), '[]'::jsonb)
    INTO v_result
  FROM (
    SELECT sv.id, sv.fecha_toma, sv.capturado_por, cap.nombre_completo AS capturado_por_nombre,
           sv.estado, sv.presion_arterial, sv.frecuencia_cardiaca, sv.frecuencia_respiratoria,
           sv.temperatura, sv.peso_kg, sv.talla_cm, sv.imc, sv.saturacion_o2, sv.glucosa, sv.notas,
           sv.medico_id, sv.validado_por, sv.validado_at
    FROM public.signos_vitales sv
    LEFT JOIN public.perfiles cap ON cap.id = sv.capturado_por
    WHERE sv.cita_id = p_cita_id
  ) t;

  RETURN v_result;
END;
$function$;

-- ── ESCRITURA ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.capturar_signo_vital(p_paciente_id integer, p_cita_id bigint DEFAULT NULL::bigint, p_presion_arterial text DEFAULT NULL::text, p_frecuencia_cardiaca integer DEFAULT NULL::integer, p_frecuencia_respiratoria integer DEFAULT NULL::integer, p_temperatura numeric DEFAULT NULL::numeric, p_peso_kg numeric DEFAULT NULL::numeric, p_talla_cm numeric DEFAULT NULL::numeric, p_saturacion_o2 integer DEFAULT NULL::integer, p_glucosa integer DEFAULT NULL::integer, p_notas text DEFAULT NULL::text, p_medico_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_row public.signos_vitales%ROWTYPE;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Gate explícito fail-closed (mismo que la ex-policy): rol de captura + pertenencia del paciente,
  -- (254) O el caller es el MÉDICO DUEÑO de la cita (medico_id = auth.uid()).
  IF NOT (
       (private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria']) AND private.paciente_en_clinica_de(p_paciente_id))
   OR EXISTS (SELECT 1 FROM public.citas c WHERE c.id = p_cita_id AND c.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No autorizado: rol o pertenencia';
  END IF;

  -- Guard cita↔paciente (164): si se ata a una cita, debe ser del mismo paciente.
  IF p_cita_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.citas WHERE id = p_cita_id AND paciente_id = p_paciente_id
  ) THEN
    RAISE EXCEPTION 'La cita no corresponde al paciente';
  END IF;

  -- capturado_por = auth.uid() y estado='capturado' FORZADOS server-side (no params → no suplantables).
  -- imc lo calcula el trigger BEFORE INSERT trg_calcular_imc a partir de peso_kg/talla_cm.
  INSERT INTO public.signos_vitales (
    paciente_id, cita_id, medico_id, capturado_por, estado,
    presion_arterial, frecuencia_cardiaca, frecuencia_respiratoria, temperatura,
    peso_kg, talla_cm, saturacion_o2, glucosa, notas
  ) VALUES (
    p_paciente_id, p_cita_id, p_medico_id, v_uid, 'capturado',
    p_presion_arterial, p_frecuencia_cardiaca, p_frecuencia_respiratoria, p_temperatura,
    p_peso_kg, p_talla_cm, p_saturacion_o2, p_glucosa, p_notas
  )
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$function$;
