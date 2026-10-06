-- ############################################################################################
-- 368 - configuracion_sistema: el admin_pais solo ve las 14 claves publicas (familia 2, F2-f parte 2)
-- ############################################################################################
-- Recon del 6-oct-2026 (solo lectura contra prod, con la 367 aplicada):
--   * La 366 dejo configuracion_sistema_select_authenticated_publicas = las 14 claves publicas OR super_admin/admin_pais.
--   * Nadie lee configuracion_sistema con sesion de usuario: /configuracion va por la edge actualizar-configuracion
--     (service_role, gate super_admin; un admin_pais recibe 403), ninguna RPC la lee y ninguna pantalla de admin-ezpay la
--     usa. El admin_pais no usa ninguna de las 7 claves no publicas (5 bancarias + integ_email_smtp/integ_whatsapp_api).
-- Cambio: ALTER POLICY configuracion_sistema_select_authenticated_publicas: se saca 'admin_pais' del tiene_rol. Mismo rol
-- ({authenticated}) y cmd (SELECT); las otras 2 policies y los GRANT no se tocan.
-- Huella de policies a99ac4be... 307 -> 2c6e39d7... 307; ACL de relaciones de public sin cambio (e2bb57f4... 2370).
-- Probes: P757 (admin_pais 21 -> 14, sin integ_* por nombre) y P1009 (config de los admin_pais 21 -> 14).
-- Rollback: 368_rollback.sql (qual exacto de la 366).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT pg_get_expr(pl.polqual, pl.polrelid)||' | '||pl.polcmd::text||' | '||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_authenticated_publicas');
  IF v IS DISTINCT FROM '((clave = ANY (ARRAY[''app_logo_url''::text, ''app_nombre''::text, ''color_fondo''::text, ''color_primario''::text, ''color_secundario''::text, '
                      ||'''integ_google_calendar''::text, ''notif_email_activo''::text, ''notif_recordatorios_activo''::text, ''notif_sms_activo''::text, '
                      ||'''notif_whatsapp_activo''::text, ''sistema_formato_fecha''::text, ''sistema_idioma''::text, ''sistema_moneda''::text, '
                      ||'''sistema_zona_horaria''::text])) OR COALESCE(private.tiene_rol(ARRAY[''super_admin''::text, ''admin_pais''::text]), false)) | r | {authenticated}' THEN
    bad := bad||'qual de configuracion_sistema_select_authenticated_publicas ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
     FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass);
  IF v IS DISTINCT FROM 'be7900d849dc893cd0aa2087909932f9 3' THEN bad := bad||'texto de las 3 policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'a99ac4becc3fba65a272569c293fdd26 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e2bb57f40da44965e21590fb92d7f9c3 2370' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG368 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cambio
ALTER POLICY configuracion_sistema_select_authenticated_publicas ON public.configuracion_sistema
  USING ((clave = ANY (ARRAY['app_logo_url'::text, 'app_nombre'::text, 'color_fondo'::text, 'color_primario'::text, 'color_secundario'::text,
                             'integ_google_calendar'::text, 'notif_email_activo'::text, 'notif_recordatorios_activo'::text, 'notif_sms_activo'::text,
                             'notif_whatsapp_activo'::text, 'sistema_formato_fecha'::text, 'sistema_idioma'::text, 'sistema_moneda'::text,
                             'sistema_zona_horaria'::text]))
         OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false));

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT pg_get_expr(pl.polqual, pl.polrelid)||' | '||pl.polcmd::text||' | '||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_authenticated_publicas');
  IF v IS DISTINCT FROM '((clave = ANY (ARRAY[''app_logo_url''::text, ''app_nombre''::text, ''color_fondo''::text, ''color_primario''::text, ''color_secundario''::text, '
                      ||'''integ_google_calendar''::text, ''notif_email_activo''::text, ''notif_recordatorios_activo''::text, ''notif_sms_activo''::text, '
                      ||'''notif_whatsapp_activo''::text, ''sistema_formato_fecha''::text, ''sistema_idioma''::text, ''sistema_moneda''::text, '
                      ||'''sistema_zona_horaria''::text])) OR COALESCE(private.tiene_rol(ARRAY[''super_admin''::text]), false)) | r | {authenticated}' THEN
    bad := bad||'qual nuevo ['||COALESCE(v, '-')||']; ';
  END IF;
  IF position('admin_pais' IN (SELECT pg_get_expr(pl.polqual, pl.polrelid) FROM pg_policy pl
                                WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_authenticated_publicas')) > 0 THEN
    bad := bad||'el qual todavia menciona admin_pais; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
     FROM pg_policy pl WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname <> 'configuracion_sistema_select_authenticated_publicas');
  IF v IS DISTINCT FROM '96246f4f7f652836272d97632096a032 2' THEN bad := bad||'las otras 2 policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e2bb57f40da44965e21590fb92d7f9c3 2370' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '2c6e39d704ebd6a2e28542b9d3b4fbc0 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG368 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
