-- ############################################################################################
-- 339 - contexto_ia_ultima_visita(p_paciente_id): contexto para el resumen IA de la ULTIMA visita
-- ############################################################################################
-- Fase 1 del "resumen de la ultima visita" (opcion B, decision de Oscar del 26-sep). Recon de solo
-- lectura del 1-oct-2026 (tmp/recon_ia_f1/). Sin cambios de esquema.
--
-- Por que una RPC nueva y no obtener_contexto_visita (mig 291, queda como esta, sin callers):
--   * no pasa por gate_accion_phi: no mira el consentimiento 'asistente_ia';
--   * devuelve to_jsonb(expediente_notas.*) entero (columnas de control incluidas) y el historial IA;
--   * su gate de rol es otro (admin de clinica y super_admin si; asistente_medico no).
--
-- Contrato:
--   * Gate: lo PRIMERO es gate_accion_phi(p_paciente_id, 'asistente_ia'), el mismo del asistente IA
--     (medico o asistente_medico de la clinica del paciente; consentimiento no revocado). Sus errores
--     ('no_auth', 'no_pertenencia', 'consentimiento_revocado') propagan tal cual: el edge ya los mapea.
--   * Ultima visita = la ultima cita COMPLETADA del paciente que TENGA nota en expediente_notas,
--     ordenada por fecha DESC, hora_inicio DESC, id DESC (el id desempata dos citas del mismo dia y
--     hora). citas no tiene completada_at. Una completada SIN nota (hay una legacy, previa a PE001)
--     se saltea y se toma la anterior que si tenga.
--   * expediente_notas.cita_id no es UNIQUE: si una cita tuviera dos notas se toma la de mayor id.
--   * Sin visita -> {"sin_visita": true}. No es un rechazo: no gasta errcode (PE005 sigue libre).
--   * Salida con campos EXPLICITOS (nada de to_jsonb(n.*)): la nota VIGENTE completa de UNA visita
--     (las versiones previas viven en expediente_notas_revisiones y no se exponen), los signos vitales
--     atados a esa cita (validados primero, despues fecha_toma DESC, max 10) y los mismos datos del
--     paciente que usa contexto_ia_paciente. Las unidades van una vez, en unidades_signos_vitales
--     (son las canonicas que la mig 330 exige por CHECK).
-- Probes P916-P919. Rollback: 339_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- md5(prosrc) vivos medidos el 1-oct-2026. Una segunda pasada aborta aca: la funcion ya existe.
DO $pre$
DECLARE bad text := ''; x text; r record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_ultima_visita') THEN
    bad := bad||'public.contexto_ia_ultima_visita ya existe; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',         '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_paciente(bigint)',         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG339 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- ---------------------------------------------------------------------------------- la RPC
CREATE FUNCTION public.contexto_ia_ultima_visita(p_paciente_id bigint)
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

-- ---------------------------------------------------------------------------------- grants
REVOKE ALL ON FUNCTION public.contexto_ia_ultima_visita(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contexto_ia_ultima_visita(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; r record; v_oid oid := to_regprocedure('public.contexto_ia_ultima_visita(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG339 AUTOCHEQUEO FALLA: la funcion no existe'; END IF;
  SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||(position(E'\r' in p.prosrc) = 0)::text INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'true {"search_path=\"\""} true' THEN bad := bad||'definer/search_path/LF: '||COALESCE(x, '-')||'; '; END IF;
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
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG339 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
