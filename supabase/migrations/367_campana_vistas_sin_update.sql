-- ############################################################################################
-- 367 - campana_vistas sin UPDATE de authenticated (familia 2, F2-f parte 1)
-- ############################################################################################
-- Recon del 6-oct-2026 (solo lectura contra prod, sobre main 21a1ff8):
--   * campana_vistas: UNIQUE (campana_id, paciente_id); 2 policies TO authenticated ("Paciente crea sus vistas" INSERT y
--     "Paciente ve sus vistas" SELECT); NINGUNA de UPDATE. authenticated tiene arw: el UPDATE es un privilegio muerto que
--     estaba en la allowlist de P930 solo porque el front registraba la vista con upsert (ON CONFLICT DO UPDATE exige UPDATE).
--   * Ese upsert (registrarVista, useWebAppCampanas.ts:71) no tiene ningun llamador: la tabla tiene 0 filas. Los banners
--     registran impresiones y clicks en campana_metricas por la RPC DEFINER registrar_campana_metrica. Ninguna funcion,
--     edge ni trigger escribe campana_vistas, y nadie la lee.
-- Cambio: se revoca el UPDATE de authenticated en public.campana_vistas (regla 12: un privilegio de escritura solo junto con su
-- policy). El INSERT del paciente y el INSERT ... ON CONFLICT DO NOTHING (ignoreDuplicates) siguen andando; ON CONFLICT DO
-- UPDATE y el UPDATE directo dan 42501. Sin cambios de policies.
-- ACL de relaciones de public d05a8b3a... 2371 -> e2bb57f4... 2370; huella de policies sin cambio (a99ac4be... 307).
-- Front (mismo PR): se borra registrarVista, muerta. Probes: P1010 (nuevo); P930 sin la entrada de campana_vistas.
-- Rollback: 367_rollback.sql (GRANT UPDATE).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(pl.polname||'|'||pl.polcmd::text, ',' ORDER BY pl.polname) FROM pg_policy pl WHERE pl.polrelid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM 'Paciente crea sus vistas|a,Paciente ve sus vistas|r' THEN bad := bad||'policies ['||COALESCE(v, '-')||']; '; END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
     FROM pg_policy pl WHERE pl.polrelid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM 'fbf32b7248e5c2b05004c62510ba200d 2' THEN bad := bad||'texto de las policies '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.campana_vistas'::regclass AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL) THEN
    bad := bad||'hay privilegios por columna; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde 2371' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'a99ac4becc3fba65a272569c293fdd26 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG367 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cambio
REVOKE UPDATE ON public.campana_vistas FROM authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF has_table_privilege('authenticated', 'public.campana_vistas', 'UPDATE') OR has_any_column_privilege('authenticated', 'public.campana_vistas', 'UPDATE') THEN
    bad := bad||'authenticated conserva UPDATE; ';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.campana_vistas', 'INSERT') OR NOT has_table_privilege('authenticated', 'public.campana_vistas', 'SELECT') THEN
    bad := bad||'authenticated perdio INSERT o SELECT; ';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) pr
              WHERE NOT has_table_privilege('service_role', 'public.campana_vistas', pr)) THEN
    bad := bad||'service_role perdio algo; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
     FROM pg_policy pl WHERE pl.polrelid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM 'fbf32b7248e5c2b05004c62510ba200d 2' THEN bad := bad||'texto de las policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e2bb57f40da44965e21590fb92d7f9c3 2370' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG367 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
