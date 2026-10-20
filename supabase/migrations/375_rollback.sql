-- ############################################################################################
-- 375_rollback - deshace 375_enrolamiento_hardening.sql y deja el estado post-374 EXACTO
-- ############################################################################################
-- Orden global: 375_rollback -> 374_rollback -> 373_rollback -> ...
-- Fuente de los cuerpos: pg_get_functiondef VIVO del 20-oct-2026 (C:\tmp\mig375\vivo_*.sql), copiado textual (sin CR):
--   enrolar_medico 58387ef7..., prioridad_activa 8cf68b2c..., trg_gate_head_start_lab 835096c8...,
--   trg_medicos_lab_enrolador_inmutable a8c115d8.... CREATE OR REPLACE conserva oid y ACL; las ACL previas se reponen
--   con GRANT (prioridad_activa y trg_gate_head_start_lab vuelven a tener EXECUTE de authenticated).
-- Cambios: DROP del CHECK medicos_enrolador_coherente; los 4 cuerpos y los 2 triggers como estaban
--   (BEFORE UPDATE ON medicos; BEFORE INSERT ON visitas_agendadas); fuera los grants por columna y SELECT de tabla de
--   vuelta a authenticated; lab_enrolador_fecha de medico.qa a NULL (DESPUES de restaurar el trigger viejo y de sacar el
--   CHECK). Si despues del apply alguien enrolo otro medico por la RPC, esa fila conserva su fecha (el estado viejo la admite).
-- Si el front ya mapea PV015-PV017, puede quedar: con este rollback dejan de emitirse.
-- Autochequeo: md5 restaurados = originales, DEFINER/proconfig/ACL originales, triggers y ACL de medicos originales, sin el
--   CHECK, sin PV015-PV017, huellas post-374 (funciones 027e10a7.../392, relaciones d065decf.../2394, policies 8a8dc5cf.../309).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-375)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(f.proname||'='||md5(f.prosrc), ',' ORDER BY f.proname) FROM pg_proc f
         WHERE f.oid IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                         'public.trg_gate_head_start_lab()'::regprocedure, 'public.trg_medicos_lab_enrolador_inmutable()'::regprocedure));
  IF v IS DISTINCT FROM 'enrolar_medico=58e441f3a68a5f80645f9b8f0452ffca,prioridad_activa=07c6a62ffa594ebd093eeca1efbea0d8,trg_gate_head_start_lab=ba09b4fca04e22fe4c3ec0607691805e,trg_medicos_lab_enrolador_inmutable=2af30509d27efef4ed649c5785883381' THEN
    bad := bad||'cuerpos ['||COALESCE(v, '-')||']; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.medicos'::regclass AND c.conname = 'medicos_enrolador_coherente') THEN
    bad := bad||'falta medicos_enrolador_coherente; ';
  END IF;
  IF (SELECT t.tgtype FROM pg_trigger t WHERE t.tgrelid = 'public.medicos'::regclass AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable') IS DISTINCT FROM 23::int2 THEN
    bad := bad||'trigger de medicos no es el de la 375; ';
  END IF;
  IF (SELECT t.tgtype FROM pg_trigger t WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND t.tgname = 'trigger_gate_head_start_lab') IS DISTINCT FROM 23::int2 THEN
    bad := bad||'trigger del head-start no es el de la 375; ';
  END IF;
  v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL);
  IF v IS DISTINCT FROM 'id,clinica_id,nombre_completo,especialidad,telefono,email,cedula_profesional,horario_atencion,activo,created_at,updated_at,pais_id,foto_url,especialidad_id' THEN
    bad := bad||'grants por columna de medicos ['||COALESCE(v, '-')||']; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = '09d243d5-b222-482a-9762-94a582e9e752'
                    AND m.lab_enrolador_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133' AND m.lab_enrolador_fecha IS NOT NULL) THEN
    bad := bad||'medico.qa no esta enrolado con fecha; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK375 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: CHECK
ALTER TABLE public.medicos DROP CONSTRAINT medicos_enrolador_coherente;

-- ---------------------------------------------------------------------------- 2: guard de medicos (cuerpo y trigger anteriores)
CREATE OR REPLACE FUNCTION public.trg_medicos_lab_enrolador_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.lab_enrolador_id IS NOT NULL AND NEW.lab_enrolador_id IS DISTINCT FROM OLD.lab_enrolador_id THEN
    RAISE EXCEPTION 'lab_enrolador_id es inmutable una vez seteado';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER trigger_medicos_lab_enrolador_inmutable ON public.medicos;
CREATE TRIGGER trigger_medicos_lab_enrolador_inmutable BEFORE UPDATE ON public.medicos FOR EACH ROW EXECUTE FUNCTION public.trg_medicos_lab_enrolador_inmutable();

