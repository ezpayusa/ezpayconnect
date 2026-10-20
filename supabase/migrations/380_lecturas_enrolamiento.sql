-- ############################################################################################
-- 380 - lecturas del enrolamiento: "mis medicos" del laboratorio y prioridad al agendar (paso 7 de la familia enrolamiento)
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\mig380\). Estado vivo medido:
--   - public.prioridad_activa(uuid) RETURNS TABLE(activa, lab_prioritario_id, visitas_completadas, visitas_limite),
--     STABLE, DEFINER, search_path '', ACL {postgres=X/postgres,service_role=X/postgres}, md5(prosrc)
--     07c6a62ffa594ebd093eeca1efbea0d8. activa = visitas cumplidas del lab enrolador desde lab_enrolador_fecha (estado
--     'completada' con checkout_fecha >= lab_enrolador_fecha) < COALESCE(ventana_prioridad_visitas del lab, 8)
--     AND now() < lab_enrolador_fecha + 18 meses (techo hardcodeado).
--   - public.trg_gate_head_start_lab() (BEFORE INSERT/UPDATE de visitas_agendadas), md5 ba09b4fca04e22fe4c3ec0607691805e:
--     si la prioridad esta activa y la visita es de OTRO lab, rechaza con PV002 toda fecha_visita < CURRENT_DATE +
--     COALESCE(dias_ventaja_reserva del lab prioritario, 5). El propio lab prioritario agenda cualquier fecha.
--   - public.enrolar_medico(uuid) md5 58e441f3a68a5f80645f9b8f0452ffca: PV010 sin empresa -> PV016 no es
--     laboratorio_farmaceutico -> PV017 rol fuera de admin/supervisor/visitador_medico (mi_rol_proveedor NULL incluido).
--   - private.visitador_ve_medico(uuid) md5 92275e4d96bc7f601f937dbe24d5ee34: plan de visitador activo y vigente de mi
--     empresa en el pais del medico (perfiles.pais_id) = la misma puerta de gate_visita_pais al agendar.
--   - Errcodes PV en uso: PV001-PV003, PV010-PV025 (PV026 libre).
--   - Huellas post-379: funciones (cuerpo, DEFINER, config, ACL) a2652baa3738c1b758b0b120eb6d513a/399; ACL de funciones
--     f71eb65210787bd94c899a623d20350b/399; ACL de relaciones de public 9da6a3c4ca75cd58b3a3053603bf03fe/2406; policies
--     cfb5d7632f071052d491e02a6a5e0932/311.
--
-- Que hace (solo lectura; las dos STABLE, SECURITY DEFINER, search_path '', EXECUTE solo authenticated y service_role):
--   1. listar_mis_medicos_enrolados(): los medicos con lab_enrolador_id = mi empresa. Gates PV010 -> PV016 -> PV017
--      (los de enrolar_medico, con el mismo significado). Por fila: id, nombre, especialidad (catalogo o texto), pais
--      (perfiles.pais_id, el que usan la visibilidad y el agendar), fecha de enrolamiento, prioridad_activa y visitas
--      (de public.prioridad_activa, sin duplicar la regla), prioridad_vence_el = fecha UTC del techo de 18 meses (el fin
--      por visitas no es calculable) y dias_ventaja (COALESCE(dias_ventaja_reserva, 5) de mi empresa). Sin email ni
--      telefono. Orden: prioridad activa primero, despues fecha de enrolamiento desc.
--   2. prioridad_para_agendar(p_medico_id): PV010 sin empresa; PV026 si el medico no existe o mi empresa no lo ve
--      (private.visitador_ve_medico; mismo error para los dos casos). Devuelve {estado, fecha_minima,
--      visitas_completadas, visitas_limite}:
--        'propia'            = mi empresa tiene la prioridad activa; fecha_minima null; visitas de mi empresa.
--        'otro_laboratorio'  = otra empresa la tiene; fecha_minima = CURRENT_DATE + dias_ventaja_reserva de esa empresa
--                              (el primer dia que el trigger me deja agendar hoy); visitas null.
--        'libre'             = sin prioridad activa; fecha_minima null; visitas solo si el enrolador (vencido) es mi
--                              empresa, si no null (no se filtra la actividad de otro laboratorio).
--      Nunca devuelve el id ni el nombre del otro laboratorio.
--
-- Errcodes: PV026 (no puedes consultar a este medico). Reusa PV010, PV016 y PV017 de enrolar_medico.
--
-- md5(prosrc) de las funciones nuevas (calculado sobre este archivo, sin CR; el autochequeo lo exige):
--   listar_mis_medicos_enrolados 0cea8b586b46708d2ced087d6290e6a8, prioridad_para_agendar 1b65c48238b7d93d187dcafe275bb08a.
--
-- Huellas esperadas despues: excluyendo las 2 funciones nuevas, funciones completas y ACL de funciones iguales a las de
--   antes; ACL de relaciones de public y policies sin cambio. Con las nuevas (medidas en el dry-run): funciones completas
--   76b4b9cdebf22fcf3316c9135cc699c1/401; ACL de funciones 853697ced74926f9b09abe3e74f68d50/401.
--
-- Front: nada todavia (PV026 sin mapear).
--
-- Rollback: 380_rollback.sql (DROP de las 2 funciones). Orden global: 380_rollback -> 379_rollback -> 378_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.prioridad_activa(uuid)'));
  IF v IS DISTINCT FROM '07c6a62ffa594ebd093eeca1efbea0d8' THEN bad := bad||'prioridad_activa md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.trg_gate_head_start_lab()'));
  IF v IS DISTINCT FROM 'ba09b4fca04e22fe4c3ec0607691805e' THEN bad := bad||'trg_gate_head_start_lab md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.enrolar_medico(uuid)'));
  IF v IS DISTINCT FROM '58e441f3a68a5f80645f9b8f0452ffca' THEN bad := bad||'enrolar_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.visitador_ve_medico(uuid)'));
  IF v IS DISTINCT FROM '92275e4d96bc7f601f937dbe24d5ee34' THEN bad := bad||'visitador_ve_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('listar_mis_medicos_enrolados', 'prioridad_para_agendar')) THEN
    bad := bad||'ya existe una funcion de la 380; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.prosrc LIKE '%PV026%') THEN bad := bad||'PV026 ya esta en uso; '; END IF;

  -- huellas post-379
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cfb5d7632f071052d491e02a6a5e0932 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9da6a3c4ca75cd58b3a3053603bf03fe 2406' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'f71eb65210787bd94c899a623d20350b 399' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'a2652baa3738c1b758b0b120eb6d513a 399' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG380_PRE FALLA:%', bad; END IF;
END $precondicion$;

