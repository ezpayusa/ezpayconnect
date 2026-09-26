-- ############################################################################################
-- 331 - rechazar tomas de signos vitales VACIAS (SV003) + borrar la toma vacia 1453
-- ############################################################################################
-- Hallazgo en navegador (25-sep 18:23, cita 970, medico.qa): en Glucosa se tipeo "10-100"; el input
-- type=number entrega "" (validity.badInput), el form (noValidate) lo trato como "no medido" y, como ni
-- el form ni la RPC exigian al menos un vital, se guardo la fila 1453 con los 9 vitales en NULL.
--
-- (a) capturar_signo_vital: misma firma, SECURITY DEFINER, search_path=''. Dentro del bloque de
--     validacion de la 330 (despues del gate de autorizacion y del guard cita/paciente, antes del
--     INSERT): si los 8 parametros de vitales vienen NULL -> SV003 'Toma vacía: cargue al menos un
--     signo vital'. PA vacia o solo espacios cuenta como NULL. notas NO es un vital. El resto de la
--     funcion es identico a la 330 (md5 b2246251fd9154ebcb851332991170c7 -> df1142281e2fb841ec97fab2266c13fc).
-- (b) DELETE de la fila 1453 con guardas en el WHERE; tiene que borrar exactamente 1 fila.
-- (c) grants explicitos identicos a los vigentes (P800).
-- (d) autochequeo.
--
-- Errcode SV003. Probes P861-P865 (P860 deja de fijar el md5: lo fija P865). Rollback: 331_rollback.sql.
-- ############################################################################################

BEGIN;

