-- ############################################################################################
-- 365 ROLLBACK - el super_admin vuelve a poder crear y editar notas clinicas
-- ############################################################################################
-- Recrea exp_superadmin_insert y exp_superadmin_update con su texto EXACTO previo (tomado del objeto vivo el
-- 5-oct-2026: TO authenticated, PERMISSIVE). Efecto: el super_admin vuelve a poder insertar notas a nombre de cualquier
-- medico (sin cita nacen cerradas) y editar las abiertas, por PostgREST directo.
-- Precondicion: la 365 esta viva (6 policies en expediente_notas, huella 66bef0e5... 307).
-- Autochequeo: las 2 policies con su texto y huella de policies 1929c331... 309.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 365)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass);
  IF v IS DISTINCT FROM '4d98fb00930c90e7f685bc8dea0a4712 6' THEN bad := bad||'policies de expediente_notas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '66bef0e55ba9d2a98434376a9222b5c6 307' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK365 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

CREATE POLICY exp_superadmin_insert ON public.expediente_notas
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY exp_superadmin_update ON public.expediente_notas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), 'NULL')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), 'NULL'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass AND pl.polname IN ('exp_superadmin_insert', 'exp_superadmin_update'));
  IF v IS DISTINCT FROM 'exp_superadmin_insert|a|{authenticated}|true|NULL|private.tiene_rol(ARRAY[''super_admin''::text])'||E'\n'
                      ||'exp_superadmin_update|w|{authenticated}|true|private.tiene_rol(ARRAY[''super_admin''::text])|private.tiene_rol(ARRAY[''super_admin''::text])' THEN
    bad := bad||'las 2 policies del super_admin ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1929c33129d0f77f80020bdc0603243c 309' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK365 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