-- huella de las funciones de public/private antes de crear las nuevas: el autochequeo exige que quede igual sin ellas
CREATE TEMP TABLE mig380_huella ON COMMIT DROP AS
SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                      COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                      ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
       count(*) AS n
  FROM pg_proc f
 WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace);

-- ---------------------------------------------------------------------------- 1: listar_mis_medicos_enrolados
CREATE FUNCTION public.listar_mis_medicos_enrolados()
RETURNS TABLE (
  medico_id           uuid,
  nombre_completo     text,
  especialidad        text,
  pais_id             uuid,
  lab_enrolador_fecha timestamptz,
  prioridad_activa    boolean,
  visitas_completadas integer,
  visitas_limite      integer,
  prioridad_vence_el  date,
  dias_ventaja        integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_empresa uuid;
  v_tipo    text;
  v_rol     text;
  v_ventaja int;
BEGIN
  -- 1) Debe ser una cuenta de proveedor (empresa derivada de la sesion).
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  -- 2) Solo un laboratorio farmaceutico enrola (y por lo tanto tiene medicos enrolados).
  SELECT ep.tipo::text INTO v_tipo FROM public.empresas_proveedoras ep WHERE ep.id = v_empresa;
  IF v_tipo IS DISTINCT FROM 'laboratorio_farmaceutico' THEN
    RAISE EXCEPTION 'Solo un laboratorio farmacéutico tiene médicos enrolados.' USING ERRCODE = 'PV016';
  END IF;

  -- 3) Los mismos roles que enrolar_medico. mi_rol_proveedor() da NULL si la cuenta o la empresa no estan activas.
  v_rol := public.mi_rol_proveedor();
  IF v_rol IS NULL OR v_rol NOT IN ('admin', 'supervisor', 'visitador_medico') THEN
    RAISE EXCEPTION 'Tu rol en la empresa no te permite ver los médicos enrolados.' USING ERRCODE = 'PV017';
  END IF;

  -- Ventaja de reserva de mi empresa: la que el trigger del head-start aplica a los otros labs sobre mis medicos.
  SELECT COALESCE(ep.dias_ventaja_reserva, 5) INTO v_ventaja FROM public.empresas_proveedoras ep WHERE ep.id = v_empresa;
  v_ventaja := COALESCE(v_ventaja, 5);

  -- La regla de la prioridad vive en public.prioridad_activa (no se duplica). El fin por visitas no es calculable:
  -- prioridad_vence_el es la fecha (UTC) del techo de 18 meses.
  RETURN QUERY
    SELECT m.id,
           m.nombre_completo,
           COALESCE(es.nombre, m.especialidad),
           pf.pais_id,
           m.lab_enrolador_fecha,
           pa.activa,
           pa.visitas_completadas,
           pa.visitas_limite,
           ((m.lab_enrolador_fecha + INTERVAL '18 months') AT TIME ZONE 'UTC')::date,
           v_ventaja
      FROM public.medicos m
      LEFT JOIN public.especialidades es ON es.id = m.especialidad_id
      LEFT JOIN public.perfiles pf ON pf.id = m.id
      CROSS JOIN LATERAL public.prioridad_activa(m.id) pa
     WHERE m.lab_enrolador_id = v_empresa
     ORDER BY pa.activa DESC, m.lab_enrolador_fecha DESC, m.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.listar_mis_medicos_enrolados() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_mis_medicos_enrolados() TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 2: prioridad_para_agendar
