-- ############################################################################################
-- 340 ROLLBACK - contexto_ia_ultima_visita vuelve EXACTAMENTE al cuerpo de la 339
-- ############################################################################################
-- Orden de rollback: 340 -> 339 (339_rollback.sql exige el md5 de la 339, que deja este archivo).
-- Precondicion: estado POST-340 exacto (md5 7c97629d2a213a201c40f5615bf40cdf, DEFINER, search_path vacio, EXECUTE solo para
-- authenticated y service_role, vecinas y exp_select_medico intactas). Si ya se corrio, aborta ahi.
-- Restaura el cuerpo y el comentario de la 339 (md5 a755ff5be772cd2079e19c8ad62a92ea); los grants no cambian.
-- Costo de volver atras: vuelve el hueco que cerro la 340 (asistente_medico y medicos de la clinica sin
-- relacion con el paciente reciben la nota por la RPC). No hay datos que restaurar: no escribe filas.
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE bad text := ''; x text; r record; v_oid oid := to_regprocedure('public.contexto_ia_ultima_visita(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG340 ROLLBACK PRECONDICION FALLA: la funcion no existe'; END IF;
  SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||(position(E'\r' in p.prosrc) = 0)::text INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM '7c97629d2a213a201c40f5615bf40cdf true {"search_path=\"\""} true' THEN bad := bad||'funcion: '||COALESCE(x, '-')||'; '; END IF;
  -- EXECUTE exactamente para postgres (duenio), authenticated y service_role
  SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type, ','
                    ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type)
    INTO x FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE' THEN bad := bad||'ACL: '||COALESCE(x, '-')||'; '; END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_ultima_visita') <> 1 THEN
    bad := bad||'mas de una firma; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',         '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_paciente(bigint)',         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097'),
      ('private.es_medico_de(bigint)',                'f68727f9861162f212f57ff2412d7c8b'),
      ('private.medico_atiende_paciente(bigint)',     'ffbb220849b4c21896d103faf8d05abd')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- exp_select_medico: la policy cuyo predicado de paciente copia el gate (pg_policies con el search_path por defecto)
  SELECT cmd||' '||permissive||' '||roles::text||' '||COALESCE(qual, '-')||' '||COALESCE(with_check, '-') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas' AND policyname = 'exp_select_medico';
  IF x IS DISTINCT FROM 'SELECT PERMISSIVE {authenticated} ((medico_id = auth.uid()) OR private.es_medico_de((paciente_id)::bigint) OR private.medico_atiende_paciente((paciente_id)::bigint)) -' THEN bad := bad||'exp_select_medico: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  IF left(obj_description(v_oid, 'pg_proc'), 13) IS DISTINCT FROM 'Mig 339/340. ' THEN bad := bad||'comentario: '||COALESCE(left(obj_description(v_oid, 'pg_proc'), 40), '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG340 ROLLBACK PRECONDICION FALLA:%', bad; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.contexto_ia_ultima_visita(p_paciente_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_cita   record;
  v_nota   record;
  v_pac    record;
  v_medico text;
  v_vit    jsonb;
