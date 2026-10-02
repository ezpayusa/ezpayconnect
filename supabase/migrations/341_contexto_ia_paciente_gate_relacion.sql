-- ############################################################################################
-- 341 - contexto_ia_paciente (asistente IA en vivo): gate de relacion alineado con exp_select_medico
-- ############################################################################################
-- Backlog familia 3 (DEFINER), adelantado por decision de Oscar (2-oct-2026). Mismo hueco que cerro la
-- 340 en contexto_ia_ultima_visita: contexto_ia_paciente (SECURITY DEFINER; unico caller: el edge
-- asistente-ia, modo actual) solo llama a gate_accion_phi(asistente_ia), que deja pasar a cualquier
-- medico o asistente_medico de la clinica del paciente. Asi el asistente_medico y un medico de la
-- clinica sin relacion recibian las ultimas 5 notas SOAP (mas recetas, examenes y vitales) aunque la RLS
-- de expediente_notas (exp_select_medico) no les deja leer esas notas.
--
-- Cambio (unico): inmediatamente despues de gate_accion_phi, que conserva su prioridad y sus mensajes
-- (no_auth, no_pertenencia, consentimiento_revocado), el mismo gate de la 340:
--   private.es_medico_de(p) OR private.medico_atiende_paciente(p), COALESCE fail-closed -> 'no_pertenencia'
-- (P0001, mismo mensaje: el edge ya lo mapea a 403 no_pertenencia). El resto del cuerpo es el vivo,
-- sacado de pg_get_functiondef el 2-oct-2026, byte a byte. Atributos (DEFINER, search_path vacio,
-- VOLATILE, sin comentario) y grants iguales.
-- Por que no deja afuera a nadie legitimo: el unico flujo vivo es AsistenteIA en ConsultaPage; un medico
-- solo carga citas propias (citas_select_medico: medico_id = auth.uid()), asi que medico_atiende_paciente
-- ya es true para el; los demas roles que ven citas no pasan gate_accion_phi, salvo asistente_medico,
-- que es justamente el hueco (y no puede escribir notas: exp_insert_medico exige medico_id = auth.uid()).
-- md5(prosrc): 1eaf84a3475dfdfc3845d68ce2406fbb -> 04fe590c805c79b52b324dde69948480.
-- Sin errcodes nuevos. Probes: P921 (gate), P922 (coherencia RPC <-> RLS, centinela), P923 (catalogo);
-- P860, P878, P896, P905 y P919 fijaban el md5 viejo como vecino sin cambios: ajustados al nuevo.
-- Rollback: 341_rollback.sql. Orden de rollback: 341 -> 340 -> 339.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- Estado PRE medido en prod el 2-oct-2026. Una segunda pasada aborta aca: el md5 ya no es el PRE.
DO $precondicion$
DECLARE bad text := ''; x text; r record; v_oid oid := to_regprocedure('public.contexto_ia_paciente(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG341 PRECONDICION FALLA: la funcion no existe'; END IF;
  -- md5(prosrc), DEFINER, search_path vacio, VOLATILE, sin \r en el cuerpo
  SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||p.provolatile::text||' '||(position(E'\r' in p.prosrc) = 0)::text
    INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM '1eaf84a3475dfdfc3845d68ce2406fbb true {"search_path=\"\""} v true' THEN bad := bad||'funcion: '||COALESCE(x, '-')||'; '; END IF;
  -- EXECUTE exactamente para postgres (duenio), authenticated y service_role (aclexplode, no information_schema)
  SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type, ','
                    ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type)
    INTO x FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE' THEN bad := bad||'ACL: '||COALESCE(x, '-')||'; '; END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_paciente') <> 1 THEN
    bad := bad||'mas de una firma; '; END IF;
  IF obj_description(v_oid, 'pg_proc') IS NOT NULL THEN bad := bad||'comentario inesperado; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',          '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_ultima_visita(bigint)',     '7c97629d2a213a201c40f5615bf40cdf'),
      ('public.obtener_contexto_visita(bigint)',       '24c3825b9c8fc6d172f8963191025097'),
      ('private.es_medico_de(bigint)',                 'f68727f9861162f212f57ff2412d7c8b'),
      ('private.medico_atiende_paciente(bigint)',      'ffbb220849b4c21896d103faf8d05abd')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- exp_select_medico: la policy cuyo predicado de paciente copia el gate (pg_policies con el search_path por defecto)
  SELECT cmd||' '||permissive||' '||roles::text||' '||COALESCE(qual, '-')||' '||COALESCE(with_check, '-') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas' AND policyname = 'exp_select_medico';
  IF x IS DISTINCT FROM 'SELECT PERMISSIVE {authenticated} ((medico_id = auth.uid()) OR private.es_medico_de((paciente_id)::bigint) OR private.medico_atiende_paciente((paciente_id)::bigint)) -' THEN bad := bad||'exp_select_medico: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG341 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------- la RPC
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
  -- Relacion (mig 341): el predicado de PACIENTE de la policy exp_select_medico, con sus mismos helpers
  -- (el mismo gate que la 340 puso en contexto_ia_ultima_visita). Fail-closed: NULL cuenta como no.
  IF NOT COALESCE(private.es_medico_de(p_paciente_id) OR private.medico_atiende_paciente(p_paciente_id), false) THEN
    RAISE EXCEPTION 'no_pertenencia';
  END IF;

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