CREATE FUNCTION public.prioridad_para_agendar(p_medico_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_empresa uuid;
  v_prio    record;
  v_ventaja int;
BEGIN
  -- 1) Debe ser una cuenta de proveedor (empresa derivada de la sesion).
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  -- 2) La misma puerta que agendar (plan activo de mi empresa en el pais del medico). Medico inexistente o no visible:
  --    el mismo error, sin distinguir.
  IF p_medico_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = p_medico_id)
     OR NOT private.visitador_ve_medico(p_medico_id) THEN
    RAISE EXCEPTION 'No puedes consultar a este médico.' USING ERRCODE = 'PV026';
  END IF;

  SELECT * INTO v_prio FROM public.prioridad_activa(p_medico_id);

  IF v_prio.activa AND v_prio.lab_prioritario_id = v_empresa THEN
    RETURN jsonb_build_object('estado', 'propia', 'fecha_minima', NULL,
                              'visitas_completadas', v_prio.visitas_completadas, 'visitas_limite', v_prio.visitas_limite);
  END IF;

  IF v_prio.activa THEN
    -- Otro laboratorio: el primer dia que trg_gate_head_start_lab deja agendar hoy (CURRENT_DATE + su ventaja).
    SELECT COALESCE(ep.dias_ventaja_reserva, 5) INTO v_ventaja
      FROM public.empresas_proveedoras ep WHERE ep.id = v_prio.lab_prioritario_id;
    v_ventaja := COALESCE(v_ventaja, 5);
    RETURN jsonb_build_object('estado', 'otro_laboratorio', 'fecha_minima', CURRENT_DATE + v_ventaja,
                              'visitas_completadas', NULL, 'visitas_limite', NULL);
  END IF;

  -- Sin prioridad activa. Las visitas solo se muestran si el enrolador (con la prioridad vencida) es mi empresa.
  IF v_prio.lab_prioritario_id = v_empresa THEN
    RETURN jsonb_build_object('estado', 'libre', 'fecha_minima', NULL,
                              'visitas_completadas', v_prio.visitas_completadas, 'visitas_limite', v_prio.visitas_limite);
  END IF;
  RETURN jsonb_build_object('estado', 'libre', 'fecha_minima', NULL, 'visitas_completadas', NULL, 'visitas_limite', NULL);
END;
$function$;

REVOKE ALL ON FUNCTION public.prioridad_para_agendar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prioridad_para_agendar(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 3: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text; r_act record; r_ini record;
BEGIN
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||
               p.provolatile::text||'|'||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.listar_mis_medicos_enrolados()'));
  IF v IS DISTINCT FROM '0cea8b586b46708d2ced087d6290e6a8|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|s|postgres' THEN
    bad := bad||'listar_mis_medicos_enrolados '||COALESCE(v, 'no existe')||'; ';
  END IF;
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||
               p.provolatile::text||'|'||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.prioridad_para_agendar(uuid)'));
  IF v IS DISTINCT FROM '1b65c48238b7d93d187dcafe275bb08a|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|s|postgres' THEN
    bad := bad||'prioridad_para_agendar '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname IN ('listar_mis_medicos_enrolados', 'prioridad_para_agendar')) <> 2 THEN
    bad := bad||'sobrecargas de las funciones de la 380; ';
  END IF;
  IF has_function_privilege('anon', 'public.listar_mis_medicos_enrolados()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.prioridad_para_agendar(uuid)', 'EXECUTE') THEN
    bad := bad||'anon ejecuta una funcion de la 380; ';
  END IF;

  -- el resto de las funciones de public/private, igual que antes
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO r_act
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid NOT IN ('public.listar_mis_medicos_enrolados()'::regprocedure, 'public.prioridad_para_agendar(uuid)'::regprocedure);
  SELECT t.h, t.n INTO r_ini FROM pg_temp.mig380_huella t;
  IF r_act.h IS DISTINCT FROM r_ini.h OR r_act.n IS DISTINCT FROM r_ini.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(r_act.h, '-')||'/'||COALESCE(r_act.n::text, '-')||' vs '||COALESCE(r_ini.h, '-')||'/'||COALESCE(r_ini.n::text, '-')||'; ';
  END IF;

  -- ACL de las otras funciones sin cambio
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.oid NOT IN ('public.listar_mis_medicos_enrolados()'::regprocedure, 'public.prioridad_para_agendar(uuid)'::regprocedure)) y);
  IF v IS DISTINCT FROM 'f71eb65210787bd94c899a623d20350b 399' THEN bad := bad||'ACL de funciones (sin las nuevas) '||COALESCE(v, '-')||'; '; END IF;

  -- huellas globales sin cambio
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cfb5d7632f071052d491e02a6a5e0932 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9da6a3c4ca75cd58b3a3053603bf03fe 2406' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG380_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
