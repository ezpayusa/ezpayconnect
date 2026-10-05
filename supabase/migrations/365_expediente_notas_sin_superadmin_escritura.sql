-- ############################################################################################
-- 365 - expediente_notas: el super_admin no crea ni edita notas clinicas (familia 2, F2-e parte 1)
-- ############################################################################################
-- Recon del 5-oct-2026 (solo lectura contra prod, con la 364 aplicada):
--   * exp_superadmin_insert (INSERT, WITH CHECK private.tiene_rol(super_admin)) no restringe medico_id, paciente_id ni
--     cita_id, y private.expediente_notas_guardia no compara medico_id con auth.uid(): por API directa el super_admin
--     podia crear una nota firmada por cualquier medico sobre cualquier paciente; sin cita_id nace CERRADA (R1 de la
--     334), o sea inmutable desde el primer momento. El unico rastro era updated_by, que se pisa en cada UPDATE.
--   * exp_superadmin_update (UPDATE, USING y WITH CHECK tiene_rol(super_admin)) le dejaba editar las notas ABIERTAS de
--     cualquier medico (las cerradas ya las protege NT006).
--   * Ningun flujo las usa: el unico INSERT del front (useConsultas.ts:91) manda medico_id = el usuario, y como
--     super_admin sobre la cita de otro medico el trigger ya lo rechaza con NT010; ninguna RPC ni edge escribe la tabla.
--   * Datos: 3 notas, todas con updated_by NULL o = el medico; 0 revisiones editadas por un super_admin.
-- Decision de Oscar (5-oct-2026): el super_admin no crea ni edita notas de un medico; conserva la lectura
-- (exp_superadmin_select). Las correcciones las hace el medico por corregir_nota_consulta (334).
-- Cambio: DROP de exp_superadmin_insert y exp_superadmin_update. Nada mas: ni ACL (authenticated conserva INSERT y
-- UPDATE, que usan exp_insert_medico y exp_update_medico), ni el trigger de guardia, ni exp_superadmin_select.
-- Efecto: INSERT del super_admin con el medico_id de otro -> 42501 (WITH CHECK de RLS); UPDATE -> 0 filas sin error
-- (RLS sin policy de UPDATE filtra en silencio).
-- Huella de policies 1929c331... 309 -> 66bef0e5... 307; ACL de relaciones y de funciones sin cambio.
-- Probes: P1008 (nuevo); P896 (lista exacta de policies) y P888 (UPDATE del super_admin sobre nota cerrada) ajustados.
-- Rollback: 365_rollback.sql (texto exacto de las 2 policies).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), 'NULL')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), 'NULL'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass AND pl.polname IN ('exp_superadmin_insert', 'exp_superadmin_update'));
  IF v IS DISTINCT FROM 'exp_superadmin_insert|a|{authenticated}|true|NULL|private.tiene_rol(ARRAY[''super_admin''::text])'||E'\n'
                      ||'exp_superadmin_update|w|{authenticated}|true|private.tiene_rol(ARRAY[''super_admin''::text])|private.tiene_rol(ARRAY[''super_admin''::text])' THEN
    bad := bad||'las 2 policies del super_admin ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass AND pl.polname NOT IN ('exp_superadmin_insert', 'exp_superadmin_update'));
  IF v IS DISTINCT FROM '4d98fb00930c90e7f685bc8dea0a4712 6' THEN bad := bad||'las otras 6 policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.expediente_notas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.expediente_notas_guardia()'::regprocedure);
  IF v IS DISTINCT FROM '950c36d4959f5568e3a6fbf351713541' THEN bad := bad||'trigger de guardia '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname))||' '||count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'a44a3b5a6d4c9b918583ce44d4c3c419 2' THEN bad := bad||'triggers '||COALESCE(v, '-')||'; '; END IF;
  -- datos: nada escrito por otro que el medico, ni revisiones de un super_admin
  IF (SELECT count(*) FROM public.expediente_notas WHERE updated_by IS NOT NULL AND updated_by <> medico_id) <> 0 THEN
    bad := bad||'hay notas con updated_by distinto del medico (revisar datos); ';
  END IF;
  IF (SELECT count(*) FROM public.expediente_notas_revisiones r JOIN public.perfiles p ON p.id = r.editado_por WHERE p.rol = 'super_admin') <> 0 THEN
    bad := bad||'hay revisiones editadas por un super_admin (revisar datos); ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1929c33129d0f77f80020bdc0603243c 309' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG365 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cambio
DROP POLICY exp_superadmin_insert ON public.expediente_notas;
DROP POLICY exp_superadmin_update ON public.expediente_notas;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass);
  IF v IS DISTINCT FROM '4d98fb00930c90e7f685bc8dea0a4712 6' THEN bad := bad||'policies de expediente_notas '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass AND pl.polcmd IN ('a', 'w', '*')
               AND (COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '')||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '')) ILIKE '%super_admin%') THEN
    bad := bad||'queda una policy INSERT/UPDATE/ALL que menciona super_admin; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.expediente_notas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.expediente_notas_guardia()'::regprocedure);
  IF v IS DISTINCT FROM '950c36d4959f5568e3a6fbf351713541' THEN bad := bad||'trigger de guardia '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname))||' '||count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'a44a3b5a6d4c9b918583ce44d4c3c419 2' THEN bad := bad||'triggers '||COALESCE(v, '-')||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG365 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