-- ---------------------------------------------------------------------------------- grants
-- CREATE OR REPLACE conserva la ACL; se re-afirma igual que en la 340 (identica a la PRE).
REVOKE ALL ON FUNCTION public.contexto_ia_paciente(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contexto_ia_paciente(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo
DO $autochequeo$
DECLARE bad text := ''; x text; r record; v_oid oid := to_regprocedure('public.contexto_ia_paciente(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG341 AUTOCHEQUEO FALLA: la funcion no existe'; END IF;
  -- md5(prosrc), DEFINER, search_path vacio, VOLATILE, sin \r en el cuerpo
  SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||p.provolatile::text||' '||(position(E'\r' in p.prosrc) = 0)::text
    INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM '04fe590c805c79b52b324dde69948480 true {"search_path=\"\""} v true' THEN bad := bad||'funcion: '||COALESCE(x, '-')||'; '; END IF;
  -- EXECUTE exactamente para postgres (duenio), authenticated y service_role (aclexplode, no information_schema)
  SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type, ','
                    ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type)
    INTO x FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE' THEN bad := bad||'ACL: '||COALESCE(x, '-')||'; '; END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_paciente') <> 1 THEN
    bad := bad||'mas de una firma; '; END IF;
  IF obj_description(v_oid, 'pg_proc') IS NOT NULL THEN bad := bad||'comentario inesperado; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',          '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_ultima_visita(bigint)',     '7c97629d2a213a201c40f5615bf40cdf'),
      ('public.obtener_contexto_visita(bigint)',       '24c3825b9c8fc6d172f8963191025097'),
      ('private.es_medico_de(bigint)',                 'f68727f9861162f212f57ff2412d7c8b'),
      ('private.medico_atiende_paciente(bigint)',      'ffbb220849b4c21896d103faf8d05abd')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- exp_select_medico: la policy cuyo predicado de paciente copia el gate (pg_policies con el search_path por defecto)
  SELECT cmd||' '||permissive||' '||roles::text||' '||COALESCE(qual, '-')||' '||COALESCE(with_check, '-') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas' AND policyname = 'exp_select_medico';
  IF x IS DISTINCT FROM 'SELECT PERMISSIVE {authenticated} ((medico_id = auth.uid()) OR private.es_medico_de((paciente_id)::bigint) OR private.medico_atiende_paciente((paciente_id)::bigint)) -' THEN bad := bad||'exp_select_medico: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG341 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
