-- ############################################################################################
-- Migracion 373 - completar_registro_proveedor: alta diferida de empresas con Confirm email ON
-- ############################################################################################
-- Problema: en prod "Confirm email" esta ON. El autorregistro de farmacia, laboratorio clinico y
--   proveedor hace signUp (sin sesion hasta confirmar el correo) y enseguida llama a
--   registrar_proveedor, que exige auth.uid(): da 'Usuario no autenticado' (P0001) y el alta de la
--   empresa falla siempre. Medido el 9-oct-2026: 0 usuarios huerfanos (sin perfil, paciente ni
--   cuenta de proveedor) en 90 dias, o sea que nadie lo intento todavia.
-- Decision de Oscar (alta diferida): el front guarda los datos de la empresa en
--   raw_user_meta_data -> 'registro_empresa' al hacer signUp, y al primer login (ya con el correo
--   confirmado) llama a esta RPC, que valida esos datos y llama a registrar_proveedor con la
--   sesion del usuario.
-- registrar_proveedor NO se toca: huella previa md5(prosrc) fae23eeeacb393328f774386ccd88479
--   (mig 327), verificada antes y despues.
-- Esta funcion:
--   * RP001 sin sesion; RP002 correo sin confirmar; RP003 sin registro de empresa pendiente;
--     RP004 datos invalidos. Los gates de registrar_proveedor (42501 identidad, 22023 pais/email)
--     se propagan tal cual. Ningun mensaje lleva datos del usuario.
--   * idempotente: si el uid ya tiene cuenta de proveedor, devuelve su empresa sin escribir nada.
--   * serializada por uid con pg_advisory_xact_lock (dos logins simultaneos no crean dos empresas).
--   * solo lee auth.users: no modifica la metadata ni la cuenta de auth.
-- EXECUTE: solo authenticated (y service_role por el default de la 344); ni PUBLIC ni anon.
-- Huellas (mismo calculo que la 372): precondicion = post-372, medidas en prod el 9-oct-2026:
--   ACL de funciones de public+private 5482f6de564741ad445f30d3ccbd9a79/391, policies de
--   public/private/storage 8a8dc5cfaf8365f95208fb9e8ba79674/309, ACL de relaciones de public
--   d065decfec14c0afae8f5d898032e4bb/2394. Despues: la huella de funciones SIN la nueva sigue
--   5482f6de.../391 y el conteo total es 392 (la huella completa nueva no se fija); grantees con EXECUTE
--   de la nueva = {authenticated, postgres, service_role}; policies y relaciones sin cambio.
-- Rollback: 373_rollback.sql (deja las 3 huellas post-372 exactas).
-- ############################################################################################

BEGIN;

-- PRECONDICIONES ----------------------------------------------------------------------------------
DO $$
DECLARE
  v text := '';
  h text;
BEGIN
  IF to_regprocedure('public.completar_registro_proveedor()') IS NOT NULL THEN
    v := v||E'\n ya existe public.completar_registro_proveedor()';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor no tiene la huella esperada (md5 fae23eee...)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.prosrc ~* 'ERRCODE\s*=\s*''RP[0-9]{3}''') THEN
    v := v||E'\n ya hay errcodes RPnnn en pg_proc';
  END IF;
  -- huellas globales = las post-372 (mismo calculo que la 372)
  h := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF h IS DISTINCT FROM '5482f6de564741ad445f30d3ccbd9a79 391' THEN v := v||E'\n ACL de funciones '||COALESCE(h, '-')||' (esperado 5482f6de.../391)'; END IF;
  h := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF h IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN v := v||E'\n huella de policies '||COALESCE(h, '-')||' (esperado 8a8dc5cf.../309)'; END IF;
  h := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF h IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN v := v||E'\n ACL de relaciones de public '||COALESCE(h, '-')||' (esperado d065decf.../2394)'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'MIG373 PRECONDICION:%', v; END IF;
END
$$;

-- FUNCION -----------------------------------------------------------------------------------------
CREATE FUNCTION public.completar_registro_proveedor()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_uid             uuid := auth.uid();
  v_empresa         uuid;
  v_confirmado      timestamptz;
  v_reg             jsonb;
  v_nombre          text;
  v_tipo            text;
  v_pais            text;
  v_email_contacto  text;
  v_nombre_completo text;
  v_ruc             text;
  v_ciudad          text;
  v_direccion       text;
  v_telefono        text;
  c_tipos  CONSTANT text[] := ARRAY['laboratorio_clinico', 'laboratorio_farmaceutico', 'farmacia', 'empresa_afin'];
  c_uuid   CONSTANT text   := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  c_blanco CONSTANT text   := '^\s+|\s+$';
