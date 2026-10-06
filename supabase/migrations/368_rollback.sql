-- ############################################################################################
-- 368 ROLLBACK - el admin_pais vuelve a ver las 21 claves de configuracion_sistema
-- ############################################################################################
-- Vuelve configuracion_sistema_select_authenticated_publicas al qual EXACTO de la 366 (las 14 publicas OR
-- super_admin/admin_pais). Va ANTES que 367_rollback y que 366_rollback.
-- Precondicion: la 368 esta viva (qual sin admin_pais, huella de policies 2c6e39d7... 307).
-- Autochequeo: huella de policies a99ac4be... 307.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 368)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF position('admin_pais' IN (SELECT pg_get_expr(pl.polqual, pl.polrelid) FROM pg_policy pl
                                WHERE pl.polrelid = 'public.configuracion_sistema'::regclass AND pl.polname = 'configuracion_sistema_select_authenticated_publicas')) > 0 THEN
    bad := bad||'el qual todavia menciona admin_pais (la 368 no esta aplicada); ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '2c6e39d704ebd6a2e28542b9d3b4fbc0 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK368 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

ALTER POLICY configuracion_sistema_select_authenticated_publicas ON public.configuracion_sistema
  USING ((clave = ANY (ARRAY['app_logo_url'::text, 'app_nombre'::text, 'color_fondo'::text, 'color_primario'::text, 'color_secundario'::text,
                             'integ_google_calendar'::text, 'notif_email_activo'::text, 'notif_recordatorios_activo'::text, 'notif_sms_activo'::text,
                             'notif_whatsapp_activo'::text, 'sistema_formato_fecha'::text, 'sistema_idioma'::text, 'sistema_moneda'::text,
                             'sistema_zona_horaria'::text]))
         OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text, 'admin_pais'::text]), false));

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK368 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
