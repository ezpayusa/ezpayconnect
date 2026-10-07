-- ############################################################################################
-- 370 - EXECUTE de funciones sin PUBLIC ni anon en public y private (familia 2, ultimo paso: EXECUTE)
-- ############################################################################################
-- Recon del 6-oct-2026 (solo lectura contra prod, sobre main 00e503e; censo en tmp/recon_execute/):
--   * 384 funciones en public (285) y private (99), todas de postgres, 0 de extensiones (pg_depend deptype 'e').
--   * 38 con EXECUTE para PUBLIC (aclexplode de COALESCE(proacl, acldefault)): 21 "legacy" de public con
--     {=X, postgres=X, anon=X, authenticated=X, service_role=X}; 15 de private con proacl NULL (= acldefault: PUBLIC y
--     el dueno); 2 de private con PUBLIC + authenticated (puede_aprobar_visitas, safe_uuid).
--   * 22 con anon explicito: las 21 legacy + catalogo_planes_visitador_publico (mig 362, sin PUBLIC).
--   * LA PREMISA VIEJA NO SE CUMPLE: ninguna funcion le llega a authenticated SOLO via PUBLIC en public. Las 9 helpers de
--     policies tienen authenticated (y las de public, service_role) EXPLICITOS, asi que este REVOKE no le rompe nada a
--     authenticated. Las 15 de private que solo tenian PUBLIC: 13 son de trigger (el EXECUTE de la funcion de trigger se
--     chequea al CREATE TRIGGER, no al disparar: trigger.c, CreateTriggerFiringOn vs ExecCallTriggerFunc; en prod
--     supabase_auth_admin no tiene EXECUTE sobre handle_new_paciente y las altas de auth.users siguen entrando) y 2
--     (es_staff_calendario_clinica, resolver_medicamento_id) solo las llaman funciones DEFINER.
--   * Policies que dependen (pg_depend) de funciones de public/private: TODAS TO authenticated desde las 349/350. anon
--     evalua solo configuracion_pais "Publico lee paises activos" (activo = true), configuracion_sistema_select_anon_publicas
--     (claves) y 3 de storage por bucket_id: ninguna llama funciones. Por eso las 10 helpers que la 301 le dejo a anon
--     (P739/P741) ya no le hacen falta: el motivo de la 301 (policies TO public sobre tablas que anon lee) desaparecio.
--   * anon necesita solo catalogo_planes_visitador_publico (landing /planes-visitador sin sesion, App.tsx:345).
-- Cambio:
--   1 GRANT EXECUTE explicito (no-op documental, la ACL ya lo tiene) a authenticated y service_role sobre las 9 helpers de
--     public usadas por policies o por triggers INVOKER (mi_empresa_proveedor, mi_rol_proveedor, get_auth_user_rol,
--     get_auth_user_pais_id, puede_ver_conversacion, mi_clinica_id, supervisa_cuenta_proveedor, admin_clinica_de_medico,
--     calcular_limite_cancelacion) y a authenticated sobre private.safe_uuid(text) (10 policies de storage). safe_uuid NO
--     recibe service_role: service_role tiene BYPASSRLS (nunca evalua esas policies) y no tiene USAGE en private; darselo
--     cambiaria la ACL. Los 3 triggers INVOKER (set_fecha_limite_cancelacion, perfiles_guard_rol_update,
--     trg_gate_capacidad_publicidad) llaman a calcular_limite_cancelacion, get_auth_user_rol y mi_empresa_proveedor: 10
--     funciones distintas en total.
--   2 REVOKE EXECUTE ... FROM PUBLIC, anon en TODA funcion de public/private con PUBLIC o anon, elegida por CATALOGO,
--     salvo public.catalogo_planes_visitador_publico(), que conserva anon (excepcion de producto, P739). Son 38.
--   3 GRANT EXECUTE de private.entrega_visible(uuid, integer, uuid) a authenticated (NO es un no-op: hoy su ACL es
--     {postgres=X/postgres}). La usa la policy entrega_evidencias_select (SELECT TO authenticated) de entrega_evidencias, asi
--     que hoy toda lectura de esa tabla por API da '42501 permission denied for function entrega_visible' (medido como
--     proveedor.qa el 6-oct-2026; el front no lo nota porque lee las evidencias por RPC DEFINER). Es la regla 10 de
--     CLAUDE.md (funcion nueva de private sin GRANT a authenticated). Lo hallaron P800 (l) y P1015. Sin PUBLIC ni anon.
-- Huellas: ACL de funciones e5c9770e31312d34601dc45f0c545173 384 -> 4878afd5e7fa74667b466d6994d565ff 384; policies 9ad61756... 307 y ACL de
-- relaciones de public 64ff833d... 2368 sin cambio.
-- Probes: P1015-P1018 (nuevos); P739 y P741 invertidos; P800 con reglas (j)-(m) sobre pg_proc.
-- Rollback: 370_rollback.sql (va ANTES que 369_rollback: la precondicion y el autochequeo de 369_rollback miran la ACL de
-- funciones; 370_rollback la devuelve a e5c9770e... 384). Y ANTES que 350_rollback y 349_rollback: con la 370 viva, devolver
-- esas policies a TO public le da a anon 42501 de FUNCION (get_auth_user_pais_id) en configuracion_sistema, perfiles,
-- pacientes, cuentas_proveedor, empresas_proveedoras, recetas, citas, facturas y campanas_publicitarias (medido en el
-- dry-run A con P935/P936, 6-oct-2026); configuracion_sistema la lee la landing sin sesion.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  -- huellas (misma formula que la 369)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'e5c9770e31312d34601dc45f0c545173 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  -- conteos del censo
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 38 THEN bad := bad||'funciones con PUBLIC '||n||' (esperado 38); '; END IF;
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 'anon'::regrole AND a.privilege_type = 'EXECUTE'));
  IF n <> 22 THEN bad := bad||'funciones con anon explicito '||n||' (esperado 22); '; END IF;
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND p.proacl IS NULL);
  IF n <> 15 THEN bad := bad||'funciones con proacl NULL '||n||' (esperado 15); '; END IF;
  n := (SELECT count(*) FROM pg_proc p JOIN pg_depend d ON d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF n <> 0 THEN bad := bad||n||' funciones de extension en public/private; '; END IF;

  -- las 10 que usan las policies y los triggers INVOKER: authenticated (y service_role en las de public) explicitos
  FOR r IN SELECT x.f, x.sr FROM (VALUES
      ('public.mi_empresa_proveedor()', true), ('public.mi_rol_proveedor()', true), ('public.get_auth_user_rol()', true),
      ('public.get_auth_user_pais_id()', true), ('public.puede_ver_conversacion(uuid)', true), ('public.mi_clinica_id()', true),
      ('public.supervisa_cuenta_proveedor(uuid)', true), ('public.admin_clinica_de_medico(uuid)', true),
      ('public.calcular_limite_cancelacion(date)', true), ('private.safe_uuid(text)', false)) x(f, sr) LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; CONTINUE; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = to_regprocedure(r.f) AND a.grantee = 'authenticated'::regrole AND a.privilege_type = 'EXECUTE') THEN
      bad := bad||r.f||' sin authenticated explicito; ';
    END IF;
    IF r.sr AND NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = to_regprocedure(r.f) AND a.grantee = 'service_role'::regrole AND a.privilege_type = 'EXECUTE') THEN
      bad := bad||r.f||' sin service_role explicito; ';
    END IF;
  END LOOP;

  -- ninguna policy evaluada por anon (roles {public} o {anon}) depende de una funcion de public/private
  v := (SELECT string_agg(DISTINCT pl.polname||' -> '||d.refobjid::regprocedure::text, ', ')
          FROM pg_policy pl JOIN pg_depend d ON d.classid = 'pg_policy'::regclass AND d.objid = pl.oid AND d.refclassid = 'pg_proc'::regclass
          JOIN pg_proc p ON p.oid = d.refobjid
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND (0 = ANY (pl.polroles) OR 'anon'::regrole = ANY (pl.polroles)));
  IF v IS NOT NULL THEN bad := bad||'policies de anon/public con funciones: '||v||'; '; END IF;

  -- entrega_visible: nacio sin EXECUTE para authenticated (regla 10); la 370 se lo da
  v := (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('private.entrega_visible(uuid,integer,uuid)'));
  IF v IS DISTINCT FROM '{postgres=X/postgres}' THEN bad := bad||'entrega_visible '||COALESCE(v, 'NO EXISTE')||'; '; END IF;

  -- la excepcion de producto, tal cual la dejo la 362
  v := (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('public.catalogo_planes_visitador_publico()'));
  IF v IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}' THEN
    bad := bad||'catalogo_planes_visitador_publico '||COALESCE(v, 'NO EXISTE')||'; ';
  END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG370 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: GRANT explicito (no-op documental)