BEGIN
  -- (1) sesion
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Necesitas iniciar sesión para completar el registro de tu empresa.' USING ERRCODE = 'RP001';
  END IF;

  -- (2) una sola alta a la vez por uid
  PERFORM pg_advisory_xact_lock(hashtextextended('completar_registro_proveedor:' || v_uid::text, 0));

  -- (3) idempotente: ya es proveedor -> su empresa, sin escribir nada
  SELECT cp.empresa_id INTO v_empresa FROM public.cuentas_proveedor cp WHERE cp.id = v_uid;
  IF FOUND THEN
    RETURN v_empresa;
  END IF;

  -- (4) correo confirmado y registro de empresa pendiente (solo lectura de auth.users)
  SELECT u.email_confirmed_at, u.raw_user_meta_data -> 'registro_empresa'
    INTO v_confirmado, v_reg
    FROM auth.users u
   WHERE u.id = v_uid;
  IF v_confirmado IS NULL THEN
    RAISE EXCEPTION 'Confirma tu correo antes de completar el registro.' USING ERRCODE = 'RP002';
  END IF;
  IF v_reg IS NULL OR jsonb_typeof(v_reg) <> 'object' THEN
    RAISE EXCEPTION 'Esta cuenta no tiene un registro de empresa pendiente. Escríbenos a soporte.' USING ERRCODE = 'RP003';
  END IF;

  -- (5) validacion sin errores crudos: tipos de JSON primero, despues valores; el pais se castea
  --     a uuid solo si ya matcheo la expresion regular.
  IF jsonb_typeof(v_reg -> 'nombre_empresa') IS DISTINCT FROM 'string'
     OR jsonb_typeof(v_reg -> 'tipo') IS DISTINCT FROM 'string'
     OR jsonb_typeof(v_reg -> 'pais_id') IS DISTINCT FROM 'string'
     OR jsonb_typeof(v_reg -> 'email_contacto') IS DISTINCT FROM 'string'
     OR jsonb_typeof(v_reg -> 'nombre_completo') IS DISTINCT FROM 'string'
     OR COALESCE(jsonb_typeof(v_reg -> 'ruc_nit'), 'null') NOT IN ('null', 'string')
     OR COALESCE(jsonb_typeof(v_reg -> 'ciudad'), 'null') NOT IN ('null', 'string')
     OR COALESCE(jsonb_typeof(v_reg -> 'direccion'), 'null') NOT IN ('null', 'string')
     OR COALESCE(jsonb_typeof(v_reg -> 'telefono'), 'null') NOT IN ('null', 'string') THEN
    RAISE EXCEPTION 'Los datos de registro de tu empresa no son válidos. Escríbenos a soporte para completarlo.' USING ERRCODE = 'RP004';
  END IF;

  v_nombre          := NULLIF(regexp_replace(v_reg ->> 'nombre_empresa', c_blanco, '', 'g'), '');
  v_tipo            := NULLIF(regexp_replace(v_reg ->> 'tipo', c_blanco, '', 'g'), '');
  v_pais            := NULLIF(regexp_replace(v_reg ->> 'pais_id', c_blanco, '', 'g'), '');
  v_email_contacto  := NULLIF(regexp_replace(v_reg ->> 'email_contacto', c_blanco, '', 'g'), '');
  v_nombre_completo := NULLIF(regexp_replace(v_reg ->> 'nombre_completo', c_blanco, '', 'g'), '');
  v_ruc             := NULLIF(regexp_replace(COALESCE(v_reg ->> 'ruc_nit', ''), c_blanco, '', 'g'), '');
  v_ciudad          := NULLIF(regexp_replace(COALESCE(v_reg ->> 'ciudad', ''), c_blanco, '', 'g'), '');
  v_direccion       := NULLIF(regexp_replace(COALESCE(v_reg ->> 'direccion', ''), c_blanco, '', 'g'), '');
  v_telefono        := NULLIF(regexp_replace(COALESCE(v_reg ->> 'telefono', ''), c_blanco, '', 'g'), '');

  IF v_nombre IS NULL OR v_email_contacto IS NULL OR v_nombre_completo IS NULL
     OR v_tipo IS NULL OR NOT (v_tipo = ANY (c_tipos))
     OR v_pais IS NULL OR v_pais !~ c_uuid THEN
    RAISE EXCEPTION 'Los datos de registro de tu empresa no son válidos. Escríbenos a soporte para completarlo.' USING ERRCODE = 'RP004';
  END IF;

  -- (6) alta con los gates de registrar_proveedor (identidad unica 42501, pais/email 22023), que
  --     se propagan tal cual. p_email va NULL: registrar_proveedor toma el email de auth.users.
  RETURN public.registrar_proveedor(v_nombre, v_tipo, v_ruc, v_pais::uuid, v_ciudad, v_direccion,
                                    v_email_contacto, v_telefono, v_nombre_completo, NULL);
END
$function$;

COMMENT ON FUNCTION public.completar_registro_proveedor() IS
  'Mig 373. Alta diferida de empresas (Confirm email ON): al primer login, con el correo confirmado, toma raw_user_meta_data->''registro_empresa'' de auth.users (solo lectura), lo valida y llama a registrar_proveedor con la sesion del usuario. Idempotente (si ya es proveedor devuelve su empresa) y serializada por uid. RP001 sin sesion, RP002 correo sin confirmar, RP003 sin registro pendiente, RP004 datos invalidos; 42501/22023 de registrar_proveedor se propagan. EXECUTE solo authenticated.';

