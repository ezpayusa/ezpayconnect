-- ############################################################################################
-- 366 - datos bancarios acotados (familia 2, F2-e parte 2)
-- ############################################################################################
-- Recon del 5-oct-2026 (solo lectura contra prod, con la 365 aplicada):
--   * cuentas_bancarias_pais (1 fila, GT): "cuentas_banco_read_pais" = SELECT TO authenticated USING (pais_id =
--     private.mi_pais()). mi_pais() toma primero perfiles.pais_id: cualquier perfil de GT (medicos, clientes, soporte,
--     staff de clinica, comerciales...) leia la cuenta de deposito (banco, numero, titular, NIT, email de pagos). Y como el
--     resto de mi_pais() solo mira empresas ACTIVAS, un proveedor de una empresa pendiente no la veia: no podia pagar.
--   * Lectores legitimos: el checkout del proveedor (useCuentaBancariaCheckout.ts:31, los 4 tipos de PagoCheckoutPage),
--     el admin de cuentas (CuentasBancariasPage, super_admin, por cuentas_banco_admin) y /admin/planes/visitador
--     (PlanesVisitadorConfigPage.tsx:182, AdminRoute: super_admin y admin_pais). Las RPCs que la leen son DEFINER.
--   * configuracion_sistema (21 claves): "configuracion_sistema_select_authenticated" = USING true (todo authenticated
--     leia las 5 bancarias y las 2 integ_*); "configuracion_sistema_select_anon" = denylist de las 5 bancarias (anon leia
--     16, integ_email_smtp e integ_whatsapp_api incluidas). Nadie lee la tabla con sesion de usuario: el unico lector del
--     front (useConfiguracionSistema.ts) no tiene importadores, y /configuracion va por la edge actualizar-configuracion
--     (service_role, gate super_admin).
-- Decisiones de Oscar (5-oct-2026):
--   (A) cuentas_bancarias_pais la leen solo el super_admin, el admin_pais DE ESE PAIS y las cuentas de proveedor cuya
--       empresa sea de ese pais, en cualquier estado (activa, pendiente o suspendida: una empresa pendiente paga).
--   (B) configuracion_sistema: super_admin y admin_pais leen las 21; el resto de authenticated y anon, solo las 14
--       publicas por ALLOWLIST (una clave nueva nace oculta).
-- Cambio:
--   1 private.pais_empresa_onboarding(): el pais de la empresa del proveedor que llama, con el mismo filtro que
--     private.mi_empresa_onboarding() (cuenta activa; empresa activa, pendiente o suspendida). DEFINER, search_path ''.
--     EXECUTE solo para authenticated (regla 10: private nace con EXECUTE solo para postgres).
--   2 cuentas_bancarias_pais: DROP cuentas_banco_read_pais; CREATE cuentas_banco_read_acotada (SELECT TO authenticated):
--     private.puede_admin_pais(pais_id, super_admin) OR pais_id = private.pais_empresa_onboarding(), con COALESCE.
--     cuentas_banco_admin no se toca.
--   3 configuracion_sistema: DROP de las 2 de SELECT; CREATE configuracion_sistema_select_anon_publicas (TO anon, las 14)
--     y configuracion_sistema_select_authenticated_publicas (TO authenticated, las 14 OR super_admin/admin_pais).
--     "Admin ezpay actualiza configuracion" no se toca.
--   Sin cambios de ACL de tablas. ACL de funciones c7f89c6d... 380 -> 0ee90ba6869cce295105d3b32b893aed 381 (la funcion nueva).
-- Huella de policies 66bef0e5... 307 -> a99ac4becc3fba65a272569c293fdd26 307.
-- Probes: P1009 (nuevo); P755-P758 reescritos; P936 (anon config 16 -> 14).
-- Rollback: 366_rollback.sql (texto exacto de las 3 policies borradas, DROP de las 3 nuevas y de la funcion).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname))||' '||count(*)
     FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid WHERE pl.polrelid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM '59f52a89a6434f2bc3185e535f22c124 5' THEN bad := bad||'policies de las 2 tablas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT pg_get_expr(pl.polqual, pl.polrelid) FROM pg_policy pl WHERE pl.polrelid = 'public.cuentas_bancarias_pais'::regclass AND pl.polname = 'cuentas_banco_read_pais')
       IS DISTINCT FROM '(pais_id = private.mi_pais())' THEN bad := bad||'cuentas_banco_read_pais no es la del recon; '; END IF;
  IF (SELECT pg_get_expr(pl.polqual, pl.polrelid) FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_authenticated')
       IS DISTINCT FROM 'true' THEN bad := bad||'configuracion_sistema_select_authenticated no es la del recon; '; END IF;
  IF (SELECT pg_get_expr(pl.polqual, pl.polrelid) FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_anon')
       IS DISTINCT FROM '(clave <> ALL (ARRAY[''banco''::text, ''cuenta_bancaria''::text, ''tipo_cuenta''::text, ''titular_cuenta''::text, ''email_pagos''::text]))' THEN
    bad := bad||'configuracion_sistema_select_anon no es la del recon; ';
  END IF;
  v := (SELECT string_agg(c.relname||'='||c.relacl::text, ' ' ORDER BY c.relname) FROM pg_class c WHERE c.oid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM 'configuracion_sistema={postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres} '
                      ||'cuentas_bancarias_pais={postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de las 2 tablas '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(clave, ',' ORDER BY clave) FROM public.configuracion_sistema);
  IF v IS DISTINCT FROM 'app_logo_url,app_nombre,banco,color_fondo,color_primario,color_secundario,cuenta_bancaria,email_pagos,integ_email_smtp,'
                      ||'integ_google_calendar,integ_whatsapp_api,notif_email_activo,notif_recordatorios_activo,notif_sms_activo,notif_whatsapp_activo,'
                      ||'sistema_formato_fecha,sistema_idioma,sistema_moneda,sistema_zona_horaria,tipo_cuenta,titular_cuenta' THEN
    bad := bad||'claves de configuracion_sistema ['||COALESCE(v, '-')||']; ';
  END IF;
  IF (SELECT count(*) FROM public.cuentas_bancarias_pais) <> 1 THEN bad := bad||'cuentas_bancarias_pais no tiene 1 fila; '; END IF;
  IF to_regprocedure('private.pais_empresa_onboarding()') IS NOT NULL THEN bad := bad||'private.pais_empresa_onboarding ya existe; '; END IF;
  v := (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.mi_empresa_onboarding()'::regprocedure);
  IF v IS DISTINCT FROM '58097b3c4755458774653102bf9a2f3d' THEN bad := bad||'mi_empresa_onboarding cambio '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(prosrc)||' '||proacl::text FROM pg_proc WHERE oid = 'private.puede_admin_pais(uuid,text[])'::regprocedure);
  IF v IS DISTINCT FROM '8bc2928e369d98e305355440df8b52ac {postgres=X/postgres,authenticated=X/postgres}' THEN bad := bad||'puede_admin_pais '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '66bef0e55ba9d2a98434376a9222b5c6 307' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'c7f89c6df3048083e3722d6eec7d1998 380' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG366 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: helper del pais de la empresa (cualquier estado)
CREATE FUNCTION private.pais_empresa_onboarding()
  RETURNS uuid
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path = ''
AS $fn$
  -- El pais de la empresa del proveedor que llama, con el mismo filtro que private.mi_empresa_onboarding(): cuenta
  -- activa y empresa activa, pendiente o suspendida (una empresa pendiente tiene que poder ver donde pagar). NULL si el
  -- llamante no es una cuenta de proveedor asi (fail-closed en la policy con COALESCE).
  SELECT e.pais_id
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo = true AND e.estado IN ('activa','pendiente','suspendida')
   LIMIT 1;
$fn$;
REVOKE ALL ON FUNCTION private.pais_empresa_onboarding() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.pais_empresa_onboarding() TO authenticated;

-- ---------------------------------------------------------------------------- 2: cuentas_bancarias_pais
DROP POLICY cuentas_banco_read_pais ON public.cuentas_bancarias_pais;
CREATE POLICY cuentas_banco_read_acotada ON public.cuentas_bancarias_pais
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (COALESCE(private.puede_admin_pais(pais_id, ARRAY['super_admin'::text]), false)
         OR COALESCE(pais_id = private.pais_empresa_onboarding(), false));

-- ---------------------------------------------------------------------------- 3: configuracion_sistema
DROP POLICY configuracion_sistema_select_authenticated ON public.configuracion_sistema;
DROP POLICY configuracion_sistema_select_anon ON public.configuracion_sistema;
CREATE POLICY configuracion_sistema_select_anon_publicas ON public.configuracion_sistema
  AS PERMISSIVE FOR SELECT TO anon
  USING (clave = ANY (ARRAY['app_logo_url'::text, 'app_nombre'::text, 'color_fondo'::text, 'color_primario'::text, 'color_secundario'::text,
                            'integ_google_calendar'::text, 'notif_email_activo'::text, 'notif_recordatorios_activo'::text, 'notif_sms_activo'::text,
                            'notif_whatsapp_activo'::text, 'sistema_formato_fecha'::text, 'sistema_idioma'::text, 'sistema_moneda'::text,
                            'sistema_zona_horaria'::text]));
CREATE POLICY configuracion_sistema_select_authenticated_publicas ON public.configuracion_sistema
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((clave = ANY (ARRAY['app_logo_url'::text, 'app_nombre'::text, 'color_fondo'::text, 'color_primario'::text, 'color_secundario'::text,
                             'integ_google_calendar'::text, 'notif_email_activo'::text, 'notif_recordatorios_activo'::text, 'notif_sms_activo'::text,
                             'notif_whatsapp_activo'::text, 'sistema_formato_fecha'::text, 'sistema_idioma'::text, 'sistema_moneda'::text,
                             'sistema_zona_horaria'::text]))
         OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text, 'admin_pais'::text]), false));

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname))||' '||count(*)
     FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid WHERE pl.polrelid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM 'b1642cf529b1d5c6ee3c4bb98c2b68a6 5' THEN bad := bad||'policies de las 2 tablas '||COALESCE(v, '-')||'; '; END IF;
  -- las 2 no tocadas, con su texto de antes
  IF (SELECT pg_get_expr(pl.polqual, pl.polrelid)||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') FROM pg_policy pl
        WHERE pl.polrelid = 'public.cuentas_bancarias_pais'::regclass AND pl.polname = 'cuentas_banco_admin')
     IS DISTINCT FROM '(EXISTS ( SELECT 1'||E'\n'||'   FROM perfiles p'||E'\n'||'  WHERE ((p.id = auth.uid()) AND (p.rol = ''super_admin''::text))))|(EXISTS ( SELECT 1'||E'\n'||'   FROM perfiles p'||E'\n'||'  WHERE ((p.id = auth.uid()) AND (p.rol = ''super_admin''::text))))' THEN
    bad := bad||'cuentas_banco_admin cambio; ';
  END IF;
  IF (SELECT pg_get_expr(pl.polqual, pl.polrelid)||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') FROM pg_policy pl
        WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'Admin ezpay actualiza configuracion')
     IS DISTINCT FROM '(EXISTS ( SELECT 1'||E'\n'||'   FROM perfiles p'||E'\n'||'  WHERE ((p.id = auth.uid()) AND (p.rol = ''super_admin''::text))))|-' THEN
    bad := bad||'"Admin ezpay actualiza configuracion" cambio; ';
  END IF;
  v := (SELECT p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(array_to_string(p.proconfig, ','), '-')||' '||p.proacl::text||' '||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.pais_empresa_onboarding()'));
  IF v IS DISTINCT FROM 'true s search_path="" {postgres=X/postgres,authenticated=X/postgres} postgres' THEN bad := bad||'helper '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  IF has_function_privilege('anon', 'private.pais_empresa_onboarding()', 'EXECUTE') THEN bad := bad||'anon ejecuta el helper; '; END IF;
  v := (SELECT string_agg(c.relname||'='||c.relacl::text, ' ' ORDER BY c.relname) FROM pg_class c WHERE c.oid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM 'configuracion_sistema={postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres} '
                      ||'cuentas_bancarias_pais={postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de las 2 tablas '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'a99ac4becc3fba65a272569c293fdd26 307' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '0ee90ba6869cce295105d3b32b893aed 381' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG366 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