-- (a) RPC: misma firma, SECURITY DEFINER, search_path=''
CREATE OR REPLACE FUNCTION public.capturar_signo_vital(p_paciente_id integer, p_cita_id bigint DEFAULT NULL::bigint, p_presion_arterial text DEFAULT NULL::text, p_frecuencia_cardiaca integer DEFAULT NULL::integer, p_frecuencia_respiratoria integer DEFAULT NULL::integer, p_temperatura numeric DEFAULT NULL::numeric, p_peso_kg numeric DEFAULT NULL::numeric, p_talla_cm numeric DEFAULT NULL::numeric, p_saturacion_o2 integer DEFAULT NULL::integer, p_glucosa integer DEFAULT NULL::integer, p_notas text DEFAULT NULL::text, p_medico_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_row public.signos_vitales%ROWTYPE;
  v_pa  text;
  v_sis integer;
  v_dia integer;
  v_imc numeric;
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

  -- (331) Toma vacia: al menos UN signo vital. notas NO cuenta como vital; PA vacia o solo espacios
  -- cuenta como NULL. Caso real (fila 1453, 25-sep): un input type=number con texto invalido entrega ''
  -- (badInput), el form lo leyo como "no medido" y se guardo una fila con los 9 vitales en NULL.
  IF NULLIF(btrim(p_presion_arterial), '') IS NULL
     AND p_frecuencia_cardiaca IS NULL AND p_frecuencia_respiratoria IS NULL AND p_temperatura IS NULL
     AND p_peso_kg IS NULL AND p_talla_cm IS NULL AND p_saturacion_o2 IS NULL AND p_glucosa IS NULL THEN
    RAISE EXCEPTION 'Toma vacía: cargue al menos un signo vital' USING ERRCODE = 'SV003';
  END IF;

  -- (330) Rangos de plausibilidad. Unidades canonicas: FC lpm, FR rpm, temperatura °C, SpO2 %,
  -- peso kg, talla cm, glucosa mg/dL (entero), PA 'NNN/NN' mmHg. NULL = no medido -> se permite.
  -- Barrera 1 de 2: da el errcode que el front sabe pintar. La 2 son los CHECK sv_*_rango de la tabla,
  -- que atajan cualquier escritura que no pase por aca.
  IF p_frecuencia_cardiaca IS NOT NULL AND p_frecuencia_cardiaca NOT BETWEEN 20 AND 300 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: frecuencia_cardiaca (20-300 lpm)' USING ERRCODE = 'SV001';
  END IF;
  IF p_frecuencia_respiratoria IS NOT NULL AND p_frecuencia_respiratoria NOT BETWEEN 4 AND 80 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: frecuencia_respiratoria (4-80 rpm)' USING ERRCODE = 'SV001';
  END IF;
  IF p_temperatura IS NOT NULL AND p_temperatura NOT BETWEEN 30 AND 45 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: temperatura (30-45 °C)' USING ERRCODE = 'SV001';
  END IF;
  IF p_saturacion_o2 IS NOT NULL AND p_saturacion_o2 NOT BETWEEN 50 AND 100 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: saturacion_o2 (50-100 %%)' USING ERRCODE = 'SV001';
  END IF;
  IF p_peso_kg IS NOT NULL AND p_peso_kg NOT BETWEEN 0.5 AND 400 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: peso_kg (0.5-400 kg)' USING ERRCODE = 'SV001';
  END IF;
  IF p_talla_cm IS NOT NULL AND p_talla_cm NOT BETWEEN 30 AND 250 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: talla_cm (30-250 cm)' USING ERRCODE = 'SV001';
  END IF;
  IF p_glucosa IS NOT NULL AND p_glucosa NOT BETWEEN 10 AND 1000 THEN
    RAISE EXCEPTION 'Signo vital fuera de rango: glucosa (10-1000 mg/dL)' USING ERRCODE = 'SV001';
  END IF;
  -- PA: se guarda recortada. Formato primero (SV002), cotas despues (SV001).
  IF p_presion_arterial IS NOT NULL THEN
    v_pa := btrim(p_presion_arterial);
    IF v_pa !~ '^[0-9]{2,3}/[0-9]{2,3}$' THEN
      RAISE EXCEPTION 'Presión arterial con formato inválido (use NNN/NN)' USING ERRCODE = 'SV002';
    END IF;
    v_sis := split_part(v_pa, '/', 1)::integer;
    v_dia := split_part(v_pa, '/', 2)::integer;
    IF v_sis NOT BETWEEN 50 AND 300 OR v_dia NOT BETWEEN 20 AND 200 OR v_sis <= v_dia THEN
      RAISE EXCEPTION 'Signo vital fuera de rango: presion_arterial (sistolica 50-300, diastolica 20-200 mmHg, sistolica > diastolica)' USING ERRCODE = 'SV001';
    END IF;
  END IF;
  -- IMC: misma expresion que trg_calcular_imc, sobre los valores ya redondeados como los guarda la
  -- columna. imc es numeric(4,2): sin este guard el trigger revienta con un 22003 criptico.
  IF p_peso_kg IS NOT NULL AND p_talla_cm IS NOT NULL THEN
    v_imc := ROUND((p_peso_kg::numeric(5,2) / ((p_talla_cm::numeric(5,2) / 100) * (p_talla_cm::numeric(5,2) / 100)))::numeric, 2);
    IF v_imc > 99.99 THEN
      RAISE EXCEPTION 'Combinación peso/talla inválida' USING ERRCODE = 'SV001';
    END IF;
  END IF;

  -- capturado_por = auth.uid() y estado='capturado' FORZADOS server-side (no params → no suplantables).
  -- imc lo calcula el trigger BEFORE INSERT trg_calcular_imc a partir de peso_kg/talla_cm.
  INSERT INTO public.signos_vitales (
    paciente_id, cita_id, medico_id, capturado_por, estado,
    presion_arterial, frecuencia_cardiaca, frecuencia_respiratoria, temperatura,
    peso_kg, talla_cm, saturacion_o2, glucosa, notas
  ) VALUES (
    p_paciente_id, p_cita_id, p_medico_id, v_uid, 'capturado',
    v_pa, p_frecuencia_cardiaca, p_frecuencia_respiratoria, p_temperatura,
    p_peso_kg, p_talla_cm, p_saturacion_o2, p_glucosa, p_notas
  )
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$function$;

-- (b) la toma vacia del hallazgo
DO $del$
DECLARE n int;
BEGIN
  -- guardas: id + los 9 vitales NULL + capturado por medico.qa (09d243d5-b222-482a-9762-94a582e9e752) + creada el 25-sep-2026
  -- (hora de Guatemala; en UTC es 2026-09-26 00:23:57). Si no borra EXACTAMENTE 1 fila, aborta.
  DELETE FROM public.signos_vitales
   WHERE id = 1453
     AND presion_arterial IS NULL AND frecuencia_cardiaca IS NULL AND frecuencia_respiratoria IS NULL AND temperatura IS NULL AND peso_kg IS NULL AND talla_cm IS NULL AND imc IS NULL AND saturacion_o2 IS NULL AND glucosa IS NULL
     AND capturado_por = '09d243d5-b222-482a-9762-94a582e9e752'
     AND (created_at AT TIME ZONE 'America/Guatemala')::date = DATE '2026-09-25';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'MIG331: el DELETE de la toma vacia 1453 borro % fila(s), se esperaba 1', n; END IF;
END $del$;

-- (c) grants explicitos, identicos a los vigentes (P800)
REVOKE ALL ON FUNCTION public.capturar_signo_vital(integer,bigint,text,integer,integer,numeric,numeric,numeric,integer,integer,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.capturar_signo_vital(integer,bigint,text,integer,integer,numeric,numeric,numeric,integer,integer,text,uuid) TO authenticated, service_role;

-- (d) autochequeo
DO $chk$
DECLARE bad text := ''; x text; r record; n int;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.proname = 'capturar_signo_vital';
  IF n <> 1 THEN bad := bad||'firmas='||n||'; '; END IF;
  SELECT p.prosecdef, p.proconfig::text AS cfg, p.proacl::text AS acl, md5(p.prosrc) AS m, p.prosrc AS src
    INTO r FROM pg_proc p WHERE p.oid = 'public.capturar_signo_vital(integer,bigint,text,integer,integer,numeric,numeric,numeric,integer,integer,text,uuid)'::regprocedure;
  IF NOT r.prosecdef THEN bad := bad||'no es SECURITY DEFINER; '; END IF;
  IF r.cfg IS DISTINCT FROM '{"search_path=\"\""}' THEN bad := bad||'search_path '||COALESCE(r.cfg,'NULL')||'; '; END IF;
  IF r.acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'proacl '||COALESCE(r.acl,'NULL')||'; '; END IF;
  IF r.m IS DISTINCT FROM 'df1142281e2fb841ec97fab2266c13fc' THEN bad := bad||'md5 '||r.m||'; '; END IF;
  IF position('SV001' in r.src) = 0 OR position('SV002' in r.src) = 0 THEN bad := bad||'falta SV001/SV002; '; END IF;
  IF position('SV003' in r.src) = 0 THEN bad := bad||'falta SV003; '; END IF;
  SELECT count(*) INTO n FROM pg_constraint WHERE conrelid = 'public.signos_vitales'::regclass AND contype = 'c'
     AND convalidated AND conname IN ('sv_frecuencia_cardiaca_rango', 'sv_frecuencia_respiratoria_rango', 'sv_temperatura_rango', 'sv_saturacion_o2_rango', 'sv_peso_kg_rango', 'sv_talla_cm_rango', 'sv_glucosa_rango', 'sv_presion_arterial_rango');
  IF n <> 8 THEN bad := bad||'CHECK sv_*_rango validados='||n||'; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = 'public.calcular_imc_signos_vitales()'::regprocedure;
  IF x IS DISTINCT FROM '1b9ad49a5cd1464c54d9a211e5763532' THEN bad := bad||'public.calcular_imc_signos_vitales() md5 '||COALESCE(x,'NULL')||'; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = 'public.listar_signos_vitales_cita(bigint)'::regprocedure;
  IF x IS DISTINCT FROM 'f1039b8bc0a5b91d21401ba3075147b7' THEN bad := bad||'public.listar_signos_vitales_cita(bigint) md5 '||COALESCE(x,'NULL')||'; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = 'public.validar_signo_vital(bigint)'::regprocedure;
  IF x IS DISTINCT FROM '23acbb8fec90faf2db3f6fce1aff04e2' THEN bad := bad||'public.validar_signo_vital(bigint) md5 '||COALESCE(x,'NULL')||'; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = 'public.contar_tomas_citas(bigint[])'::regprocedure;
  IF x IS DISTINCT FROM '7fdf0b0ed24da5fd92abe2ba0dd09b6e' THEN bad := bad||'public.contar_tomas_citas(bigint[]) md5 '||COALESCE(x,'NULL')||'; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = 'public.contexto_ia_paciente(bigint)'::regprocedure;
  IF x IS DISTINCT FROM '1eaf84a3475dfdfc3845d68ce2406fbb' THEN bad := bad||'public.contexto_ia_paciente(bigint) md5 '||COALESCE(x,'NULL')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM public.signos_vitales WHERE id = 1453) THEN bad := bad||'la fila 1453 sigue existiendo; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG331 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