REVOKE ALL ON FUNCTION public.completar_registro_proveedor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.completar_registro_proveedor() TO authenticated;

-- AUTOCHEQUEO -------------------------------------------------------------------------------------
DO $$
DECLARE
  v text := '';
  f regprocedure := to_regprocedure('public.completar_registro_proveedor()');
  r record;
  h text;
BEGIN
  IF f IS NULL THEN
    RAISE EXCEPTION 'MIG373 AUTOCHEQUEO FALLA:%', E'\n completar_registro_proveedor no existe';
  END IF;
  SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.proconfig, p.prosrc, p.proacl AS acl
    INTO r FROM pg_proc p WHERE p.oid = f;
  IF NOT r.prosecdef THEN v := v||E'\n no es SECURITY DEFINER'; END IF;
  IF r.owner <> 'postgres' THEN v := v||E'\n owner='||r.owner; END IF;
  IF r.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
    v := v||E'\n proconfig='||COALESCE(r.proconfig::text, 'NULL'); END IF;
  IF has_function_privilege('anon', f, 'EXECUTE') THEN v := v||E'\n anon tiene EXECUTE'; END IF;
  IF EXISTS (SELECT 1 FROM aclexplode(r.acl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
    v := v||E'\n PUBLIC tiene EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated', f, 'EXECUTE') THEN v := v||E'\n authenticated sin EXECUTE'; END IF;
  -- proacl exacto: los grantees con EXECUTE son authenticated, postgres y service_role, ninguno mas
  h := (SELECT string_agg(z.g, ',' ORDER BY z.g COLLATE "C") FROM (
          SELECT DISTINCT CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS g
            FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
           WHERE p.oid = f AND a.privilege_type = 'EXECUTE') z);
  IF h IS DISTINCT FROM 'authenticated,postgres,service_role' THEN
    v := v||E'\n grantees con EXECUTE '||COALESCE(h, '-')||' (esperado authenticated,postgres,service_role)'; END IF;
  IF r.prosrc NOT LIKE '%RP001%' OR r.prosrc NOT LIKE '%RP002%'
     OR r.prosrc NOT LIKE '%RP003%' OR r.prosrc NOT LIKE '%RP004%' THEN
    v := v||E'\n faltan errcodes RP001-RP004'; END IF;
  IF r.prosrc NOT ILIKE '%pg_advisory_xact_lock%' THEN v := v||E'\n falta pg_advisory_xact_lock'; END IF;
  IF r.prosrc NOT ILIKE '%registrar_proveedor(%' THEN v := v||E'\n falta la llamada a registrar_proveedor'; END IF;
  IF r.prosrc NOT ILIKE '%email_confirmed_at%' THEN v := v||E'\n falta el chequeo de email_confirmed_at'; END IF;
  IF r.prosrc NOT ILIKE '%registro_empresa%' THEN v := v||E'\n falta registro_empresa'; END IF;
  IF r.prosrc ILIKE '%raw_user_meta_data =%' OR r.prosrc ILIKE '%update auth.users%' THEN
    v := v||E'\n escribe en auth.users'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor cambio de cuerpo'; END IF;
  -- el pais se valida con la expresion regular ANTES del cast a uuid
  IF strpos(r.prosrc, '!~ c_uuid') = 0 OR strpos(r.prosrc, '::uuid') = 0
     OR strpos(r.prosrc, '!~ c_uuid') >= strpos(r.prosrc, '::uuid') THEN
    v := v||E'\n el cast a uuid no va despues de la validacion por regex'; END IF;
  -- huellas globales: funciones SIN la nueva = la post-372 exacta (nada de lo existente cambio de ACL) y el conteo
  -- total = 392 (391 + esta); policies y relaciones = post-372
  h := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND p.oid <> f) y);
  IF h IS DISTINCT FROM '5482f6de564741ad445f30d3ccbd9a79 391' THEN
    v := v||E'\n ACL de funciones sin la nueva '||COALESCE(h, '-')||' (esperado 5482f6de.../391)'; END IF;
  h := (SELECT count(DISTINCT p.oid)::text FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF h IS DISTINCT FROM '392' THEN v := v||E'\n funciones de public+private '||COALESCE(h, '-')||' (esperado 392)'; END IF;
  h := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF h IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN v := v||E'\n huella de policies '||COALESCE(h, '-')||' (esperado 8a8dc5cf.../309)'; END IF;
  h := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF h IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN v := v||E'\n ACL de relaciones de public '||COALESCE(h, '-')||' (esperado d065decf.../2394)'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'MIG373 AUTOCHEQUEO FALLA:%', v; END IF;
END
$$;

COMMIT;
