-- ############################################################################################
-- 313 — contexto_ia_paciente: decir si el examen tiene archivo adjunto
-- ############################################################################################
-- Frente 6 de la cola de Fase 4 (lab). El frente es de front, pero esta pieza no se puede hacer
-- sin tocar la base, y conviene que quede escrito por que.
--
-- QUE CAMBIO ARRIBA. Desde este frente el laboratorio puede cerrar un examen con SOLO el archivo
-- y el texto vacio: en la mayoria de los examenes el PDF ES el resultado, y exigir que ademas se
-- transcribiera algo obligaba a escribir relleno.
--
-- EL PROBLEMA QUE ESO CREA. El asistente de IA arma su prompt con
-- `${e.resultados || 'sin resultado'}` (supabase/functions/asistente-ia/index.ts:99). Un examen
-- cerrado solo con archivo le llegaria al modelo como "SIN RESULTADO", que es falso y peor que no
-- decir nada: el modelo razonaria sobre un paciente al que le faltan estudios que estan hechos.
--
-- POR QUE HACE FALTA UNA MIGRACION. `examenes_recientes` no lo arma la edge: lo arma el jsonb de
-- esta funcion, y su subselect traia SOLO tipo, descripcion, resultados y fecha_resultado (medido
-- contra el cuerpo VIVO, no contra el archivo del repo). La edge no tiene de donde sacar si hay
-- archivo, asi que el dato tiene que salir de aca.
--
-- SE AGREGA UN BOOLEAN, NO LA URL. Ver el comentario en el subselect: `archivo_url` es un path del
-- bucket privado con el uuid de la empresa adentro y este jsonb va DENTRO DE UN PROMPT a un modelo
-- de terceros. Mandar el path seria filtrar la estructura interna del storage sin ninguna ganancia.
--
-- CONTRATO ADITIVO. Las cuatro claves que ya estaban quedan igual — mismos nombres, mismo orden,
-- mismo `left(resultados, 500)` — asi que cualquier consumidor viejo sigue leyendo lo mismo. El
-- autochequeo lo verifica clave por clave contra un paciente real, no de palabra.
--
-- DE PASO, MOJIBAKE REPARADO. El cuerpo vivo tenia 4 comentarios con UTF-8 guardado como cp1252
-- ("Ãºltimas", "exÃ¡menes", "â‰¤5"): alguien lo aplico con la codificacion equivocada en su momento.
-- Un CREATE OR REPLACE que copiara el cuerpo tal cual lo perpetuaba. Son SOLO comentarios: el
-- script que armo esta migracion verifica que el codigo sin comentarios quede identico byte a byte.
-- ############################################################################################

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
                 'resultados', left(t.resultados, 500), 'fecha_resultado', t.fecha_resultado,
                 -- MIG 313: un BOOLEAN, no la URL. archivo_url es un path del bucket privado con
                 -- el uuid de la empresa adentro, y este jsonb termina dentro de un prompt que se
                 -- manda a un modelo de terceros. Para decidir el texto alcanza con si existe.
                 'tiene_archivo', (t.archivo_url IS NOT NULL AND btrim(t.archivo_url) <> '')
               ) ORDER BY t.fecha_resultado DESC NULLS LAST)
        FROM ( SELECT tipo, descripcion, resultados, fecha_resultado, created_at, archivo_url
               FROM public.examenes
               WHERE paciente_id = p_paciente_id::integer AND estado = 'completado'
               ORDER BY fecha_resultado DESC NULLS LAST, created_at DESC LIMIT 5 ) t ),
      '[]'::jsonb
    )
  );
END;
$function$;


-- ============================================================================================
-- AUTOCHEQUEO — el contrato viejo intacto y la clave nueva respondiendo
-- ============================================================================================
-- Se ejercita contra un paciente REAL que tenga examenes completados de los dos tipos: uno con
-- archivo y uno sin. Si no existe el caso "sin archivo", se siembra dentro de una subtransaccion
-- que siempre aborta — sin eso el chequeo no podria distinguir true de "siempre true".
--
-- La funcion es SECURITY DEFINER y arranca con `PERFORM public.gate_accion_phi(...)`, asi que hay
-- que llamarla con un actor que pase ese gate: se usa el medico del propio examen.
DO $ac$
DECLARE
  v_pac int; v_med uuid; v_ex_con int; v_ex_sin int;
  v_ctx jsonb; v_exa jsonb; n_con int; n_sin int; v_faltan text;
