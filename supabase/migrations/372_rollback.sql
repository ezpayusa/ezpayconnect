-- ############################################################################################
-- 372_rollback - deshace 372_textos_legales_hardening.sql (GL-02: hardening de textos legales) y deja el estado
-- post-371 EXACTO
-- ############################################################################################
-- Va ANTES que 371_rollback (la precondicion de 371_rollback exige la ACL de funciones post-371 4c1f611c.../389, y la
-- 372 la deja en 391). Orden global: 372_rollback -> 371_rollback -> 370_rollback -> ...
-- Si el front de GL-02 ya muestra LG006 o los mensajes nuevos de la 372, revertirlo antes (con este rollback LG006 deja
-- de existir y los mensajes vuelven a los de la 371).
-- NO exige 0 aceptaciones: este rollback no borra ni modifica filas de aceptaciones_legales (solo saca la FK y el trigger
-- de fecha; las filas existentes quedan como estan, con el aceptado_at que les fijo la 372).
-- Precondicion: el estado post-372 exacto (huellas post-372, md5(prosrc) de las 7 funciones medidos en el dry-run v2 del
-- 8-oct-2026, objetos de la 372 presentes, solo_append INVOKER).
-- Cambios: DROP de la FK, del trigger de fecha y de su funcion; aceptar_textos_legales, textos_legales_pendientes y
-- textos_legales_pendientes_de vuelven al cuerpo de 371_textos_legales.sql COPIADO SIN CAMBIOS (solo CREATE FUNCTION ->
-- CREATE OR REPLACE FUNCTION en la primera linea, para conservar el oid); despues DROP de private.identidad_legal;
-- solo_append vuelve a SECURITY DEFINER; ACL y COMMENT exactos de la 371.
-- Autochequeo: huellas post-371 (policies 8a8dc5cf.../309, relaciones d065decf.../2394, funciones 4c1f611c.../389),
-- md5(prosrc) de las 5 funciones = los de la 371, solo los 2 triggers de la 371, sin FK a auth.users, LG006 ausente.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-372)
DO $precondicion$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '5482f6de564741ad445f30d3ccbd9a79 391' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  -- md5(prosrc) post-372 de las 7 funciones (dry-run v2 de la 372, 8-oct-2026)
  FOR r IN SELECT x.f, x.m FROM (VALUES
      ('public.aceptar_textos_legales(jsonb,text,text)', '7fe84db6b866b5fc846b47ab255f73c6'),
      ('public.textos_legales_pendientes()',             '880bacbe3c01e0cca420fa02a76d0d92'),
      ('private.textos_legales_pendientes_de(uuid)',     '916968ecdc50dab1059984e40e377fa1'),
      ('private.identidad_legal(uuid)',                  'ed8687ff662f8ff289a4677ce31b60b0'),
      ('private.aceptaciones_legales_fija_fecha()',      '14e1c35f28a94fe7c459dd4b7b512440'),
      ('private.aceptaciones_legales_solo_append()',     'baa1ac304a19794b770ca8840e077f5f'),
      ('private.textos_legales_al_dia(uuid)',            'fe75239007bb488512eb3dc1cc8ad43a')) x(f, m) LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.f));
    IF v IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5(prosrc) '||COALESCE(v, 'no existe')||' (esperado '||r.m||'); '; END IF;
  END LOOP;

  -- objetos de la 372 presentes
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.aceptaciones_legales'::regclass AND t.tgname = 'trg_aceptaciones_legales_fija_fecha') THEN
    bad := bad||'falta trg_aceptaciones_legales_fija_fecha; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.aceptaciones_legales'::regclass
                   AND c.conname = 'aceptaciones_legales_usuario_id_fkey' AND c.contype = 'f' AND c.confrelid = 'auth.users'::regclass) THEN
    bad := bad||'falta aceptaciones_legales_usuario_id_fkey; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'private.aceptaciones_legales_solo_append()'::regprocedure AND NOT p.prosecdef) THEN
    bad := bad||'aceptaciones_legales_solo_append no es INVOKER; ';
  END IF;
  -- sin exigencia de 0 aceptaciones: el rollback no toca filas (ver cabecera)

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK372 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: FK y fecha forzada
ALTER TABLE public.aceptaciones_legales DROP CONSTRAINT aceptaciones_legales_usuario_id_fkey;
DROP TRIGGER trg_aceptaciones_legales_fija_fecha ON public.aceptaciones_legales;
DROP FUNCTION private.aceptaciones_legales_fija_fecha();

