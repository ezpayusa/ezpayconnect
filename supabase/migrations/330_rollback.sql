-- ############################################################################################
-- 330 ROLLBACK - vuelve capturar_signo_vital a la definicion previa (md5 4b23e0f4...) y quita los
-- 8 CHECK sv_*_rango. La funcion es la definicion viva de prod capturada el 25-sep con
-- pg_get_functiondef (mig 254), byte a byte.
-- ############################################################################################

BEGIN;

ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_frecuencia_cardiaca_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_frecuencia_respiratoria_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_temperatura_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_saturacion_o2_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_peso_kg_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_talla_cm_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_glucosa_rango;
ALTER TABLE public.signos_vitales DROP CONSTRAINT IF EXISTS sv_presion_arterial_rango;

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

REVOKE ALL ON FUNCTION public.capturar_signo_vital(integer,bigint,text,integer,integer,numeric,numeric,numeric,integer,integer,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.capturar_signo_vital(integer,bigint,text,integer,integer,numeric,numeric,numeric,integer,integer,text,uuid) TO authenticated, service_role;

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
  IF r.m IS DISTINCT FROM '4b23e0f47c56a079d69e306a0b033d27' THEN bad := bad||'md5 '||r.m||'; '; END IF;
  IF position('SV001' in r.src) > 0 OR position('SV002' in r.src) > 0 THEN bad := bad||'quedo SV001/SV002; '; END IF;
  SELECT count(*) INTO n FROM pg_constraint WHERE conrelid = 'public.signos_vitales'::regclass
     AND conname IN ('sv_frecuencia_cardiaca_rango', 'sv_frecuencia_respiratoria_rango', 'sv_temperatura_rango', 'sv_saturacion_o2_rango', 'sv_peso_kg_rango', 'sv_talla_cm_rango', 'sv_glucosa_rango', 'sv_presion_arterial_rango');
  IF n <> 0 THEN bad := bad||'quedan '||n||' CHECK sv_*_rango; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK330 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