BEGIN
  BEGIN
    SELECT e.paciente_id, e.medico_id INTO v_pac, v_med
      FROM public.examenes e
     WHERE e.estado = 'completado' AND e.paciente_id IS NOT NULL
       AND e.medico_id IS NOT NULL AND e.archivo_url IS NOT NULL
     ORDER BY e.id LIMIT 1;
    IF v_pac IS NULL THEN RAISE EXCEPTION 'M313_NOFIX'; END IF;

    -- el caso "solo archivo / sin texto" es justo el que este frente habilita: hoy no existe en
    -- los datos, asi que se siembra.
    INSERT INTO public.examenes (tipo, paciente_id, medico_id, estado, resultados, archivo_url,
                                 fecha_resultado)
         VALUES ('QA 313 solo archivo', v_pac, v_med, 'completado'::public.examen_estado, '',
                 'qa-313/solo-archivo.pdf', CURRENT_DATE)
    RETURNING id INTO v_ex_con;
    -- y uno con texto y sin archivo, para el control negativo de la clave nueva
    INSERT INTO public.examenes (tipo, paciente_id, medico_id, estado, resultados, archivo_url,
                                 fecha_resultado)
         VALUES ('QA 313 solo texto', v_pac, v_med, 'completado'::public.examen_estado,
                 'Valores dentro de rango.', NULL, CURRENT_DATE)
    RETURNING id INTO v_ex_sin;

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    v_ctx := public.contexto_ia_paciente(v_pac::bigint);
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);

    v_exa := v_ctx -> 'examenes_recientes';
    SELECT count(*) FILTER (WHERE (x ->> 'tiene_archivo')::boolean),
           count(*) FILTER (WHERE NOT (x ->> 'tiene_archivo')::boolean)
      INTO n_con, n_sin
      FROM jsonb_array_elements(v_exa) x;

    RAISE EXCEPTION 'M313_ROLLBACK_FIXTURE';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM = 'M313_NOFIX' THEN
      RAISE EXCEPTION '313 autochequeo: no hay examen completado con paciente, medico y archivo para medir';
    ELSIF SQLERRM <> 'M313_ROLLBACK_FIXTURE' THEN
      RAISE EXCEPTION '313 autochequeo: fallo midiendo (% %)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- contrato viejo: las 8 claves de primer nivel siguen estando
  SELECT string_agg(k, ', ') INTO v_faltan
    FROM unnest(ARRAY['demografia','alergias','medicacion_en_uso','antecedentes',
                      'signos_vitales_recientes','diagnosticos_recientes',
                      'medicacion_recetada_activa','examenes_recientes']) k
   WHERE NOT (v_ctx ? k);
  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION '313 autochequeo: el jsonb perdio claves de primer nivel: %', v_faltan;
  END IF;

  IF jsonb_array_length(COALESCE(v_exa, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION '313 autochequeo: examenes_recientes vino vacio, el chequeo no mide nada';
  END IF;

  -- las 4 claves viejas del examen siguen estando, con sus nombres
  SELECT string_agg(k, ', ') INTO v_faltan
    FROM unnest(ARRAY['tipo','descripcion','resultados','fecha_resultado']) k
   WHERE NOT ((v_exa -> 0) ? k);
  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION '313 autochequeo: el examen perdio claves viejas: %', v_faltan;
  END IF;

  -- y la nueva discrimina: tiene que haber de los DOS tipos, no todo true ni todo false
  IF NOT ((v_exa -> 0) ? 'tiene_archivo') THEN
    RAISE EXCEPTION '313 autochequeo: falta la clave tiene_archivo';
  END IF;
  IF COALESCE(n_con,0) = 0 OR COALESCE(n_sin,0) = 0 THEN
    RAISE EXCEPTION '313 autochequeo: tiene_archivo no discrimina (con archivo=%, sin archivo=%)',
      COALESCE(n_con,-1), COALESCE(n_sin,-1);
  END IF;

  PERFORM set_config('m313.auto', format(
    'OK (8 claves de primer nivel, 4 claves viejas del examen, y tiene_archivo discrimina: %s con archivo / %s sin archivo)',
    n_con, n_sin), true);
END $ac$;