-- ---------------------------------------------------------------------------- 3: enrolar_medico (cuerpo anterior; ACL igual)
CREATE OR REPLACE FUNCTION public.enrolar_medico(p_medico_id uuid)
 RETURNS TABLE(estado text, lab_enrolador_id uuid, lab_enrolador_fecha timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa uuid;
  v_actual  uuid;
BEGIN
  -- 1) Debe ser un visitador activo (empresa derivada de la sesión).
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  -- 2) Gate de CAPACIDAD (NUEVO): la empresa debe tener el módulo 'enrolamiento' activo/vigente.
  --    Va antes del plan/país porque es la pregunta más fundamental ("¿tu empresa contrató esto?").
  IF NOT private.empresa_tiene_capacidad(v_empresa, 'enrolamiento') THEN
    RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de enrolamiento. Contactá a soporte para activarlo.' USING ERRCODE = 'PV014';
  END IF;

  -- 3) Puerta comercial: MISMA que ver disponibilidad/agendar (plan activo que cubre el país del médico).
  --    NO se restringe por rol_en_empresa (decisión de producto).
  IF NOT private.visitador_ve_medico(p_medico_id) THEN
    RAISE EXCEPTION 'No tienes un plan activo que cubra a este médico en su país.' USING ERRCODE = 'PV011';
  END IF;

  -- 4) El médico debe existir. Lock de la fila → serializa enrolamientos concurrentes del mismo médico.
  SELECT m.lab_enrolador_id INTO v_actual
  FROM public.medicos m
  WHERE m.id = p_medico_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Médico no encontrado.' USING ERRCODE = 'PV012';
  END IF;

  -- 5) Enrolamiento según estado previo.
  IF v_actual IS NULL THEN
    -- Libre → enrolar con este lab.
    UPDATE public.medicos
      SET lab_enrolador_id = v_empresa, lab_enrolador_fecha = now()
      WHERE id = p_medico_id;
    RETURN QUERY
      SELECT 'enrolado'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSIF v_actual = v_empresa THEN
    -- Ya enrolado por ESTE lab → no-op idempotente (no error).
    RETURN QUERY
      SELECT 'ya_enrolado_por_ti'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSE
    -- Otro lab → mensaje de negocio claro (defensa en profundidad; el trigger de inmutabilidad
    -- de la mig 193 bloquearía el UPDATE de todas formas).
    RAISE EXCEPTION 'Este médico ya fue enrolado por otro laboratorio.' USING ERRCODE = 'PV013';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------------- 4: prioridad_activa (cuerpo y ACL anteriores)
