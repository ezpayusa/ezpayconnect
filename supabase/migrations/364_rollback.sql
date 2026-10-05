-- ############################################################################################
-- 364 ROLLBACK - visitas_agendadas vuelve a tener UPDATE directo
-- ############################################################################################
-- Recrea las 2 policies de UPDATE con su texto EXACTO previo (tomado del objeto vivo el 5-oct-2026: TO authenticated,
-- PERMISSIVE, sin WITH CHECK) y devuelve GRANT UPDATE ON public.visitas_agendadas TO authenticated.
-- Efecto: el medico vuelve a poder cambiar cualquier columna de sus visitas, y cualquier cuenta de la empresa cualquier
-- columna de las visitas de su empresa, por PostgREST directo.
-- Precondicion: la 364 esta viva (0 policies UPDATE/ALL, relacl sin UPDATE de authenticated, huella 1929c331... 309).
-- Autochequeo: huella de policies 6fd0d66d... 311, ACL de relaciones de public deedb2e6..., relacl de partida.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 364)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass AND pl.polcmd IN ('w', '*')) THEN
    bad := bad||'hay policies UPDATE o ALL en visitas_agendadas; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.visitas_agendadas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1929c33129d0f77f80020bdc0603243c 309' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK364 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

CREATE POLICY "Médico actualiza sus visitas" ON public.visitas_agendadas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (medico_id = auth.uid());
CREATE POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (empresa_id = public.mi_empresa_proveedor());
GRANT UPDATE ON public.visitas_agendadas TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), 'NULL'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass AND pl.polcmd IN ('w', '*'));
  IF v IS DISTINCT FROM 'Médico actualiza sus visitas|{authenticated}|true|(medico_id = auth.uid())|NULL'||E'\n'
                      ||'Proveedor cancela sus visitas|{authenticated}|true|(empresa_id = mi_empresa_proveedor())|NULL' THEN
    bad := bad||'policies de UPDATE ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.visitas_agendadas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK364 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
