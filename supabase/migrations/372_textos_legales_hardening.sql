-- ############################################################################################
-- 372 - GL-02 textos legales: hardening de la 371 (review #54: n2, n4, n5, n6, n7, n8, n9)
-- ############################################################################################
-- Recon: tmp/gl02_372/recon.md (8-oct-2026, sobre main 6d7f46f y prod post-371).
-- Va DESPUES de la 371, por huella: la precondicion exige el estado post-371 exacto (huellas + md5(prosrc) de las 5
-- funciones de la 371). Al reves no: la precondicion de la 371 exige que sus objetos no existan.
--
-- Cambios:
--   private.identidad_legal(uuid)  NUEVA (n8). Unica fuente de la identidad legal del uid: (es_paciente, es_profesional),
--                                  exactamente una fila, NULL -> (false, false). es_profesional = perfil con rol de
--                                  roles_catalogo.ambito = 'clinica' (JOIN, sin lista literal) o fila en cuentas_proveedor.
--                                  Hoy ambito = 'clinica' son exactamente los 6 roles de la lista de la 371 (la
--                                  precondicion lo exige: el resultado de pendientes_de no cambia).
--   private.textos_legales_pendientes_de(uuid)  misma firma; la identidad sale de identidad_legal (n8).
--   public.aceptar_textos_legales(jsonb, text, text)  misma firma y mismo contrato de retorno:
--     - recorre el array ORDER BY (e ->> 'codigo') (n7): dos llamadas concurrentes toman los FOR SHARE de
--       textos_legales y las entradas del UNIQUE de aceptaciones en el mismo orden.
--     - por elemento: tipo (LG004) -> repetido (LG004) -> existe (LG002) -> aplica a la identidad del llamante (LG006,
--       nuevo, n5) -> version vigente (LG003) -> INSERT ... ON CONFLICT DO NOTHING.
--     - LG006 usa la regla de pendientes_de ('todos', o 'paciente' con es_paciente, o 'profesional' con es_profesional)
--       SIN mirar exigible: aceptar un texto con exigible = false sigue permitido.
--     - el chequeo de objeto se mantiene aunque es redundante con el de codigo (n2).
--   public.textos_legales_pendientes()  solo cambia el mensaje de LG001.
--   Mensajes (n6): con tildes, en tu, sin interpolar nada que venga del cliente. LG005 conserva TG_OP (no es del cliente).
--   private.aceptaciones_legales_fija_fecha()  NUEVA (n4): trigger BEFORE INSERT FOR EACH ROW, NEW.aceptado_at := now().
--                                  Quien inserte (la RPC o service_role directo) no elige la fecha. Corre tambien para
--                                  las filas que ON CONFLICT DO NOTHING descarta, sin cambiar la deteccion del conflicto
--                                  (medido en 17.6: recon punto 8).
--   private.aceptaciones_legales_solo_append()  pasa a SECURITY INVOKER (n9), mismo cuerpo (md5(prosrc) sin cambio).
--   FK aceptaciones_legales_usuario_id_fkey  usuario_id -> auth.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT (n4): no
--                                  hay aceptaciones de uids inexistentes, y borrar un usuario con aceptaciones falla.
--                                  Hoy 0 filas; los borrados de usuarios del repo son rollbacks de altas en la misma
--                                  request (recon punto 5).
--
-- Errcodes (prefijo LG): LG001-LG005 sin cambio de significado; LG006 NUEVO = el texto no corresponde a la identidad de
--   la cuenta (aplica_a). Proximo libre: LG007.
--
-- Privilegios (CLAUDE.md, GRANTs explicitos; P800, P931):
--   las 2 RPCs: ACL exacta {postgres, authenticated, service_role} (REVOKE/GRANT explicitos, igual que la 371).
--   las 5 de private (identidad_legal, pendientes_de, al_dia, fija_fecha, solo_append): solo postgres (regla 10).
--   DEFINER con search_path = '': identidad_legal, pendientes_de, al_dia y las 2 RPCs (P931). Las 2 de trigger son
--   INVOKER con search_path = '' (no leen tablas; EXECUTE no se chequea al disparar un trigger).
--   Tablas: sin cambio de ACL. service_role conserva SELECT/INSERT/UPDATE/DELETE (regla 3); UPDATE/DELETE siguen dando
--   LG005 y aceptado_at lo fija el trigger.
-- Huellas: policies 8a8dc5cf.../309 y ACL de relaciones de public d065decf.../2394 SIN cambio; ACL de funciones
--   4c1f611c29b8b37d8076536d065069e0/389 -> 5482f6de564741ad445f30d3ccbd9a79/391 (CALCULADA el 8-oct-2026 con una
--   consulta de solo lectura: filas vivas + 2 filas sinteticas postgres=X/postgres de las funciones nuevas; la misma
--   consulta reproduce exacto la post-371; el dry-run la confirma). El autochequeo exige ademas que la huella de
--   funciones SIN las 2 nuevas siga siendo la post-371.
-- Probes: P1022 exige hoy 2 triggers exactos y las 5 funciones DEFINER; con la 372 viva sale ROJO hasta ajustarlo en el
--   mismo PR (proximo probe libre: P1023).
-- Riesgo aceptado (review #55 n2): service_role conserva SELECT/INSERT/UPDATE/DELETE (regla 3 de CLAUDE.md) y puede
--   insertar directo una aceptacion de un usuario REAL, de un texto que no le aplica y con via/user_agent a eleccion: el
--   INSERT directo no pasa por LG006 (que vive en aceptar_textos_legales). Lo que si queda cerrado: la fecha (trigger
--   trg_aceptaciones_legales_fija_fecha) y el uid inexistente (FK a auth.users). service_role solo existe server-side y
--   ninguna edge escribe en esta tabla hoy (recon de la 372, punto 4.a).
-- IDENTITY con huecos (review #55 n7): la secuencia de aceptaciones_legales.id tiene huecos por diseno (los probes y los
--   dry-runs consumen ids en transacciones abortadas; nextval no es transaccional). Un hueco no implica una fila borrada:
--   la inmutabilidad la garantizan los triggers LG005 (UPDATE/DELETE/TRUNCATE).
-- Rollback: 372_rollback.sql (vuelve exacto a post-371; funciona con aceptaciones cargadas, las conserva).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-371)
DO $precondicion$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  -- huellas (misma formula que la 371)
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

  -- md5(prosrc) de las 5 funciones de la 371 = el vivo medido el 8-oct-2026
  FOR r IN SELECT x.f, x.m FROM (VALUES
      ('public.aceptar_textos_legales(jsonb,text,text)', '26cb312d862345b0099e96fdc4ba5464'),
      ('public.textos_legales_pendientes()',             'baa5ee4e82dd110585282ff97b7ba0f7'),
      ('private.textos_legales_pendientes_de(uuid)',     'eb41c39c7a0ee7673ddfe56f47416b59'),
      ('private.textos_legales_al_dia(uuid)',            'fe75239007bb488512eb3dc1cc8ad43a'),
      ('private.aceptaciones_legales_solo_append()',     'baa1ac304a19794b770ca8840e077f5f')) x(f, m) LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.f));
    IF v IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5(prosrc) '||COALESCE(v, 'no existe')||' (esperado '||r.m||'); '; END IF;
  END LOOP;

  -- los objetos de la 372 no existen todavia; LG006 no esta en uso
  IF to_regprocedure('private.identidad_legal(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace AND p.proname = 'identidad_legal') THEN
    bad := bad||'private.identidad_legal ya existe; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace AND p.proname = 'aceptaciones_legales_fija_fecha') THEN
    bad := bad||'private.aceptaciones_legales_fija_fecha ya existe; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.aceptaciones_legales'::regclass AND t.tgname = 'trg_aceptaciones_legales_fija_fecha') THEN
    bad := bad||'trg_aceptaciones_legales_fija_fecha ya existe; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.aceptaciones_legales'::regclass
               AND (c.conname = 'aceptaciones_legales_usuario_id_fkey' OR (c.contype = 'f' AND c.confrelid = 'auth.users'::regclass))) THEN
    bad := bad||'aceptaciones_legales ya tiene FK a auth.users; ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc LIKE '%LG006%');
  IF v IS NOT NULL THEN bad := bad||'LG006 ya aparece en: '||v||'; '; END IF;

  -- la FK se puede crear: 0 aceptaciones de uids que no existen en auth.users
  n := (SELECT count(*) FROM public.aceptaciones_legales a WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.usuario_id));
  IF n <> 0 THEN bad := bad||n||' aceptaciones con usuario_id ausente en auth.users; '; END IF;

  -- identidad_legal reemplaza la lista literal por roles_catalogo.ambito = 'clinica': hoy tienen que ser los mismos 6
  -- roles, o pendientes_de cambiaria de resultado
  v := (SELECT string_agg(rc.codigo, ',' ORDER BY rc.codigo COLLATE "C") FROM public.roles_catalogo rc WHERE rc.ambito = 'clinica');
  IF v IS DISTINCT FROM 'admin_clinica,asistente_medico,enfermeria,gerente,medico,secretaria' THEN
    bad := bad||'roles con ambito clinica ['||COALESCE(v, 'ninguno')||'] (esperado los 6 de la 371); ';
  END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG372 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: identidad legal (una sola fuente, n8)