CREATE OR REPLACE FUNCTION public.prioridad_activa(p_medico_id uuid)
 RETURNS TABLE(activa boolean, lab_prioritario_id uuid, visitas_completadas integer, visitas_limite integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lab    uuid;
  v_fecha  timestamptz;
  v_count  int;
  v_limite int;
BEGIN
  SELECT m.lab_enrolador_id, m.lab_enrolador_fecha
    INTO v_lab, v_fecha
  FROM public.medicos m
  WHERE m.id = p_medico_id;

  -- Médico inexistente o sin enrolador → sin prioridad.
  IF v_lab IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 0, 0;
    RETURN;
  END IF;

  -- Visitas CUMPLIDAS reales del lab enrolador desde el enrolamiento (checkout, no fecha agendada).
  SELECT count(*)::int INTO v_count
  FROM public.visitas_agendadas va
  WHERE va.medico_id      = p_medico_id
    AND va.empresa_id     = v_lab
    AND va.estado         = 'completada'
    AND va.checkout_fecha IS NOT NULL
    AND va.checkout_fecha >= v_fecha;

  -- Límite del lab enrolador; default global 8 si la columna es NULL (o el lab no existiera).
  SELECT COALESCE(ep.ventana_prioridad_visitas, 8) INTO v_limite
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_lab;
  v_limite := COALESCE(v_limite, 8);

  RETURN QUERY SELECT
    ( v_count < v_limite
      AND now() < v_fecha + INTERVAL '18 months' ),   -- techo anti-gaming (hardcodeado por ahora)
    v_lab,
    v_count,
    v_limite;
END;
$function$;

-- orden de la ACL vieja {postgres, authenticated, service_role}: un GRANT agrega al final, asi que service_role sale y vuelve despues
REVOKE EXECUTE ON FUNCTION public.prioridad_activa(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.prioridad_activa(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 5: head-start (INVOKER, solo INSERT, ACL anterior)
CREATE OR REPLACE FUNCTION public.trg_gate_head_start_lab()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_prio      record;
  v_ventaja   int;
  v_fecha_min date;
BEGIN
  SELECT * INTO v_prio FROM public.prioridad_activa(NEW.medico_id);

  -- Sin prioridad activa (no enrolado o ventana expirada): cualquier lab reserva libre.
  IF NOT v_prio.activa THEN
    RETURN NEW;
  END IF;

  -- El propio lab prioritario reserva cualquier fecha.
  IF NEW.empresa_id = v_prio.lab_prioritario_id THEN
    RETURN NEW;
  END IF;

  -- Otro lab: head-start por fecha del lab prioritario (default global 5 días).
  SELECT COALESCE(ep.dias_ventaja_reserva, 5) INTO v_ventaja
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_prio.lab_prioritario_id;
  v_ventaja := COALESCE(v_ventaja, 5);

  v_fecha_min := CURRENT_DATE + v_ventaja;   -- date + int = date

  IF NEW.fecha_visita < v_fecha_min THEN
    RAISE EXCEPTION 'Esta fecha está reservada para el laboratorio con prioridad hasta el %. Puedes agendar a partir de esa fecha.', to_char(v_fecha_min, 'YYYY-MM-DD')
      USING ERRCODE = 'PV002';   -- head-start (país=P0001, bolsa=PV001, head-start=PV002) → front lo captura por SQLSTATE
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.trg_gate_head_start_lab() FROM service_role;
GRANT EXECUTE ON FUNCTION public.trg_gate_head_start_lab() TO authenticated, service_role;

DROP TRIGGER trigger_gate_head_start_lab ON public.visitas_agendadas;
CREATE TRIGGER trigger_gate_head_start_lab BEFORE INSERT ON public.visitas_agendadas FOR EACH ROW EXECUTE FUNCTION public.trg_gate_head_start_lab();

-- ---------------------------------------------------------------------------- 6: privilegios de medicos
REVOKE SELECT (id, clinica_id, nombre_completo, especialidad, telefono, email, cedula_profesional, horario_atencion,
               activo, created_at, updated_at, pais_id, foto_url, especialidad_id)
  ON public.medicos FROM authenticated;
GRANT SELECT ON public.medicos TO authenticated;

-- ---------------------------------------------------------------------------- 7: dato (con el trigger viejo y sin el CHECK)
DO $dato$
DECLARE n int;
BEGIN
  UPDATE public.medicos SET lab_enrolador_fecha = NULL
   WHERE id = '09d243d5-b222-482a-9762-94a582e9e752' AND lab_enrolador_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133'
     AND lab_enrolador_fecha IS NOT NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'ROLLBACK375 DATO: se esperaba 1 fila (medico.qa), se actualizaron %', n; END IF;
END $dato$;

-- ---------------------------------------------------------------------------- autochequeo (estado post-374)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(f.proname||'='||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, 'NULL'), E'\n' ORDER BY f.proname)
          FROM pg_proc f
         WHERE f.oid IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                         'public.trg_gate_head_start_lab()'::regprocedure, 'public.trg_medicos_lab_enrolador_inmutable()'::regprocedure));
  IF v IS DISTINCT FROM
       'enrolar_medico=58387ef76ce0b9589a8a3d3d66fbad23|true|{search_path=public}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'||E'\n'||
       'prioridad_activa=8cf68b2cccbdca78a2515e1c4b4265dc|true|{search_path=public}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'||E'\n'||
       'trg_gate_head_start_lab=835096c89cb6828048ac40bc04975b37|false|{search_path=public}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'||E'\n'||
       'trg_medicos_lab_enrolador_inmutable=a8c115d820012b413d82950b70f4817a|false|{search_path=public}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'funciones restauradas ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT t.tgtype::text||'|'||t.tgattr::text||'|'||t.tgfoid::regprocedure::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.medicos'::regclass AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable');
  IF v IS DISTINCT FROM '19||trg_medicos_lab_enrolador_inmutable()|O' THEN bad := bad||'trigger de medicos '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT t.tgtype::text||'|'||t.tgattr::text||'|'||t.tgfoid::regprocedure::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND t.tgname = 'trigger_gate_head_start_lab');
  IF v IS DISTINCT FROM '7||trg_gate_head_start_lab()|O' THEN bad := bad||'trigger del head-start '||COALESCE(v, 'no existe')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.medicos'::regclass AND c.conname = 'medicos_enrolador_coherente') THEN
    bad := bad||'medicos_enrolador_coherente sigue; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL) THEN
    bad := bad||'quedan grants por columna en medicos; ';
  END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos '||COALESCE(v, 'NULL')||'; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = '09d243d5-b222-482a-9762-94a582e9e752'
                    AND m.lab_enrolador_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133' AND m.lab_enrolador_fecha IS NULL) THEN
    bad := bad||'medico.qa no volvio a fecha NULL; ';
  END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc ~ 'PV01[5-7]');
  IF v IS NOT NULL THEN bad := bad||'PV015-PV017 siguen en ['||v||']; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '027e10a7b66101b4f5bb85c475c34045 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK375 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
