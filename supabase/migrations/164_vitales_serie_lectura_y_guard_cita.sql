-- 164 · Ola 2 (backend) — lectura de la serie de vitales por cita + guard cita↔paciente en la captura.
-- Resuelve el bloqueo A: las policies SELECT de signos_vitales NO cubren capturado_por=auth.uid(), así que
-- un asistente_medico/enfermeria capturaba pero NO podía leer su propia serie → la UI de admisión no podía
-- mostrar las tomas. Patrón DEFINER (igual que capturar_signo_vital / listar_recetas_entrantes): la lectura
-- multi-rol va por RPC con gate explícito, no por RLS-policy (evita la flakiness de plan y da el scope correcto:
-- la serie COMPLETA de la cita, no solo las filas propias del capturador).

-- ============================================================
-- 1) listar_signos_vitales_cita — lectura de la serie de una cita. Gate: rol de captura + pertenencia.
--    (admin_clinica/gerente y el médico-en-consulta leen por sus propias policies SELECT; este RPC es la
--     vía de la UI de admisión. 'medico' incluido por si el médico usa la misma pantalla.)
-- ============================================================
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

  -- Pertenencia: el paciente de la cita debe estar en una clínica del caller.
  IF NOT COALESCE(private.paciente_en_clinica_de(v_paciente), false) THEN
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
REVOKE ALL    ON FUNCTION public.listar_signos_vitales_cita(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_signos_vitales_cita(bigint) TO authenticated;

-- ============================================================
-- 2) Guard cita↔paciente en capturar_signo_vital (defensa en profundidad). Todo lo demás del RPC INTACTO
--    (firma, gate rol+pertenencia, capturado_por/estado server-side, INSERT, RETURNING, grants).
--    Único agregado: tras el gate y SOLO si p_cita_id IS NOT NULL, validar que la cita es del paciente.
-- ============================================================
CREATE OR REPLACE FUNCTION public.capturar_signo_vital(
  p_paciente_id integer, p_cita_id bigint DEFAULT NULL::bigint,
  p_presion_arterial text DEFAULT NULL::text, p_frecuencia_cardiaca integer DEFAULT NULL::integer,
  p_frecuencia_respiratoria integer DEFAULT NULL::integer, p_temperatura numeric DEFAULT NULL::numeric,
  p_peso_kg numeric DEFAULT NULL::numeric, p_talla_cm numeric DEFAULT NULL::numeric,
  p_saturacion_o2 integer DEFAULT NULL::integer, p_glucosa integer DEFAULT NULL::integer,
  p_notas text DEFAULT NULL::text, p_medico_id uuid DEFAULT NULL::uuid)
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

  -- Gate explícito fail-closed (mismo que la ex-policy): rol de captura + pertenencia del paciente.
  IF NOT (
       private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria'])
   AND private.paciente_en_clinica_de(p_paciente_id)
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
