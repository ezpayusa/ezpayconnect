-- 174 contexto_ia_paciente: contexto clínico CURADO y ACOTADO (HIPAA minimum necessary) para el asistente IA.
-- Server-side, reemplaza el contexto que hoy arma el front (el cableo a edge/front es INC 2; aquí solo el RPC).
-- NO modifica tablas existentes. Alcance de PHI a revisar por asesor legal (Nivel 1+2 acotado).
--
-- GATE: PERFORM public.gate_accion_phi(p_paciente_id,'asistente_ia') ANTES de leer nada
--   (auth + rol medico/asistente_medico + pertenencia + consentimiento grandfather).
--   La excepción del gate (no_auth/no_pertenencia/consentimiento_revocado) PROPAGA: sin consentimiento, no hay contexto.
--
-- Decisiones de acotamiento (documentadas):
--  * signos_vitales: se prefieren tomas estado='validado'; si el paciente no tiene ninguna validada,
--    fallback a estado='capturado'. Serie corta (≤5), fecha_toma DESC. Solo columnas clínicas.
--  * diagnosticos_recientes: solo diagnostico/plan/motivo_consulta/fecha de las últimas 5 notas.
--    NO se exponen subjetivo/objetivo/analisis/nota (SOAP íntegro queda fuera).
--  * medicacion_recetada_activa: recetas estado='activa' (últimas 5) + items (medicamento/dosis/frecuencia/duracion).
--  * examenes_recientes: estado='completado' (resultado finalizado; se excluyen revision/en_proceso/recibida/pendiente),
--    últimos 5; 'resultados' truncado a 500 chars para no inflar el prompt.
--  * Cada lista LIMIT 5; COALESCE a [] / null si no hay datos.

CREATE OR REPLACE FUNCTION public.contexto_ia_paciente(p_paciente_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE                 -- llama a gate_accion_phi (VOLATILE); no marcar STABLE
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

    -- diagnósticos: solo diagnostico/plan/motivo_consulta (NO SOAP íntegro). Últimas 5.
    'diagnosticos_recientes', COALESCE(
      ( SELECT jsonb_agg(jsonb_build_object(
                 'fecha', t.created_at, 'motivo_consulta', t.motivo_consulta,
                 'diagnostico', t.diagnostico, 'plan', t.plan
               ) ORDER BY t.created_at DESC)
        FROM ( SELECT created_at, motivo_consulta, diagnostico, plan
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

REVOKE ALL     ON FUNCTION public.contexto_ia_paciente(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.contexto_ia_paciente(bigint) TO authenticated;
