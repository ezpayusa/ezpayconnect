-- ############################################################################################
-- 330 - rangos de plausibilidad de signos vitales (P2, base; el front va aparte)
-- ############################################################################################
-- signos_vitales no validaba NADA: ni la RPC ni la tabla tenian cotas, y ninguna columna dice su
-- unidad. Medido en el recon del 25-sep: una glucosa en mmol/L entera (7) entraba igual que 7 mg/dL,
-- 98.6 °F entraba como 98.6 °C, y una talla en metros o pulgadas hacia reventar el trigger del IMC con
-- un 22003 sin explicacion.
--
-- Decisiones (Oscar, no se re-discuten): glucosa SOLO mg/dL entero; temperatura SOLO °C; peso kg;
-- talla cm; PA sigue TEXT pero validada 'NNN/NN'. NULL = no medido, se permite. Sin cambio de firma.
--
-- Doble barrera:
--   1) capturar_signo_vital valida cada parametro no-NULL -> SV001 (fuera de rango, nombra el campo y
--      la unidad) / SV002 (formato de PA). La PA se guarda con btrim. Si vienen peso y talla, calcula
--      el IMC igual que trg_calcular_imc y rechaza > 99.99 (tope de imc numeric(4,2)).
--   2) CHECK sv_<campo>_rango en la tabla, con las mismas cotas: ataja cualquier escritura que no pase
--      por la RPC (hoy solo super_admin, por sv_superadmin_all).
-- La validacion va DESPUES del gate de autorizacion y del guard cita/paciente, y ANTES del INSERT: un
-- caller sin permiso recibe 'No autorizado', no mensajes de rango.
--
-- Writers de la tabla (catalogo 25-sep): capturar_signo_vital (INSERT) y validar_signo_vital (UPDATE
-- solo de estado/validado_por/validado_at, no toca medidas). Ninguna edge escribe. Las otras
-- funciones que la leen no se tocan (el autochequeo lo verifica por md5).
--
-- Errcodes: SV001, SV002 (familia SV nueva). Probes P848-P860. Rollback: 330_rollback.sql.
-- ############################################################################################

BEGIN;

-- (b) las filas existentes tienen que cumplir antes de agregar los CHECK
DO $pre$
DECLARE bad text := ''; n bigint;
BEGIN
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (frecuencia_cardiaca IS NULL OR frecuencia_cardiaca BETWEEN 20 AND 300);
  IF n > 0 THEN bad := bad||'sv_frecuencia_cardiaca_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (frecuencia_respiratoria IS NULL OR frecuencia_respiratoria BETWEEN 4 AND 80);
  IF n > 0 THEN bad := bad||'sv_frecuencia_respiratoria_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (temperatura IS NULL OR temperatura BETWEEN 30 AND 45);
  IF n > 0 THEN bad := bad||'sv_temperatura_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (saturacion_o2 IS NULL OR saturacion_o2 BETWEEN 50 AND 100);
  IF n > 0 THEN bad := bad||'sv_saturacion_o2_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (peso_kg IS NULL OR peso_kg BETWEEN 0.5 AND 400);
  IF n > 0 THEN bad := bad||'sv_peso_kg_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (talla_cm IS NULL OR talla_cm BETWEEN 30 AND 250);
  IF n > 0 THEN bad := bad||'sv_talla_cm_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (glucosa IS NULL OR glucosa BETWEEN 10 AND 1000);
  IF n > 0 THEN bad := bad||'sv_glucosa_rango: '||n||' fila(s); '; END IF;
  SELECT count(*) INTO n FROM public.signos_vitales WHERE NOT (CASE WHEN presion_arterial IS NULL THEN true
            WHEN presion_arterial !~ '^[0-9]{2,3}/[0-9]{2,3}$' THEN false
            ELSE split_part(presion_arterial, '/', 1)::integer BETWEEN 50 AND 300
             AND split_part(presion_arterial, '/', 2)::integer BETWEEN 20 AND 200
             AND split_part(presion_arterial, '/', 1)::integer > split_part(presion_arterial, '/', 2)::integer END);
  IF n > 0 THEN bad := bad||'sv_presion_arterial_rango: '||n||' fila(s); '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG330: filas existentes fuera de rango, no se agregan los CHECK: %', bad; END IF;
END $pre$;

-- (b) CHECKs
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_frecuencia_cardiaca_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_frecuencia_cardiaca_rango CHECK (
  frecuencia_cardiaca IS NULL OR frecuencia_cardiaca BETWEEN 20 AND 300);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_frecuencia_respiratoria_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_frecuencia_respiratoria_rango CHECK (
  frecuencia_respiratoria IS NULL OR frecuencia_respiratoria BETWEEN 4 AND 80);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_temperatura_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_temperatura_rango CHECK (
  temperatura IS NULL OR temperatura BETWEEN 30 AND 45);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_saturacion_o2_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_saturacion_o2_rango CHECK (
  saturacion_o2 IS NULL OR saturacion_o2 BETWEEN 50 AND 100);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_peso_kg_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_peso_kg_rango CHECK (
  peso_kg IS NULL OR peso_kg BETWEEN 0.5 AND 400);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_talla_cm_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_talla_cm_rango CHECK (
  talla_cm IS NULL OR talla_cm BETWEEN 30 AND 250);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_glucosa_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_glucosa_rango CHECK (
  glucosa IS NULL OR glucosa BETWEEN 10 AND 1000);
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_presion_arterial_rango;
ALTER TABLE public.signos_vitales ADD CONSTRAINT sv_presion_arterial_rango CHECK (
  CASE WHEN presion_arterial IS NULL THEN true
            WHEN presion_arterial !~ '^[0-9]{2,3}/[0-9]{2,3}$' THEN false
            ELSE split_part(presion_arterial, '/', 1)::integer BETWEEN 50 AND 300
             AND split_part(presion_arterial, '/', 2)::integer BETWEEN 20 AND 200
             AND split_part(presion_arterial, '/', 1)::integer > split_part(presion_arterial, '/', 2)::integer END);

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
  IF r.m IS DISTINCT FROM 'b2246251fd9154ebcb851332991170c7' THEN bad := bad||'md5 '||r.m||'; '; END IF;
  IF position('SV001' in r.src) = 0 OR position('SV002' in r.src) = 0 THEN bad := bad||'falta SV001/SV002; '; END IF;
  SELECT count(*) INTO n FROM pg_constraint WHERE conrelid = 'public.signos_vitales'::regclass AND contype = 'c'
     AND convalidated AND conname IN ('sv_frecuencia_cardiaca_rango', 'sv_frecuencia_respiratoria_rango', 'sv_temperatura_rango', 'sv_saturacion_o2_rango', 'sv_peso_kg_rango', 'sv_talla_cm_rango', 'sv_glucosa_rango', 'sv_presion_arterial_rango');
  IF n <> 8 THEN bad := bad||'CHECK validados='||n||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG330 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