GRANT EXECUTE ON FUNCTION public.mi_empresa_proveedor() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mi_rol_proveedor() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_auth_user_rol() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_auth_user_pais_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.puede_ver_conversacion(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mi_clinica_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.supervisa_cuenta_proveedor(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clinica_de_medico(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.calcular_limite_cancelacion(date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.safe_uuid(text) TO authenticated;

-- ---------------------------------------------------------------------------- 3: entrega_visible para la policy de evidencias
-- La policy entrega_evidencias_select (SELECT TO authenticated) la llama; sin EXECUTE la tabla le lanza 42501 a todo
-- authenticated (regla 10 de CLAUDE.md; hallado por P800 (l) y P1015). Sin PUBLIC ni anon.
GRANT EXECUTE ON FUNCTION private.entrega_visible(uuid, integer, uuid) TO authenticated;

-- ---------------------------------------------------------------------------- 2: REVOKE por catalogo
DO $revoke$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT p.oid FROM pg_proc p
            WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
              AND p.oid <> 'public.catalogo_planes_visitador_publico()'::regprocedure
              AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                           WHERE a.privilege_type = 'EXECUTE' AND (a.grantee = 0 OR a.grantee = 'anon'::regrole))
            ORDER BY p.oid LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.oid::regprocedure);
    n := n + 1;
  END LOOP;
  IF n <> 38 THEN RAISE EXCEPTION 'MIG370 REVOKE: se revocaron % funciones (esperado 38)', n; END IF;
END $revoke$;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones siguen con PUBLIC; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF n <> 1 OR NOT has_function_privilege('anon', 'public.catalogo_planes_visitador_publico()'::regprocedure, 'EXECUTE') THEN
    bad := bad||'anon ejecuta '||n||' ['||COALESCE(v, 'ninguna')||'] (esperado solo catalogo_planes_visitador_publico); ';
  END IF;
  FOR r IN SELECT x.f, x.sr FROM (VALUES
      ('public.mi_empresa_proveedor()', true), ('public.mi_rol_proveedor()', true), ('public.get_auth_user_rol()', true),
      ('public.get_auth_user_pais_id()', true), ('public.puede_ver_conversacion(uuid)', true), ('public.mi_clinica_id()', true),
      ('public.supervisa_cuenta_proveedor(uuid)', true), ('public.admin_clinica_de_medico(uuid)', true),
      ('public.calcular_limite_cancelacion(date)', true), ('private.safe_uuid(text)', false)) x(f, sr) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = to_regprocedure(r.f) AND a.grantee = 'authenticated'::regrole AND a.privilege_type = 'EXECUTE')
       OR NOT has_function_privilege('authenticated', to_regprocedure(r.f), 'EXECUTE') THEN
      bad := bad||r.f||' sin authenticated; ';
    END IF;
    IF r.sr AND (NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = to_regprocedure(r.f) AND a.grantee = 'service_role'::regrole AND a.privilege_type = 'EXECUTE')
                 OR NOT has_function_privilege('service_role', to_regprocedure(r.f), 'EXECUTE')) THEN
      bad := bad||r.f||' sin service_role; ';
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated', 'private.entrega_visible(uuid,integer,uuid)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('anon', 'private.entrega_visible(uuid,integer,uuid)'::regprocedure, 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                 WHERE p.oid = 'private.entrega_visible(uuid,integer,uuid)'::regprocedure AND a.grantee = 0) THEN
    bad := bad||'entrega_visible: '||COALESCE((SELECT proacl::text FROM pg_proc WHERE oid = 'private.entrega_visible(uuid,integer,uuid)'::regprocedure), '-')
           ||' (esperado authenticated si, anon y PUBLIC no); ';
  END IF;
  -- huellas: policies y relaciones sin cambio; funciones con la huella nueva medida en el dry-run
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4878afd5e7fa74667b466d6994d565ff 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG370 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
