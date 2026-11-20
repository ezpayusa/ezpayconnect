-- =====================================================================================================================
-- MIG 397 — cierre: los tokens de recetas salen del SELECT de authenticated + rotación de los expuestos (paso 2 de 2).
-- Diseño: output/diseno-396-tokens-20nov.md (20-nov-2026), decisiones D-1 a D-6 aprobadas como recomienda.
--
-- Por qué: authenticated tenía SELECT DE TABLA sobre recetas_avanzadas y dispensaciones (relacl authenticated=r, sin
-- attacl), así que quien pasara una policy de SELECT leía dispatch_token y confirmacion_token (y la copia del
-- dispatch_token en dispensaciones.codigo_qr): además del paciente dueño, el admin_clinica/gerente de la clínica del autor
-- y cualquier médico con una cita con el paciente. La 396 (aplicada) le dio al paciente su token por la RPC
-- mis_despachos_receta(), y el front del paciente (PR #99) ya no lo pide por SELECT.
--
-- Censo de lectores como authenticated (20-nov, origin/main 9d588a8): front src/pages/PacienteDetallePage.tsx:208 (lista
-- explícita, sin tokens) y src/webapp/hooks/useWebAppRecetas.ts:28 (embed recetas_avanzadas(dispatch_token_expira_at,
-- estado_dispensacion)); ninguna edge con sesión de usuario (generar-pdf-receta usa service_role); ninguna vista; harness:
-- 4 lecturas como authenticated (count(*) y columnas no secretas). Ninguna pide '*' ni un token.
--
-- Qué hace (y nada más):
--   1. recetas_avanzadas: REVOKE SELECT de tabla a authenticated; GRANT SELECT de todas las columnas MENOS
--      dispatch_token y confirmacion_token. dispensaciones: igual, MENOS codigo_qr. authenticated no tenía INSERT, UPDATE
--      ni DELETE en ninguna de las dos (solo SELECT); anon no tenía nada: no cambian. service_role y las funciones DEFINER
--      no cambian. Efecto: un select('*') o un embed que nombre una columna sin grant da 42501; toda columna nueva de
--      estas tablas necesita su GRANT SELECT (col) explícito en la misma migración.
--   2. Rotación (D-6): dispatch_token nuevo para las filas con dispatch_token vigente y confirmacion_token nuevo para las
--      filas con confirmacion_token vigente, con el mismo generador que el DEFAULT de la columna que usa emitir_receta al
--      insertar (encode(extensions.gen_random_bytes(32), 'hex')). No cambian los vencimientos ni ninguna otra columna. Los
--      vencidos no se tocan (no sirven). Las copias viejas en dispensaciones.codigo_qr quedan como historial (ya no
--      despachan: registrar_dispensacion compara contra recetas_avanzadas.dispatch_token).
--   MIG97 = guarda de la migración. Sin errcodes nuevos.
--
-- La ROTACIÓN NO SE REVIERTE: 397_rollback.sql solo devuelve los grants. Un QR abierto antes del apply deja de servir:
-- el paciente ve el nuevo al volver a abrir sus recetas.
--
-- Estado ANTES, medido el 20-nov-2026 18:23:10 UTC (post-396):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... 77ae9f738b13c5b920383d0cf0bda746 420
--   ACL de funciones (solo privilegios), public/private .......................... 6eca74c670156e3a2d290b96651fc30e 420
--   ACL de relaciones de public ................................................... 88e7fd697ef0703f8f1deb153e9c68d0 2448
--     (sin recetas_avanzadas ni dispensaciones .................................... 2fcc56f14173658062bfae3c43214b81 2414)
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... eba82b3fc822926313534f04caa4f853 309
--   recetas_avanzadas y dispensaciones: relacl {postgres=arwdDxtm/postgres,authenticated=r/postgres,
--   service_role=arwdDxtm/postgres}, sin attacl (las guardas comparan el relacl ORDENADO: después de 397_rollback el
--   GRANT deja las mismas entradas en otro orden). mis_despachos_receta() md5(prosrc) 3e0fe1250d0c85b7ac7daeab3344ff35.
--   Filas: recetas_avanzadas 17 (md5 e367fecb…), dispensaciones 5 (md5 597c4b11…); dispatch_token vigentes 4,
--   confirmacion_token vigentes 8. La guarda NO exige esos conteos (la app sigue emitiendo recetas): rota las vigentes al
--   momento del apply y verifica exactamente esas.
-- Huellas post-397: ver el dry-run (en el PR). Rollback: supabase/migrations/397_rollback.sql (va antes que 396_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/397_recetas_tokens_cierre.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 396 está aplicada; la 397 no
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proacl::text, '-') FROM pg_proc p WHERE p.oid = to_regprocedure('public.mis_despachos_receta()'))
     IS DISTINCT FROM '3e0fe1250d0c85b7ac7daeab3344ff35 true {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'la 396 no está aplicada (mis_despachos_receta distinta o ausente); ';
  END IF;
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas'), ('public.dispensaciones')) AS t(tabla) LOOP
    IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM 'authenticated=r/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
       OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
      bad := bad||'relacl o attacl de '||r.tabla||' distintos de los medidos (¿la 397 ya se aplicó?); ';
    END IF;
  END LOOP;
  -- columnas exactas (la lista de GRANT de abajo depende de ellas)
  IF (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = 'public.recetas_avanzadas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id,receta_base_id,paciente_id,medico_id,codigo_qr,firma_digital,estado_dispensacion,farmacia_id,fecha_dispensacion,pdf_url,created_at,updated_at,dispatch_token,dispatch_token_expira_at,emitida_at,confirmacion_token,confirmacion_token_expira_at'
     OR (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = 'public.dispensaciones'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id,receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,motivo_rechazo,farmaceutico_nombre,fecha_dispensacion,created_at,despachado_por' THEN
    bad := bad||'columnas de recetas_avanzadas o dispensaciones distintas de las medidas; ';
  END IF;
  -- censo en base: ninguna vista ni función INVOKER fuera del trigger de stock lee estas tablas
  IF EXISTS (SELECT 1 FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid JOIN pg_class vc ON vc.oid = rw.ev_class
              WHERE d.refobjid IN ('public.recetas_avanzadas'::regclass, 'public.dispensaciones'::regclass)
                AND vc.oid NOT IN ('public.recetas_avanzadas'::regclass, 'public.dispensaciones'::regclass)) THEN
    bad := bad||'hay vistas que leen recetas_avanzadas o dispensaciones; ';
  END IF;
  IF (SELECT string_agg(p.oid::regprocedure::text, ',') FROM pg_proc p
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND NOT p.prosecdef
         AND (p.prosrc ILIKE '%recetas_avanzadas%' OR p.prosrc ILIKE '%dispensaciones%'))
     IS DISTINCT FROM 'actualizar_stock_dispensacion()' THEN
    bad := bad||'funciones INVOKER que leen estas tablas distintas de las medidas; ';
  END IF;
  -- generador de los tokens y unicidad del dispatch_token
  IF (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
       WHERE d.adrelid = 'public.recetas_avanzadas'::regclass AND a.attname = 'dispatch_token') IS DISTINCT FROM 'encode(gen_random_bytes(32), ''hex''::text)'
     OR (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
       WHERE d.adrelid = 'public.recetas_avanzadas'::regclass AND a.attname = 'confirmacion_token') IS DISTINCT FROM 'encode(gen_random_bytes(32), ''hex''::text)'
     OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL
     OR to_regclass('public.recetas_avanzadas_dispatch_token_key') IS NULL THEN
    bad := bad||'generador de tokens o índice único de dispatch_token distintos de los medidos; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.recetas_avanzadas'::regclass AND NOT t.tgisinternal) THEN
    bad := bad||'recetas_avanzadas tiene triggers (la rotación los dispararía); ';
  END IF;

  -- huellas post-396 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '77ae9f738b13c5b920383d0cf0bda746 420' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '6eca74c670156e3a2d290b96651fc30e 420' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG97: precondición: %', bad USING ERRCODE = 'MIG97';
  END IF;

  -- estado de entrada para el autochequeo: filas de dispensaciones, y por cada fila de recetas_avanzadas la huella de
  -- todo MENOS los tokens, el md5 de cada token y si estaba vigente.
  PERFORM set_config('mig397.filas_disp', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.dispensaciones t), true);
  CREATE TEMP TABLE mig397_antes ON COMMIT DROP AS
    SELECT ra.id,
           md5(ra.dispatch_token) AS md_dispatch,
           md5(ra.confirmacion_token) AS md_confirmacion,
           ra.dispatch_token_expira_at > now() AS dispatch_vigente,
           ra.confirmacion_token_expira_at > now() AS confirmacion_vigente,
           md5((to_jsonb(ra) - 'dispatch_token' - 'confirmacion_token')::text) AS md_resto
      FROM public.recetas_avanzadas ra;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) recetas_avanzadas y dispensaciones: SELECT por columna, sin los tokens
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE SELECT ON TABLE public.recetas_avanzadas FROM authenticated;
GRANT SELECT (id, receta_base_id, paciente_id, medico_id, codigo_qr, firma_digital, estado_dispensacion, farmacia_id,
              fecha_dispensacion, pdf_url, created_at, updated_at, dispatch_token_expira_at, emitida_at,
              confirmacion_token_expira_at)
  ON TABLE public.recetas_avanzadas TO authenticated;