-- ---------------------------------------------------------------------------- 2: cuerpos de la 371 (sin cambios)
-- 371_textos_legales.sql L196-L223
CREATE OR REPLACE FUNCTION private.textos_legales_pendientes_de(p_uid uuid)
 RETURNS TABLE (codigo text, version text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH ident AS (
    SELECT EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.auth_user_id = p_uid) AS es_paciente,
           (EXISTS (SELECT 1 FROM public.perfiles pf
                     WHERE pf.id = p_uid
                       AND pf.rol IN ('medico','admin_clinica','gerente','secretaria','enfermeria','asistente_medico'))
            OR EXISTS (SELECT 1 FROM public.cuentas_proveedor cp WHERE cp.id = p_uid)) AS es_profesional
  )
  SELECT t.codigo, t.version
    FROM public.textos_legales t CROSS JOIN ident i
   WHERE p_uid IS NOT NULL
     AND t.exigible
     AND ('todos' = ANY (t.aplica_a)
          OR ('paciente' = ANY (t.aplica_a) AND i.es_paciente)
          OR ('profesional' = ANY (t.aplica_a) AND i.es_profesional))
     AND NOT EXISTS (SELECT 1 FROM public.aceptaciones_legales a
                      WHERE a.usuario_id = p_uid AND a.codigo = t.codigo AND a.version = t.version)
   ORDER BY t.codigo;
$function$;
COMMENT ON FUNCTION private.textos_legales_pendientes_de(uuid) IS
  'Mig 371. Unica fuente de la regla "que textos exige cada rol": textos exigibles que aplican al uid (todos; paciente si tiene fila en pacientes; profesional si es perfil clinico o tiene cuenta_proveedor) sin aceptacion de la version vigente. EXECUTE solo postgres.';
REVOKE ALL ON FUNCTION private.textos_legales_pendientes_de(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- 371_textos_legales.sql L239-L258
CREATE OR REPLACE FUNCTION public.textos_legales_pendientes()
 RETURNS TABLE (codigo text, version text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida para consultar los textos legales' USING ERRCODE = 'LG001';
  END IF;
  RETURN QUERY SELECT x.codigo, x.version FROM private.textos_legales_pendientes_de(v_uid) x;
END
$function$;
COMMENT ON FUNCTION public.textos_legales_pendientes() IS
  'Mig 371 (GL-02). Textos legales que el llamante tiene que aceptar (codigo, version vigente). Sin sesion -> LG001 (nunca 0 filas).';
REVOKE ALL ON FUNCTION public.textos_legales_pendientes() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.textos_legales_pendientes() TO authenticated, service_role;

-- 371_textos_legales.sql L261-L338
CREATE OR REPLACE FUNCTION public.aceptar_textos_legales(p_textos jsonb, p_via text DEFAULT 'login', p_user_agent text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_ua        text;
  v_el        jsonb;
  v_codigo    text;
  v_version   text;
  v_vigente   text;
  v_vistos    text[] := ARRAY[]::text[];
  v_n         int;
  v_aceptados int := 0;
  v_ya        int := 0;
  v_pend      jsonb;
BEGIN
  -- gate primero
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sesion requerida para aceptar textos legales' USING ERRCODE = 'LG001';
  END IF;

  IF p_via IS NULL OR p_via NOT IN ('registro', 'login', 'app') THEN
    RAISE EXCEPTION 'Via de aceptacion invalida' USING ERRCODE = 'LG004';
  END IF;
  IF p_textos IS NULL OR jsonb_typeof(p_textos) <> 'array' THEN
    RAISE EXCEPTION 'La lista de textos tiene que ser un arreglo' USING ERRCODE = 'LG004';
  END IF;
  v_n := jsonb_array_length(p_textos);
  IF v_n < 1 OR v_n > 10 THEN
    RAISE EXCEPTION 'La lista de textos tiene que tener entre 1 y 10 elementos' USING ERRCODE = 'LG004';
  END IF;

  -- user_agent: sin caracteres de control, recortado y truncado a 300 (D-6); vacio -> NULL
  v_ua := NULLIF(left(btrim(regexp_replace(COALESCE(p_user_agent, ''), '[[:cntrl:]]', ' ', 'g')), 300), '');

  -- un solo recorrido: cualquier RAISE deshace las filas ya insertadas en esta llamada
  FOR v_el IN SELECT e FROM jsonb_array_elements(p_textos) e LOOP
    IF jsonb_typeof(v_el) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_el -> 'codigo') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_el -> 'version') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Cada texto tiene que traer codigo y version' USING ERRCODE = 'LG004';
    END IF;
    v_codigo  := v_el ->> 'codigo';
    v_version := v_el ->> 'version';
    IF v_codigo = ANY (v_vistos) THEN
      RAISE EXCEPTION 'Texto repetido en la lista: %', v_codigo USING ERRCODE = 'LG004';
    END IF;
    v_vistos := v_vistos || v_codigo;

    SELECT t.version INTO v_vigente FROM public.textos_legales t WHERE t.codigo = v_codigo FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Texto legal inexistente' USING ERRCODE = 'LG002';
    END IF;
    IF v_version IS DISTINCT FROM v_vigente THEN
      RAISE EXCEPTION 'La version % de % ya no es la vigente', v_version, v_codigo USING ERRCODE = 'LG003';
    END IF;

    INSERT INTO public.aceptaciones_legales (usuario_id, codigo, version, via, user_agent)
    VALUES (v_uid, v_codigo, v_version, p_via, v_ua)
    ON CONFLICT (usuario_id, codigo, version) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 1 THEN v_aceptados := v_aceptados + 1; ELSE v_ya := v_ya + 1; END IF;
  END LOOP;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'version', x.version) ORDER BY x.codigo), '[]'::jsonb)
    INTO v_pend FROM private.textos_legales_pendientes_de(v_uid) x;

  RETURN jsonb_build_object('aceptados', v_aceptados, 'ya_aceptados', v_ya, 'pendientes', v_pend);
