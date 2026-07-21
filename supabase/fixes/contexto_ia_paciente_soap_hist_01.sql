-- Expande contexto_ia_paciente para incluir SOAP historico (subjetivo/objetivo/analisis, trunc 500)
-- en el bloque 'diagnosticos_recientes'. TODO lo demas identico al vivo (mig 174). Aplicar con -f.
-- La IA leia solo diagnostico/motivo/plan; el medico escribe su razonamiento en 'analisis' (casi siempre
-- poblada) y en subjetivo/objetivo, que la IA no veia historicamente. Truncado a 500 c/u por PHI/tokens.
CREATE OR REPLACE FUNCTION public.contexto_ia_paciente(p_paciente_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_p RECORD;
BEGIN
  -- GATE primero: si falla, propaga y NO se lee ni arma nada.
  PERFORM public.gate_accion_phi(p_paciente_id, 'asistente_ia');

  SELECT fecha_nacimiento, genero, tipo_sangre, alergias, medicamentos_en_uso,
         antecedentes_personales, antecedentes_familiares
    INTO v_p
  FROM public.pacientes
  WHERE id = p_paciente_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'paciente_no_encontrado'; END IF;

  RETURN jsonb_build_object(
    'demografia', jsonb_build_object(
      'edad', CASE WHEN v_p.fecha_nacimiento IS NOT NULL
                   THEN extract(year from age(v_p.fecha_nacimiento))::int ELSE NULL END,
      'genero', v_p.genero,
      'tipo_sangre', v_p.tipo_sangre
    ),
    'alergias', v_p.alergias,
    'medicacion_en_uso', v_p.medicamentos_en_uso,
    'antecedentes', jsonb_build_object(
      'personales', v_p.antecedentes_personales,
      'familiares', v_p.antecedentes_familiares
    ),

    -- vitales: validadas preferidas; si no hay, capturadas (COALESCE entre aggs). Serie corta ≤5.
    'signos_vitales_recientes', COALESCE(
      ( SELECT jsonb_agg(jsonb_build_object(
                 'fecha_toma', t.fecha_toma, 'presion_arterial', t.presion_arterial,
                 'frecuencia_cardiaca', t.frecuencia_cardiaca, 'frecuencia_respiratoria', t.frecuencia_respiratoria,
                 'temperatura', t.temperatura, 'peso_kg', t.peso_kg, 'talla_cm', t.talla_cm,
                 'imc', t.imc, 'saturacion_o2', t.saturacion_o2, 'glucosa', t.glucosa
               ) ORDER BY t.fecha_toma DESC)
        FROM ( SELECT * FROM public.signos_vitales
               WHERE paciente_id = p_paciente_id::integer AND estado = 'validado'
               ORDER BY fecha_toma DESC LIMIT 5 ) t ),
      ( SELECT jsonb_agg(jsonb_build_object(
                 'fecha_toma', t.fecha_toma, 'presion_arterial', t.presion_arterial,
                 'frecuencia_cardiaca', t.frecuencia_cardiaca, 'frecuencia_respiratoria', t.frecuencia_respiratoria,
                 'temperatura', t.temperatura, 'peso_kg', t.peso_kg, 'talla_cm', t.talla_cm,
                 'imc', t.imc, 'saturacion_o2', t.saturacion_o2, 'glucosa', t.glucosa
               ) ORDER BY t.fecha_toma DESC)
        FROM ( SELECT * FROM public.signos_vitales
               WHERE paciente_id = p_paciente_id::integer AND estado = 'capturado'
               ORDER BY fecha_toma DESC LIMIT 5 ) t ),
      '[]'::jsonb
    ),

    -- consultas previas: SOAP historico (subjetivo/objetivo/analisis trunc 500) + diagnostico/plan/motivo. Últimas 5.
    'diagnosticos_recientes', COALESCE(
      ( SELECT jsonb_agg(jsonb_build_object(
                 'fecha', t.created_at, 'motivo_consulta', t.motivo_consulta,
                 'subjetivo', t.subjetivo, 'objetivo', t.objetivo, 'analisis', t.analisis,
                 'diagnostico', t.diagnostico, 'plan', t.plan
               ) ORDER BY t.created_at DESC)
        FROM ( SELECT created_at, motivo_consulta, diagnostico, plan,
                      left(subjetivo, 500) AS subjetivo,
                      left(objetivo, 500)  AS objetivo,
                      left(analisis, 500)  AS analisis
               FROM public.expediente_notas
               WHERE paciente_id = p_paciente_id::integer
               ORDER BY created_at DESC LIMIT 5 ) t ),
      '[]'::jsonb
    ),

    -- recetas activas (últimas 5) con sus items, estructurado.
    'medicacion_recetada_activa', COALESCE(
      ( SELECT jsonb_agg(jsonb_build_object(
                 'fecha', r.created_at,
                 'items', COALESCE(
                   ( SELECT jsonb_agg(jsonb_build_object(
                       'medicamento', ri.nombre_medicamento, 'dosis', ri.dosis,
                       'frecuencia', ri.frecuencia, 'duracion', ri.duracion ))
                     FROM public.receta_items ri WHERE ri.receta_id = r.id ),
                   '[]'::jsonb )
               ) ORDER BY r.created_at DESC)
        FROM ( SELECT id, created_at FROM public.recetas
               WHERE paciente_id = p_paciente_id AND estado = 'activa'
               ORDER BY created_at DESC LIMIT 5 ) r ),
      '[]'::jsonb
    ),

    -- exámenes con resultado finalizado (estado='completado'), últimos 5; resultados truncado a 500.
    'examenes_recientes', COALESCE(
      ( SELECT jsonb_agg(jsonb_build_object(
                 'tipo', t.tipo, 'descripcion', t.descripcion,
                 'resultados', left(t.resultados, 500), 'fecha_resultado', t.fecha_resultado
               ) ORDER BY t.fecha_resultado DESC NULLS LAST)
        FROM ( SELECT tipo, descripcion, resultados, fecha_resultado, created_at
               FROM public.examenes
               WHERE paciente_id = p_paciente_id::integer AND estado = 'completado'
               ORDER BY fecha_resultado DESC NULLS LAST, created_at DESC LIMIT 5 ) t ),
      '[]'::jsonb
    )
  );
END;
$function$;

-- Grants (re-emitidos por prolijidad/versionado; identicos a mig 174).
REVOKE ALL ON FUNCTION public.contexto_ia_paciente(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.contexto_ia_paciente(bigint) TO authenticated;
