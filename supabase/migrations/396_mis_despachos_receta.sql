-- =====================================================================================================================
-- MIG 396 — mis_despachos_receta(): el paciente dueño obtiene el token de despacho de sus recetas por RPC (ADITIVA).
-- Diseño: output/diseno-396-tokens-20nov.md (20-nov-2026), decisiones D-1 a D-6 aprobadas como recomienda.
--
-- Por qué: authenticated tiene SELECT DE TABLA sobre public.recetas_avanzadas (relacl authenticated=r, sin attacl), así
-- que quien pase una policy de SELECT lee dispatch_token y confirmacion_token: además del paciente dueño, el admin_clinica
-- y el gerente de la clínica del autor, el médico de cabecera y cualquier médico con una cita con el paciente (medido el
-- 20-nov impersonando). El único lector legítimo por SELECT directo es la app del paciente
-- (src/webapp/hooks/useWebAppRecetas.ts:25 lee recetas_avanzadas(dispatch_token, dispatch_token_expira_at,
-- estado_dispensacion) para dibujar el QR). Patrón de dos pasos (D-1): esta migración solo AGREGA la RPC; el front del
-- paciente pasa a leer el token por ella; la mig 397 cierra el SELECT por columna.
--
-- Qué hace (y nada más):
--   1. public.mis_despachos_receta() RETURNS TABLE(receta_id bigint, dispatch_token text, dispatch_token_expira_at
--      timestamptz, estado_dispensacion text): SECURITY DEFINER, STABLE, SET search_path = ''. Devuelve las recetas
--      avanzadas del PACIENTE DUEÑO (pacientes.auth_user_id = auth.uid(), el mismo criterio que private.paciente_es_mio,
--      que usa la policy recadv_select_paciente) con token VIGENTE (dispatch_token_expira_at > now(); D-3). No devuelve
--      confirmacion_token (D-2). Sin sesión, sin fila en pacientes o cualquier otro actor: 0 filas, sin error (lectura
--      fail-closed, sin errcode).
--   2. REVOKE ALL ON FUNCTION … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated.
--   No toca grants de tablas, policies, columnas ni datos. MIG96 = guarda de la migración.
--
-- Estado ANTES, medido el 20-nov-2026 17:49:47 UTC (post-395):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... d20a117271a2a187c6f461b1af1d8014 419
--   ACL de funciones (solo privilegios), public/private .......................... 311350dbe0717e9737372034623b434b 419
--   ACL de relaciones de public ................................................... 88e7fd697ef0703f8f1deb153e9c68d0 2448
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... eba82b3fc822926313534f04caa4f853 309
--   recetas_avanzadas y dispensaciones: relacl {postgres=arwdDxtm/postgres,authenticated=r/postgres,
--   service_role=arwdDxtm/postgres}, sin attacl. emitir_receta(bigint,text,jsonb,bigint) md5(prosrc) 9b65b54d… (395).
--   Funciones que tocan tokens, md5(prosrc): verificar_receta_despacho a258edce…, registrar_dispensacion c53336c3…,
--   registrar_dispensacion_dirigida 5801cdac…, confirmar_recepcion_receta b94e4d21….
--   Filas: recetas_avanzadas 17 (md5 e367fecb…), dispensaciones 5 (md5 597c4b11…). La guarda NO exige esos conteos
--   (la app sigue emitiendo recetas entre la medición y el apply): los captura al entrar y exige que no cambien al salir.
-- Huellas post-396: ver el dry-run (en el PR). Rollback: supabase/migrations/396_rollback.sql (va antes que 395_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/396_mis_despachos_receta.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 395 está aplicada; la 396 no
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.emitir_receta(bigint,text,jsonb,bigint)'))
     IS DISTINCT FROM '9b65b54d314c61d1db6f4f8998234f6b'
     OR to_regclass('public.receta_alertas_alergia') IS NULL THEN
    bad := bad||'la 395 no está aplicada (emitir_receta de 4 argumentos o receta_alertas_alergia); ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'mis_despachos_receta') THEN
    bad := bad||'mis_despachos_receta ya existe (la 396 ya se aplicó); ';
  END IF;

  -- privilegios de las tablas con tokens, exactos
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas'), ('public.dispensaciones')) AS t(tabla) LOOP
    IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}'
       OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
      bad := bad||'relacl o attacl de '||r.tabla||' distintos de los medidos; ';
    END IF;
  END LOOP;
  -- columnas que lee la función, con sus tipos
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attname)
        FROM pg_attribute a WHERE a.attrelid = 'public.recetas_avanzadas'::regclass AND NOT a.attisdropped
         AND a.attname IN ('receta_base_id', 'paciente_id', 'dispatch_token', 'dispatch_token_expira_at', 'estado_dispensacion'))
     IS DISTINCT FROM 'dispatch_token:text,dispatch_token_expira_at:timestamp with time zone,estado_dispensacion:text,paciente_id:text,receta_base_id:bigint'
     OR (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attname)
        FROM pg_attribute a WHERE a.attrelid = 'public.pacientes'::regclass AND NOT a.attisdropped AND a.attname IN ('id', 'auth_user_id'))
     IS DISTINCT FROM 'auth_user_id:uuid,id:bigint' THEN
    bad := bad||'columnas o tipos de recetas_avanzadas / pacientes distintos de los medidos; ';
  END IF;
  -- funciones que tocan tokens: cuerpos de hoy
  FOR r IN SELECT * FROM (VALUES
      ('public.verificar_receta_despacho(text)',                    'a258edce0ffe1ffdb2850f789497a6a4'),
      ('public.registrar_dispensacion(text,bigint[],text)',          'c53336c3d8038da66133036f4fbec1ee'),
      ('public.registrar_dispensacion_dirigida(bigint,bigint[],text)','5801cdac37b1c42d94dd9258d71ab17f'),
      ('public.confirmar_recepcion_receta(text,inet,text)',         'b94e4d21e567ceeb38fb83ebf9a83b03')) AS t(firma, md)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md THEN
      bad := bad||r.firma||' distinta de la medida; ';
    END IF;
  END LOOP;

  -- huellas post-395 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'd20a117271a2a187c6f461b1af1d8014 419' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '311350dbe0717e9737372034623b434b 419' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG96: precondición: %', bad USING ERRCODE = 'MIG96';
  END IF;

  -- filas de las tablas con tokens al entrar (el autochequeo exige que no cambien)
  PERFORM set_config('mig396.filas_recadv', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.recetas_avanzadas t), true);
  PERFORM set_config('mig396.filas_disp', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.dispensaciones t), true);
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) mis_despachos_receta()
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.mis_despachos_receta()
RETURNS TABLE (receta_id bigint, dispatch_token text, dispatch_token_expira_at timestamptz, estado_dispensacion text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT ra.receta_base_id, ra.dispatch_token, ra.dispatch_token_expira_at, ra.estado_dispensacion
    FROM public.recetas_avanzadas ra
    JOIN public.pacientes pa ON pa.id::text = ra.paciente_id
   WHERE auth.uid() IS NOT NULL
     AND pa.auth_user_id = auth.uid()
     AND ra.dispatch_token_expira_at > now()
   ORDER BY ra.receta_base_id, ra.id
$fn$;

COMMENT ON FUNCTION public.mis_despachos_receta() IS
  'Mig 396: tokens de despacho VIGENTES de las recetas del paciente que llama (pacientes.auth_user_id = auth.uid()). Sin confirmacion_token. Otro actor o sin sesión: 0 filas.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) PRIVILEGIOS
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.mis_despachos_receta() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mis_despachos_receta() TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la función: una sola sobrecarga, firma y retorno exactos, DEFINER, STABLE, search_path vacío, ACL exacta
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'mis_despachos_receta') <> 1 THEN
    bad := bad||'mis_despachos_receta no tiene exactamente una sobrecarga; ';
  END IF;
  v := (SELECT pg_get_function_identity_arguments(p.oid)||' -> '||pg_get_function_result(p.oid)||' '||p.prosecdef::text||' '||p.provolatile::text||' '||
               COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.mis_despachos_receta()'));
  IF v IS DISTINCT FROM ' -> TABLE(receta_id bigint, dispatch_token text, dispatch_token_expira_at timestamp with time zone, estado_dispensacion text) true s {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'mis_despachos_receta = '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT p.prosrc ILIKE '%confirmacion%' FROM pg_proc p WHERE p.oid = to_regprocedure('public.mis_despachos_receta()')) THEN
    bad := bad||'mis_despachos_receta menciona confirmacion_token; ';
  END IF;
  IF has_function_privilege('anon', 'public.mis_despachos_receta()', 'EXECUTE') OR NOT has_function_privilege('authenticated', 'public.mis_despachos_receta()', 'EXECUTE') THEN
    bad := bad||'EXECUTE de anon/authenticated sobre mis_despachos_receta; ';
  END IF;

  -- lo demás, intacto: tablas con tokens, funciones que tocan tokens, filas
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas'), ('public.dispensaciones')) AS t(tabla) LOOP
    IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}'
       OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
      bad := bad||'relacl o attacl de '||r.tabla||' cambió; ';
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
      ('public.verificar_receta_despacho(text)',                    'a258edce0ffe1ffdb2850f789497a6a4'),
      ('public.registrar_dispensacion(text,bigint[],text)',          'c53336c3d8038da66133036f4fbec1ee'),
      ('public.registrar_dispensacion_dirigida(bigint,bigint[],text)','5801cdac37b1c42d94dd9258d71ab17f'),
      ('public.confirmar_recepcion_receta(text,inet,text)',         'b94e4d21e567ceeb38fb83ebf9a83b03')) AS t(firma, md)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md THEN
      bad := bad||r.firma||' cambió; ';
    END IF;
  END LOOP;
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.recetas_avanzadas t)
     IS DISTINCT FROM current_setting('mig396.filas_recadv', true) THEN
    bad := bad||'cambiaron filas de recetas_avanzadas; ';
  END IF;
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.dispensaciones t)
     IS DISTINCT FROM current_setting('mig396.filas_disp', true) THEN
    bad := bad||'cambiaron filas de dispensaciones; ';
  END IF;

  -- huellas: sin la función nueva = las de antes; con ella, 420 funciones; relaciones, secuencias y policies sin cambio
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.proname <> 'mis_despachos_receta');
  IF v IS DISTINCT FROM 'd20a117271a2a187c6f461b1af1d8014 419' THEN bad := bad||'huella de funciones completas sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.proname <> 'mis_despachos_receta') y);
  IF v IS DISTINCT FROM '311350dbe0717e9737372034623b434b 419' THEN bad := bad||'huella de ACL de funciones sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 420 THEN
    bad := bad||'no quedaron 420 funciones en public/private; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  -- P800 (j)/(k): ninguna función de public/private con EXECUTE para PUBLIC; anon solo en catalogo_planes_visitador_publico
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR (a.grantee = 'anon'::regrole AND f.oid <> 'public.catalogo_planes_visitador_publico()'::regprocedure)));
  IF v IS NOT NULL THEN bad := bad||'EXECUTE para PUBLIC/anon: '||v||'; '; END IF;
  -- P931: ninguna DEFINER de public/private sin search_path fijo
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%'));
  IF v IS NOT NULL THEN bad := bad||'DEFINER sin search_path: '||v||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG96: autochequeo: %', bad USING ERRCODE = 'MIG96';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