CREATE FUNCTION private.identidad_legal(p_uid uuid)
 RETURNS TABLE (es_paciente boolean, es_profesional boolean)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.auth_user_id = p_uid), false),
         COALESCE(EXISTS (SELECT 1 FROM public.perfiles pf
                            JOIN public.roles_catalogo rc ON rc.codigo = pf.rol
                           WHERE pf.id = p_uid AND rc.ambito = 'clinica')
                  OR EXISTS (SELECT 1 FROM public.cuentas_proveedor cp WHERE cp.id = p_uid), false);
$function$;
COMMENT ON FUNCTION private.identidad_legal(uuid) IS
  'Mig 372 (GL-02). Identidad legal del uid, una sola fila siempre: es_paciente (fila en pacientes) y es_profesional (perfil con rol de roles_catalogo.ambito = clinica, o fila en cuentas_proveedor). uid NULL o inexistente -> (false, false). La usan pendientes_de y aceptar_textos_legales. EXECUTE solo postgres.';
REVOKE ALL ON FUNCTION private.identidad_legal(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- 2: la regla por rol, con identidad_legal
CREATE OR REPLACE FUNCTION private.textos_legales_pendientes_de(p_uid uuid)
 RETURNS TABLE (codigo text, version text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH ident AS (
    SELECT il.es_paciente, il.es_profesional FROM private.identidad_legal(p_uid) il
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
  'Mig 371/372. Unica fuente de la regla "que textos exige cada rol": textos exigibles que aplican al uid (todos; paciente si es_paciente; profesional si es_profesional, ambos de private.identidad_legal) sin aceptacion de la version vigente. EXECUTE solo postgres.';
REVOKE ALL ON FUNCTION private.textos_legales_pendientes_de(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- 3: RPC de lectura (solo el mensaje)
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
    RAISE EXCEPTION 'Necesitas iniciar sesión para consultar los textos legales.' USING ERRCODE = 'LG001';
  END IF;
  RETURN QUERY SELECT x.codigo, x.version FROM private.textos_legales_pendientes_de(v_uid) x;
END
$function$;
COMMENT ON FUNCTION public.textos_legales_pendientes() IS
  'Mig 371/372 (GL-02). Textos legales que el llamante tiene que aceptar (codigo, version vigente). Sin sesion -> LG001 (nunca 0 filas).';
REVOKE ALL ON FUNCTION public.textos_legales_pendientes() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.textos_legales_pendientes() TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 4: RPC de escritura
CREATE OR REPLACE FUNCTION public.aceptar_textos_legales(p_textos jsonb, p_via text DEFAULT 'login', p_user_agent text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid            uuid := auth.uid();
  v_es_paciente    boolean;
  v_es_profesional boolean;
  v_ua             text;
  v_el             jsonb;
  v_codigo         text;
  v_version        text;
  v_vigente        text;
  v_aplica         text[];
  v_vistos         text[] := ARRAY[]::text[];
  v_n              int;
  v_aceptados      int := 0;
  v_ya             int := 0;
  v_pend           jsonb;
BEGIN
  -- gate primero
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Necesitas iniciar sesión para aceptar los textos legales.' USING ERRCODE = 'LG001';
  END IF;

  IF p_via IS NULL OR p_via NOT IN ('registro', 'login', 'app') THEN
    RAISE EXCEPTION 'La vía de aceptación no es válida.' USING ERRCODE = 'LG004';
  END IF;
  IF p_textos IS NULL OR jsonb_typeof(p_textos) <> 'array' THEN
    RAISE EXCEPTION 'La lista de textos tiene que ser un arreglo.' USING ERRCODE = 'LG004';
  END IF;
  v_n := jsonb_array_length(p_textos);
  IF v_n < 1 OR v_n > 10 THEN
    RAISE EXCEPTION 'La lista tiene que tener entre 1 y 10 textos.' USING ERRCODE = 'LG004';
  END IF;

  -- user_agent: sin caracteres de control, recortado y truncado a 300 (D-6); vacio -> NULL
  v_ua := NULLIF(left(btrim(regexp_replace(COALESCE(p_user_agent, ''), '[[:cntrl:]]', ' ', 'g')), 300), '');

  -- identidad del llamante, una vez (misma fuente que pendientes_de)
  SELECT il.es_paciente, il.es_profesional INTO v_es_paciente, v_es_profesional FROM private.identidad_legal(v_uid) il;

  -- un solo recorrido, en orden de codigo (n7): dos llamadas concurrentes toman los locks en el mismo orden. Cualquier
  -- RAISE deshace las filas ya insertadas en esta llamada.
  FOR v_el IN SELECT e FROM jsonb_array_elements(p_textos) e ORDER BY (e ->> 'codigo') LOOP
    -- tipo. El chequeo de objeto es redundante con el de codigo (sobre un no-objeto, v_el -> 'codigo' es NULL), pero
    -- se deja explicito (n2).
    IF jsonb_typeof(v_el) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_el -> 'codigo') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_el -> 'version') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Cada texto tiene que traer código y versión.' USING ERRCODE = 'LG004';
    END IF;
    v_codigo  := v_el ->> 'codigo';
    v_version := v_el ->> 'version';
    IF v_codigo = ANY (v_vistos) THEN
      RAISE EXCEPTION 'Hay un texto repetido en la lista.' USING ERRCODE = 'LG004';
    END IF;
    v_vistos := v_vistos || v_codigo;

    SELECT t.version, t.aplica_a INTO v_vigente, v_aplica FROM public.textos_legales t WHERE t.codigo = v_codigo FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Uno de los textos no existe.' USING ERRCODE = 'LG002';
    END IF;
    -- n5: el texto tiene que aplicar a la identidad del llamante (misma regla que pendientes_de). No mira exigible:
    -- aceptar un texto con exigible = false sigue permitido.
    IF NOT ('todos' = ANY (v_aplica)
            OR ('paciente' = ANY (v_aplica) AND v_es_paciente)
            OR ('profesional' = ANY (v_aplica) AND v_es_profesional)) THEN
      RAISE EXCEPTION 'Uno de los textos no corresponde a tu cuenta.' USING ERRCODE = 'LG006';
    END IF;
    IF v_version IS DISTINCT FROM v_vigente THEN
      RAISE EXCEPTION 'Uno de los textos no está en su versión vigente. Recarga la página e inténtalo de nuevo.' USING ERRCODE = 'LG003';
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
  'Mig 371/372 (GL-02). Registra la aceptacion de textos legales del llamante (auth.uid()). p_textos = [{"codigo":..,"version":..}] (1-10, sin repetidos), recorrido en orden de codigo; p_via registro|login|app. Cada texto tiene que aplicar a la identidad del llamante (LG006; no mira exigible). Idempotente por usuario/texto/version. Devuelve {aceptados, ya_aceptados, pendientes}. LG001-LG004, LG006.';
REVOKE ALL ON FUNCTION public.aceptar_textos_legales(jsonb, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aceptar_textos_legales(jsonb, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 5: fecha fijada por el servidor (n4)
CREATE FUNCTION private.aceptaciones_legales_fija_fecha()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  NEW.aceptado_at := now();
  RETURN NEW;
END
$function$;
COMMENT ON FUNCTION private.aceptaciones_legales_fija_fecha() IS
  'Mig 372. BEFORE INSERT (fila) de aceptaciones_legales: aceptado_at = now(), ignora lo que mande quien inserta. INVOKER, no lee tablas. EXECUTE solo postgres.';
REVOKE ALL ON FUNCTION private.aceptaciones_legales_fija_fecha() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_aceptaciones_legales_fija_fecha
  BEFORE INSERT ON public.aceptaciones_legales
  FOR EACH ROW EXECUTE FUNCTION private.aceptaciones_legales_fija_fecha();

-- ---------------------------------------------------------------------------- 6: inmutabilidad sin DEFINER (n9)
ALTER FUNCTION private.aceptaciones_legales_solo_append() SECURITY INVOKER;
COMMENT ON FUNCTION private.aceptaciones_legales_solo_append() IS
  'Mig 371/372. BEFORE UPDATE OR DELETE (fila) y BEFORE TRUNCATE (sentencia) de aceptaciones_legales: LG005 para todos. INVOKER desde la 372 (no lee tablas). EXECUTE solo postgres.';

-- ---------------------------------------------------------------------------- 7: usuario_id -> auth.users (n4)
ALTER TABLE public.aceptaciones_legales
  ADD CONSTRAINT aceptaciones_legales_usuario_id_fkey
  FOREIGN KEY (usuario_id) REFERENCES auth.users (id) ON DELETE RESTRICT ON UPDATE RESTRICT;
COMMENT ON TABLE public.aceptaciones_legales IS
  'Mig 371/372 (GL-02). Append-only: una fila por usuario/texto/version aceptada. Se escribe solo por aceptar_textos_legales (usuario_id = auth.uid()). aceptado_at lo fija un trigger (now()). usuario_id -> auth.users ON DELETE RESTRICT. UPDATE/DELETE/TRUNCATE dan LG005 para todos. Sin IP.';

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; n int; r record; st text; msg text;
BEGIN
  -- (a) funciones tocadas o nuevas: dueno postgres, search_path = '', prosecdef y ACL exacta
  FOR r IN SELECT x.f, x.acl, x.secdef FROM (VALUES
      ('private.identidad_legal(uuid)',                  'postgres:EXECUTE',                                            true),
      ('private.textos_legales_pendientes_de(uuid)',     'postgres:EXECUTE',                                            true),
      ('private.textos_legales_al_dia(uuid)',            'postgres:EXECUTE',                                            true),
      ('public.textos_legales_pendientes()',             'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE', true),
      ('public.aceptar_textos_legales(jsonb,text,text)', 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE', true),
      ('private.aceptaciones_legales_fija_fecha()',      'postgres:EXECUTE',                                            false),
      ('private.aceptaciones_legales_solo_append()',     'postgres:EXECUTE',                                            false)) x(f, acl, secdef) LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; CONTINUE; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND p.prosecdef = r.secdef
                     AND p.proconfig = ARRAY['search_path=""'] AND p.proowner = 'postgres'::regrole) THEN
      bad := bad||r.f||' prosecdef/search_path/dueno distinto de lo esperado (prosecdef '||r.secdef::text||'); ';
    END IF;
    v := (SELECT string_agg(z.g, ',' ORDER BY z.g COLLATE "C") FROM (
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type AS g
              FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE p.oid = to_regprocedure(r.f)) z);
    IF v IS DISTINCT FROM r.acl THEN bad := bad||r.f||' ACL '||COALESCE(v, '-')||' (esperado '||r.acl||'); '; END IF;
  END LOOP;
  -- cuerpo sin cambio en las que no se reescriben
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.aceptaciones_legales_solo_append()'::regprocedure) IS DISTINCT FROM 'baa1ac304a19794b770ca8840e077f5f' THEN
    bad := bad||'aceptaciones_legales_solo_append cambio de cuerpo; ';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.textos_legales_al_dia(uuid)'::regprocedure) IS DISTINCT FROM 'fe75239007bb488512eb3dc1cc8ad43a' THEN
    bad := bad||'textos_legales_al_dia cambio de cuerpo; ';
  END IF;

  -- (b) triggers exactos de aceptaciones_legales. tgtype: 7 = ROW|BEFORE|INSERT; 27 = ROW|BEFORE|DELETE|UPDATE;
  --     34 = BEFORE|TRUNCATE (sentencia)
  v := (SELECT string_agg(t.tgname||':'||t.tgtype::text||':'||t.tgenabled::text||':'||t.tgfoid::regprocedure::text, ',' ORDER BY t.tgname)
          FROM pg_trigger t WHERE t.tgrelid = 'public.aceptaciones_legales'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'trg_aceptaciones_legales_fija_fecha:7:O:private.aceptaciones_legales_fija_fecha(),'
                      ||'trg_aceptaciones_legales_no_truncate:34:O:private.aceptaciones_legales_solo_append(),'
                      ||'trg_aceptaciones_legales_solo_append:27:O:private.aceptaciones_legales_solo_append()' THEN
    bad := bad||'triggers '||COALESCE(v, '-')||'; ';
  END IF;

  -- (c) FK usuario_id -> auth.users(id), RESTRICT / RESTRICT, validada
  v := (SELECT string_agg(c.conname||':'||c.confrelid::regclass::text||':'||c.confdeltype::text||':'||c.confupdtype::text||':'||c.convalidated::text||':'||
                          (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)), ',')
          FROM pg_constraint c WHERE c.conrelid = 'public.aceptaciones_legales'::regclass AND c.contype = 'f' AND c.confrelid = 'auth.users'::regclass);
  IF v IS DISTINCT FROM 'aceptaciones_legales_usuario_id_fkey:auth.users:r:r:true:usuario_id' THEN bad := bad||'FK a auth.users '||COALESCE(v, '-')||'; '; END IF;

  -- (d) LG006 en aceptar; sin lista literal de roles en aceptar, pendientes_de ni identidad_legal
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.aceptar_textos_legales(jsonb,text,text)'::regprocedure) NOT LIKE '%''LG006''%' THEN
    bad := bad||'aceptar_textos_legales sin LG006; ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ') FROM pg_proc p
         WHERE p.oid IN ('public.aceptar_textos_legales(jsonb,text,text)'::regprocedure, 'private.textos_legales_pendientes_de(uuid)'::regprocedure,
                         'private.identidad_legal(uuid)'::regprocedure)
           AND p.prosrc ~ '''(medico|admin_clinica|gerente|secretaria|enfermeria|asistente_medico)''');
  IF v IS NOT NULL THEN bad := bad||'lista literal de roles en: '||v||'; '; END IF;

  -- (e) identidad_legal: NULL -> (false, false); uid inexistente -> exactamente 1 fila (false, false)
  v := (SELECT count(*)||':'||string_agg(il.es_paciente::text||'/'||il.es_profesional::text, ',') FROM private.identidad_legal(NULL) il);
  IF v IS DISTINCT FROM '1:false/false' THEN bad := bad||'identidad_legal(NULL) '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = '00000000-0000-4372-8000-000000000000') THEN
    bad := bad||'el uid de control 00000000-0000-4372-8000-000000000000 existe en auth.users; ';
  END IF;
  v := (SELECT count(*)||':'||string_agg(il.es_paciente::text||'/'||il.es_profesional::text, ',') FROM private.identidad_legal('00000000-0000-4372-8000-000000000000') il);
  IF v IS DISTINCT FROM '1:false/false' THEN bad := bad||'identidad_legal(uid inexistente) '||COALESCE(v, '-')||'; '; END IF;

  -- (f) ejercicio: sin sesion las 2 RPCs dan LG001 con el mensaje nuevo; TRUNCATE da LG005
  st := NULL; msg := NULL;
  BEGIN PERFORM * FROM public.textos_legales_pendientes(); st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; msg := SQLERRM; END;
  IF st IS DISTINCT FROM 'LG001' OR msg IS DISTINCT FROM 'Necesitas iniciar sesión para consultar los textos legales.' THEN
    bad := bad||'textos_legales_pendientes() sin sesion: '||COALESCE(st, '-')||' '||COALESCE(msg, '-')||'; ';
  END IF;
  st := NULL; msg := NULL;
  BEGIN PERFORM public.aceptar_textos_legales('[{"codigo":"terminos","version":"0.1"}]'::jsonb, 'login', NULL); st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; msg := SQLERRM; END;
  IF st IS DISTINCT FROM 'LG001' OR msg IS DISTINCT FROM 'Necesitas iniciar sesión para aceptar los textos legales.' THEN
    bad := bad||'aceptar_textos_legales sin sesion: '||COALESCE(st, '-')||' '||COALESCE(msg, '-')||'; ';
  END IF;
  st := NULL;
  BEGIN TRUNCATE public.aceptaciones_legales; st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; END;
  IF st IS DISTINCT FROM 'LG005' THEN bad := bad||'TRUNCATE aceptaciones_legales: '||COALESCE(st, '-')||' (esperado LG005); '; END IF;

  -- (g) censo global: 0 funciones con PUBLIC; anon ejecuta solo catalogo_planes_visitador_publico
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- (h) huella de funciones SIN las 2 nuevas = la post-371 (nada de lo existente cambio de ACL)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND p.oid NOT IN ('private.identidad_legal(uuid)'::regprocedure, 'private.aceptaciones_legales_fija_fecha()'::regprocedure)) y);
  IF v IS DISTINCT FROM '4c1f611c29b8b37d8076536d065069e0 389' THEN bad := bad||'ACL de funciones previas '||COALESCE(v, '-')||'; '; END IF;

  -- (i) huellas post-372 completas (funciones CALCULADA el 8-oct-2026; policies y relaciones sin cambio; el dry-run
  --     las confirma)
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG372 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