BEGIN
  -- GATE primero: si falla, propaga y no se lee nada.
  PERFORM public.gate_accion_phi(p_paciente_id, 'asistente_ia');

  SELECT c.id, c.fecha, c.hora_inicio, c.medico_id INTO v_cita
    FROM public.citas c
   WHERE c.paciente_id = p_paciente_id
     AND c.estado = 'completada'
     AND EXISTS (SELECT 1 FROM public.expediente_notas n
                  WHERE n.cita_id = c.id AND n.paciente_id = p_paciente_id)
   ORDER BY c.fecha DESC, c.hora_inicio DESC, c.id DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sin_visita', true);
  END IF;

  SELECT n.id, n.motivo_consulta, n.subjetivo, n.objetivo, n.analisis, n.diagnostico, n.plan, n.nota, n.corregida_at
    INTO v_nota
    FROM public.expediente_notas n
   WHERE n.cita_id = v_cita.id AND n.paciente_id = p_paciente_id
   ORDER BY n.id DESC
   LIMIT 1;

  SELECT COALESCE(m.nombre_completo, pe.nombre_completo) INTO v_medico
    FROM (SELECT v_cita.medico_id AS id) x
    LEFT JOIN public.medicos m   ON m.id = x.id
    LEFT JOIN public.perfiles pe ON pe.id = x.id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'fecha_toma', t.fecha_toma, 'estado', t.estado,
           'presion_arterial', t.presion_arterial, 'frecuencia_cardiaca', t.frecuencia_cardiaca,
           'frecuencia_respiratoria', t.frecuencia_respiratoria, 'temperatura', t.temperatura,
           'peso_kg', t.peso_kg, 'talla_cm', t.talla_cm, 'imc', t.imc,
           'saturacion_o2', t.saturacion_o2, 'glucosa', t.glucosa
         ) ORDER BY t.ord), '[]'::jsonb)
    INTO v_vit
    FROM (SELECT sv.*, row_number() OVER (ORDER BY (sv.estado = 'validado') DESC, sv.fecha_toma DESC, sv.id DESC) AS ord
            FROM public.signos_vitales sv
           WHERE sv.cita_id = v_cita.id AND sv.paciente_id = p_paciente_id
           ORDER BY (sv.estado = 'validado') DESC, sv.fecha_toma DESC, sv.id DESC
           LIMIT 10) t;

  SELECT pa.fecha_nacimiento, pa.genero, pa.tipo_sangre, pa.alergias, pa.medicamentos_en_uso,
         pa.antecedentes_personales, pa.antecedentes_familiares
    INTO v_pac
    FROM public.pacientes pa
   WHERE pa.id = p_paciente_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'paciente_no_encontrado'; END IF;

  RETURN jsonb_build_object(
    'sin_visita',      false,
    'cita_id',         v_cita.id,
    'fecha',           v_cita.fecha,
    'hora_inicio',     v_cita.hora_inicio,
    'medico_nombre',   v_medico,
    'nota_id',         v_nota.id,
    'motivo_consulta', v_nota.motivo_consulta,
    'subjetivo',       v_nota.subjetivo,
    'objetivo',        v_nota.objetivo,
    'analisis',        v_nota.analisis,
    'diagnostico',     v_nota.diagnostico,
    'plan',            v_nota.plan,
    'nota',            v_nota.nota,
    'corregida',       (v_nota.corregida_at IS NOT NULL),
    'signos_vitales',  v_vit,
    'unidades_signos_vitales', jsonb_build_object(
      'presion_arterial', 'mmHg', 'frecuencia_cardiaca', 'lpm', 'frecuencia_respiratoria', 'rpm',
      'temperatura', '°C', 'peso_kg', 'kg', 'talla_cm', 'cm', 'imc', 'kg/m2',
      'saturacion_o2', '%', 'glucosa', 'mg/dL'),
    'paciente', jsonb_build_object(
      'edad', CASE WHEN v_pac.fecha_nacimiento IS NOT NULL
                   THEN extract(year from age(v_pac.fecha_nacimiento))::int ELSE NULL END,
      'genero',                  v_pac.genero,
      'tipo_sangre',             v_pac.tipo_sangre,
      'alergias',                v_pac.alergias,
      'medicacion_en_uso',       v_pac.medicamentos_en_uso,
      'antecedentes_personales', v_pac.antecedentes_personales,
      'antecedentes_familiares', v_pac.antecedentes_familiares)
  );
END
$function$;

COMMENT ON FUNCTION public.contexto_ia_ultima_visita(bigint) IS
  'Mig 339. Contexto para el resumen IA de la ultima visita: gate_accion_phi(asistente_ia) primero; ultima cita completada CON nota (fecha, hora_inicio, id DESC); nota vigente, vitales de esa cita y datos del paciente con campos explicitos. Sin visita -> {sin_visita:true}.';

REVOKE ALL ON FUNCTION public.contexto_ia_ultima_visita(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contexto_ia_ultima_visita(bigint) TO authenticated, service_role;

DO $chk$
DECLARE bad text := ''; x text; r record; v_oid oid := to_regprocedure('public.contexto_ia_ultima_visita(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG340 ROLLBACK AUTOCHEQUEO FALLA: la funcion no existe'; END IF;
  SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||(position(E'\r' in p.prosrc) = 0)::text INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'a755ff5be772cd2079e19c8ad62a92ea true {"search_path=\"\""} true' THEN bad := bad||'funcion: '||COALESCE(x, '-')||'; '; END IF;
  -- EXECUTE exactamente para postgres (duenio), authenticated y service_role
  SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type, ','
                    ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type)
    INTO x FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE' THEN bad := bad||'ACL: '||COALESCE(x, '-')||'; '; END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_ultima_visita') <> 1 THEN
    bad := bad||'mas de una firma; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',         '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_paciente(bigint)',         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097'),
      ('private.es_medico_de(bigint)',                'f68727f9861162f212f57ff2412d7c8b'),
      ('private.medico_atiende_paciente(bigint)',     'ffbb220849b4c21896d103faf8d05abd')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- exp_select_medico: la policy cuyo predicado de paciente copia el gate (pg_policies con el search_path por defecto)
  SELECT cmd||' '||permissive||' '||roles::text||' '||COALESCE(qual, '-')||' '||COALESCE(with_check, '-') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas' AND policyname = 'exp_select_medico';
  IF x IS DISTINCT FROM 'SELECT PERMISSIVE {authenticated} ((medico_id = auth.uid()) OR private.es_medico_de((paciente_id)::bigint) OR private.medico_atiende_paciente((paciente_id)::bigint)) -' THEN bad := bad||'exp_select_medico: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  IF left(obj_description(v_oid, 'pg_proc'), 9) IS DISTINCT FROM 'Mig 339. ' THEN bad := bad||'comentario: '||COALESCE(left(obj_description(v_oid, 'pg_proc'), 40), '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG340 ROLLBACK AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
