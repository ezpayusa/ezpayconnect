-- =====================================================================================================================
-- ROLLBACK de la MIG 401 — citas vuelve a los DEFAULT de antes de la 401:
--   estado DEFAULT '''agendada'''::text (la cadena con las comillas adentro), motivo y notas DEFAULT 'NULL'::text.
--
-- LOS DATOS NO SE REVIERTEN: las citas a las que la 401 les pasó motivo/notas del texto 'NULL' a NULL (medido el 20-nov:
-- motivo en 27, 28, 29; notas en 27, 28, 29, 72, 1342-1346) quedan en NULL. Volver a escribir el texto 'NULL' sería
-- reponer basura; ningún lector distingue una cosa de la otra salvo para mostrar «NULL» en pantalla.
--
-- Va ANTES que 400_rollback (y que el rollback de cualquier migración anterior). Restaurar el DEFAULT viejo de estado vuelve a
-- romper todo INSERT que omita estado (viola citas_estado_valido); el único escritor vivo (crear_cita) lo manda explícito.
--
-- Precondición (MIG401R): el estado que deja la 401 (DEFAULT nuevos, 0 filas con el texto 'NULL') y las huellas post-401,
-- que son las mismas de post-400 (la 401 no mueve ninguna):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... f1581e8802f3a06dc7d1737c6aad51dd 424
--   ACL de funciones (solo privilegios), public/private .......................... d026ae246b0262142684e187b7b8710f 424
--   ACL de relaciones de public ................................................... d17d651fdbe1b592147983a9b133dbcf 2442
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... dabf9556bae56bcb910de70405314ad8 310
-- SQLSTATE MIG01 (5 caracteres); el mensaje lleva MIG401R.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/401_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(a.attname||'='||COALESCE(pg_get_expr(d.adbin, d.adrelid), '(sin default)'), ' ; ' ORDER BY a.attname)
          FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE a.attrelid = 'public.citas'::regclass AND a.attname IN ('estado', 'motivo', 'notas') AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'estado=''agendada''::text ; motivo=(sin default) ; notas=(sin default)' THEN
    bad := bad||'DEFAULT de citas distintos de los que deja la 401: '||COALESCE(v, '-')||'; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f1581e8802f3a06dc7d1737c6aad51dd 424' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'd026ae246b0262142684e187b7b8710f 424' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd17d651fdbe1b592147983a9b133dbcf 2442' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG401R: precondición: %', bad USING ERRCODE = 'MIG01';
  END IF;
  PERFORM set_config('mig401r.citas', (SELECT count(*)||' '||COALESCE(md5(string_agg(to_jsonb(c)::text, E'\n' ORDER BY c.id)), '-') FROM public.citas c), true);
END $precondicion$;

ALTER TABLE public.citas ALTER COLUMN estado SET DEFAULT '''agendada'''::text;
ALTER TABLE public.citas ALTER COLUMN motivo SET DEFAULT 'NULL'::text;
ALTER TABLE public.citas ALTER COLUMN notas SET DEFAULT 'NULL'::text;

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(a.attname||'='||COALESCE(pg_get_expr(d.adbin, d.adrelid), '(sin default)'), ' ; ' ORDER BY a.attname)
          FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE a.attrelid = 'public.citas'::regclass AND a.attname IN ('estado', 'motivo', 'notas') AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'estado=''''''agendada''''''::text ; motivo=''NULL''::text ; notas=''NULL''::text' THEN
    bad := bad||'DEFAULT de citas = '||COALESCE(v, '-')||'; ';
  END IF;
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(to_jsonb(c)::text, E'\n' ORDER BY c.id)), '-') FROM public.citas c)
     IS DISTINCT FROM current_setting('mig401r.citas', true) THEN
    bad := bad||'el rollback cambió datos de citas; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f1581e8802f3a06dc7d1737c6aad51dd 424' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG401R: autochequeo: %', bad USING ERRCODE = 'MIG01';
  END IF;
END $autochequeo$;

COMMIT;