END
$function$;
COMMENT ON FUNCTION public.aceptar_textos_legales(jsonb, text, text) IS
  'Mig 371 (GL-02). Registra la aceptacion de textos legales del llamante (auth.uid()). p_textos = [{"codigo":..,"version":..}] (1-10, sin repetidos); p_via registro|login|app. Idempotente por usuario/texto/version. Devuelve {aceptados, ya_aceptados, pendientes}. LG001-LG004.';
REVOKE ALL ON FUNCTION public.aceptar_textos_legales(jsonb, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aceptar_textos_legales(jsonb, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 3: identidad_legal ya no la usa nadie
DROP FUNCTION private.identidad_legal(uuid);

-- ---------------------------------------------------------------------------- 4: solo_append vuelve a DEFINER; COMMENT de la 371
ALTER FUNCTION private.aceptaciones_legales_solo_append() SECURITY DEFINER;
-- 371_textos_legales.sql L183-L185
COMMENT ON FUNCTION private.aceptaciones_legales_solo_append() IS
  'Mig 371. BEFORE UPDATE OR DELETE (fila) y BEFORE TRUNCATE (sentencia) de aceptaciones_legales: LG005 para todos.';
REVOKE ALL ON FUNCTION private.aceptaciones_legales_solo_append() FROM PUBLIC, anon, authenticated, service_role;
-- 371_textos_legales.sql L153-L154
COMMENT ON TABLE public.aceptaciones_legales IS
  'Mig 371 (GL-02). Append-only: una fila por usuario/texto/version aceptada. Se escribe solo por aceptar_textos_legales (usuario_id = auth.uid()). UPDATE/DELETE/TRUNCATE dan LG005 para todos. Sin IP.';

-- ---------------------------------------------------------------------------- autochequeo (estado post-371)
DO $autochequeo$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  -- objetos de la 372 ausentes
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace
               AND p.proname IN ('identidad_legal', 'aceptaciones_legales_fija_fecha')) THEN
    bad := bad||'quedan funciones de la 372; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.aceptaciones_legales'::regclass AND c.contype = 'f'
               AND c.confrelid = 'auth.users'::regclass) THEN
    bad := bad||'queda FK de aceptaciones_legales a auth.users; ';
  END IF;

  -- solo los 2 triggers de la 371
  v := (SELECT string_agg(t.tgname||':'||t.tgtype::text||':'||t.tgenabled::text||':'||t.tgfoid::regprocedure::text, ',' ORDER BY t.tgname)
          FROM pg_trigger t WHERE t.tgrelid = 'public.aceptaciones_legales'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'trg_aceptaciones_legales_no_truncate:34:O:private.aceptaciones_legales_solo_append(),'
                      ||'trg_aceptaciones_legales_solo_append:27:O:private.aceptaciones_legales_solo_append()' THEN
    bad := bad||'triggers '||COALESCE(v, '-')||'; ';
  END IF;

  -- las 5 funciones de la 371: cuerpo (md5), DEFINER con search_path = '', dueno postgres, ACL y COMMENT exactos
  FOR r IN SELECT x.f, x.m, x.acl, x.c FROM (VALUES
      ('public.aceptar_textos_legales(jsonb,text,text)', '26cb312d862345b0099e96fdc4ba5464', 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE',
       'Mig 371 (GL-02). Registra la aceptacion de textos legales del llamante (auth.uid()). p_textos = [{"codigo":..,"version":..}] (1-10, sin repetidos); p_via registro|login|app. Idempotente por usuario/texto/version. Devuelve {aceptados, ya_aceptados, pendientes}. LG001-LG004.'),
      ('public.textos_legales_pendientes()',             'baa5ee4e82dd110585282ff97b7ba0f7', 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE',
       'Mig 371 (GL-02). Textos legales que el llamante tiene que aceptar (codigo, version vigente). Sin sesion -> LG001 (nunca 0 filas).'),
      ('private.textos_legales_pendientes_de(uuid)',     'eb41c39c7a0ee7673ddfe56f47416b59', 'postgres:EXECUTE',
       'Mig 371. Unica fuente de la regla "que textos exige cada rol": textos exigibles que aplican al uid (todos; paciente si tiene fila en pacientes; profesional si es perfil clinico o tiene cuenta_proveedor) sin aceptacion de la version vigente. EXECUTE solo postgres.'),
      ('private.textos_legales_al_dia(uuid)',            'fe75239007bb488512eb3dc1cc8ad43a', 'postgres:EXECUTE',
       'Mig 371. true si el uid no tiene textos legales pendientes; uid NULL -> false. No lo usa ninguna RPC todavia (D-12). EXECUTE solo postgres: si una policy o RPC de authenticated lo llama, su migracion lleva el GRANT (regla 10).'),
      ('private.aceptaciones_legales_solo_append()',     'baa1ac304a19794b770ca8840e077f5f', 'postgres:EXECUTE',
       'Mig 371. BEFORE UPDATE OR DELETE (fila) y BEFORE TRUNCATE (sentencia) de aceptaciones_legales: LG005 para todos.')) x(f, m, acl, c) LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; CONTINUE; END IF;
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.f));
    IF v IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5(prosrc) '||COALESCE(v, '-')||' (esperado '||r.m||'); '; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND p.prosecdef
                     AND p.proconfig = ARRAY['search_path=""'] AND p.proowner = 'postgres'::regrole) THEN
      bad := bad||r.f||' no es DEFINER con search_path vacio y dueno postgres; ';
    END IF;
    v := (SELECT string_agg(z.g, ',' ORDER BY z.g COLLATE "C") FROM (
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type AS g
              FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE p.oid = to_regprocedure(r.f)) z);
    IF v IS DISTINCT FROM r.acl THEN bad := bad||r.f||' ACL '||COALESCE(v, '-')||' (esperado '||r.acl||'); '; END IF;
    IF obj_description(to_regprocedure(r.f), 'pg_proc') IS DISTINCT FROM r.c THEN bad := bad||r.f||' COMMENT distinto del de la 371; '; END IF;
  END LOOP;
  IF obj_description('public.aceptaciones_legales'::regclass, 'pg_class') IS DISTINCT FROM
     'Mig 371 (GL-02). Append-only: una fila por usuario/texto/version aceptada. Se escribe solo por aceptar_textos_legales (usuario_id = auth.uid()). UPDATE/DELETE/TRUNCATE dan LG005 para todos. Sin IP.' THEN
    bad := bad||'COMMENT de aceptaciones_legales distinto del de la 371; ';
  END IF;

  -- LG006 no queda en ningun prosrc
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc LIKE '%LG006%');
  IF v IS NOT NULL THEN bad := bad||'LG006 sigue en: '||v||'; '; END IF;

  -- censo global
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- huellas post-371
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4c1f611c29b8b37d8076536d065069e0 389' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK372 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