REVOKE SELECT ON TABLE public.dispensaciones FROM authenticated;
GRANT SELECT (id, receta_avanzada_id, farmacia_id, paciente_id, medico_id, medicamentos_dispensados, cantidad_items,
              total_dispensado, estado_dispensacion, motivo_rechazo, farmaceutico_nombre, fecha_dispensacion, created_at,
              despachado_por)
  ON TABLE public.dispensaciones TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) ROTACIÓN de los tokens vigentes (D-6)
-- ---------------------------------------------------------------------------------------------------------------------
UPDATE public.recetas_avanzadas
   SET dispatch_token = encode(extensions.gen_random_bytes(32), 'hex')
 WHERE id IN (SELECT a.id FROM mig397_antes a WHERE a.dispatch_vigente);

UPDATE public.recetas_avanzadas
   SET confirmacion_token = encode(extensions.gen_random_bytes(32), 'hex')
 WHERE id IN (SELECT a.id FROM mig397_antes a WHERE a.confirmacion_vigente);

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record; n_d int; n_c int; got text; want text; pac uuid;
BEGIN
  -- privilegios: relacl sin authenticated; attacl exacto; tokens sin SELECT y el resto con SELECT
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas', '{dispatch_token,confirmacion_token}'::text[]),
                                 ('public.dispensaciones', '{codigo_qr}'::text[])) AS t(tabla, tokens) LOOP
    IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM 'postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres' THEN
      bad := bad||'relacl de '||r.tabla||' = '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = r.tabla::regclass), '-')||'; ';
    END IF;
    v := (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), ',' ORDER BY a.attnum) FROM pg_attribute a
           WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped
             AND (a.attname = ANY (r.tokens)) = (a.attacl IS NOT NULL));
    IF v IS NOT NULL THEN bad := bad||'attacl de '||r.tabla||' fuera de lo esperado: '||v||'; '; END IF;
    v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
           WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped AND NOT (a.attname = ANY (r.tokens))
             AND a.attacl::text IS DISTINCT FROM '{authenticated=r/postgres}');
    IF v IS NOT NULL THEN bad := bad||'columnas de '||r.tabla||' con attacl distinto de {authenticated=r/postgres}: '||v||'; '; END IF;
    v := (SELECT string_agg(a.attname||':'||has_column_privilege('authenticated', r.tabla::regclass, a.attname, 'SELECT')::text, ',' ORDER BY a.attnum)
            FROM pg_attribute a WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped
             AND has_column_privilege('authenticated', r.tabla::regclass, a.attname, 'SELECT') = (a.attname = ANY (r.tokens)));
    IF v IS NOT NULL THEN bad := bad||'has_column_privilege(authenticated, SELECT) fuera de lo esperado en '||r.tabla||': '||v||'; '; END IF;
    IF has_table_privilege('authenticated', r.tabla::regclass, 'SELECT')
       OR has_any_column_privilege('authenticated', r.tabla::regclass, 'INSERT,UPDATE,REFERENCES')
       OR has_table_privilege('authenticated', r.tabla::regclass, 'DELETE,TRUNCATE,TRIGGER,MAINTAIN')
       OR has_any_column_privilege('anon', r.tabla::regclass, 'SELECT,INSERT,UPDATE,REFERENCES') THEN
      bad := bad||'privilegios de tabla de authenticated/anon sobre '||r.tabla||'; ';
    END IF;
  END LOOP;

  -- rotación: exactamente las vigentes de la entrada, con tokens nuevos bien formados; el resto, intacto
  n_d := (SELECT count(*) FROM mig397_antes a WHERE a.dispatch_vigente);
  n_c := (SELECT count(*) FROM mig397_antes a WHERE a.confirmacion_vigente);
  v := (SELECT string_agg(ra.id::text, ',') FROM public.recetas_avanzadas ra JOIN mig397_antes a ON a.id = ra.id
         WHERE (md5(ra.dispatch_token) = a.md_dispatch) = a.dispatch_vigente
            OR (md5(ra.confirmacion_token) = a.md_confirmacion) = a.confirmacion_vigente
            OR md5((to_jsonb(ra) - 'dispatch_token' - 'confirmacion_token')::text) IS DISTINCT FROM a.md_resto
            OR ra.dispatch_token !~ '^[0-9a-f]{64}$' OR ra.confirmacion_token !~ '^[0-9a-f]{64}$');
  IF v IS NOT NULL THEN bad := bad||'rotación fuera de lo esperado en las filas '||v||'; '; END IF;
  IF (SELECT count(*) FROM public.recetas_avanzadas) <> (SELECT count(*) FROM mig397_antes)
     OR EXISTS (SELECT 1 FROM public.recetas_avanzadas ra WHERE NOT EXISTS (SELECT 1 FROM mig397_antes a WHERE a.id = ra.id)) THEN
    bad := bad||'cambiaron las filas de recetas_avanzadas; ';
  END IF;
  IF (SELECT count(*) FROM public.recetas_avanzadas ra JOIN mig397_antes a ON a.id = ra.id WHERE md5(ra.dispatch_token) <> a.md_dispatch) <> n_d
     OR (SELECT count(*) FROM public.recetas_avanzadas ra JOIN mig397_antes a ON a.id = ra.id WHERE md5(ra.confirmacion_token) <> a.md_confirmacion) <> n_c THEN
    bad := bad||'cantidad de tokens rotados distinta de los vigentes de la entrada; ';
  END IF;
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.dispensaciones t)
     IS DISTINCT FROM current_setting('mig397.filas_disp', true) THEN
    bad := bad||'cambiaron filas de dispensaciones; ';
  END IF;
  RAISE NOTICE 'MIG97: dispatch_token rotados %, confirmacion_token rotados %', n_d, n_c;

  -- el paciente 23 sigue obteniendo sus vigentes por la RPC, con el token NUEVO
  pac := (SELECT pa.auth_user_id FROM public.pacientes pa WHERE pa.id = 23);
  IF pac IS NOT NULL THEN
    want := (SELECT count(*)||'|'||COALESCE(string_agg(ra.receta_base_id||':'||md5(ra.dispatch_token), ',' ORDER BY ra.receta_base_id), '')
               FROM public.recetas_avanzadas ra WHERE ra.paciente_id = '23' AND ra.dispatch_token_expira_at > now());
    PERFORM set_config('request.jwt.claims', json_build_object('sub', pac, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    got := (SELECT count(*)||'|'||COALESCE(string_agg(x.receta_id||':'||md5(x.dispatch_token), ',' ORDER BY x.receta_id), '')
              FROM public.mis_despachos_receta() x);
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF got IS DISTINCT FROM want THEN bad := bad||'mis_despachos_receta del paciente 23 = '||COALESCE(got, '-')||' (esperado '||COALESCE(want, '-')||'); '; END IF;
    IF EXISTS (SELECT 1 FROM public.recetas_avanzadas ra JOIN mig397_antes a ON a.id = ra.id
                WHERE ra.paciente_id = '23' AND a.dispatch_vigente AND position(md5(ra.dispatch_token) IN COALESCE(got, '')) = 0) THEN
      bad := bad||'mis_despachos_receta no devuelve el token nuevo; ';
    END IF;
  END IF;

  -- huellas: solo cambia la ACL de relaciones (las 2 tablas pierden el SELECT de tabla de authenticated)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname NOT IN ('recetas_avanzadas', 'dispensaciones')) x);
  IF v IS DISTINCT FROM '2fcc56f14173658062bfae3c43214b81 2414' THEN bad := bad||'huella de ACL de relaciones sin las 2 tablas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2446 THEN
    bad := bad||'la ACL de relaciones de public no quedó en 2446 entradas; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '77ae9f738b13c5b920383d0cf0bda746 420' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '6eca74c670156e3a2d290b96651fc30e 420' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG97: autochequeo: %', bad USING ERRCODE = 'MIG97';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
