-- ############################################################################################
-- 371 - GL-02 textos legales: catalogo, aceptaciones append-only y RPCs (paso 1: base de datos)
-- ############################################################################################
-- Diseno: tmp/legal/diseno_gl02.md + "DECISIONES APROBADAS (Oscar, 7-oct-2026)" D-1..D-14.
-- Va DESPUES de la 370, por huella: la precondicion exige el estado post-370 (ACL de funciones 4878afd5.../384, 0 funciones
-- con PUBLIC, anon solo en catalogo_planes_visitador_publico). Al reves no: la precondicion de la 370 exige 384 funciones
-- y esta crea 5.
--
-- Objetos nuevos:
--   public.textos_legales          catalogo minimo (D-8): codigo, version vigente, aplica_a, exigible, md5 del .md. El
--                                  cuerpo del texto NO vive en la base (src/legal/*.md). Escritura solo por migracion.
--   public.aceptaciones_legales    append-only: usuario_id (= auth.uid() del llamante, nunca un parametro), codigo, version,
--                                  aceptado_at, via, user_agent (truncado a 300; sin IP, D-6). UNIQUE (usuario, codigo,
--                                  version): aceptar dos veces la misma version es idempotente.
--   private.aceptaciones_legales_solo_append()   trigger BEFORE UPDATE OR DELETE (fila) y BEFORE TRUNCATE (sentencia): LG005
--                                  para todos, incluido postgres (molde de las migs 246 y 334).
--   private.textos_legales_pendientes_de(uuid)   UNICA fuente de la regla por rol (aplica_a + identidad del uid).
--   private.textos_legales_al_dia(uuid)           boolean; NULL -> false. D-12: no se engancha a ninguna RPC de negocio.
--   public.textos_legales_pendientes()            RPC de lectura para el gate del front (D-1/D-11).
--   public.aceptar_textos_legales(jsonb, text, text)  RPC de escritura.
--
-- Regla por rol (aplica_a, evaluada en private.textos_legales_pendientes_de):
--   'todos'       -> todo autenticado: terminos + privacidad (internos incluidos, D-2).
--   'paciente'    -> EXISTS pacientes.auth_user_id = uid: + consentimiento_salud.
--   'profesional' -> perfiles.rol IN (medico, admin_clinica, gerente, secretaria, enfermeria, asistente_medico) o EXISTS
--                    cuentas_proveedor.id = uid (cualquier rol_en_empresa): + condiciones_profesionales.
--   Internos (super_admin, admin_pais, asesor_comercial, supervisor_comercial, soporte) y roles sin panel (cliente,
--   vendedor): solo 'todos'. Doble identidad: union. No se filtra por activo (ni perfil, ni paciente, ni cuenta): ante la
--   duda se exige de mas, no de menos.
--   Un texto con exigible = false no aparece como pendiente, pero se puede aceptar igual (version vigente).
--
-- Semilla (D-7): los 4 textos en version '0.1' y exigible = FALSE. Nada se exige hasta que Oscar complete los datos de la
-- seccion 5.1 de tmp/legal/textos_v0.1.md; entonces una migracion sube la version y prende exigible. md5 = md5 de los
-- bytes de tmp/legal/<texto>.md (UTF-8, LF) al 7-oct-2026; los src/legal/*.md del front tienen que ser identicos.
--
-- Errcodes (prefijo nuevo LG):
--   LG001 sin sesion (auth.uid() NULL) en las 2 RPCs. Sin sesion NO se devuelven 0 filas: 0 pendientes abre el gate.
--   LG002 codigo de texto inexistente.
--   LG003 la version enviada no es la vigente (el front: "el texto cambio, volve a leerlo").
--   LG004 entrada invalida: p_textos no es array, vacio o con mas de 10, elemento sin codigo/version de tipo string,
--         codigo repetido en la misma llamada, o p_via fuera de ('registro','login','app').
--   LG005 aceptaciones_legales es append-only (UPDATE, DELETE o TRUNCATE).
--   Proximo libre: LG006 (para "faltan aceptaciones" si un dia se gatea una RPC de negocio, D-12).
--
-- Privilegios (regla de GRANTs explicitos de CLAUDE.md; P800 (a)-(m), P928, P930, P931, P934):
--   tablas: authenticated solo SELECT (con policy: P930); service_role SELECT/INSERT/UPDATE/DELETE; anon y PUBLIC nada.
--   secuencia IDENTITY de aceptaciones_legales: sin nada para authenticated/anon/PUBLIC (el default de la 344 le daria
--     USAGE a authenticated y P928 (c) saldria ROJO; IDENTITY no necesita grant para el INSERT).
--   policies (TO authenticated, P934): textos_legales_select USING (true); aceptaciones_legales_select_propias
--     USING (usuario_id = auth.uid()). Ninguna llama funciones de public/private (P800 (l) sin cambio).
--   funciones: las 2 RPCs con EXECUTE para authenticated y service_role; las 3 de private solo postgres (regla 10).
--     Ninguna con PUBLIC ni anon (P800 (j)/(k)/(m) siguen pasando). Todas SECURITY DEFINER con search_path = '' (P931).
-- Huellas: policies 9ad61756.../307 -> 8a8dc5cfaf8365f95208fb9e8ba79674/309; ACL de relaciones de public 64ff833d.../2368
--   -> d065decfec14c0afae8f5d898032e4bb/2394; ACL de funciones 4878afd5.../384 -> 4c1f611c29b8b37d8076536d065069e0/389.
--   Las 3 post-371 estan CALCULADAS (consulta de solo lectura sobre prod el 7-oct-2026: filas vivas + filas sinteticas de
--   los objetos nuevos; la misma consulta reproduce exacto las post-370), NO medidas: el dry-run las confirma. Ademas, el
--   autochequeo exige que las huellas SIN los objetos nuevos sigan siendo las post-370 (nada viejo cambio).
-- Rollback: 371_rollback.sql (va ANTES que 370_rollback; aborta si hay aceptaciones registradas). Orden de deploy: esta
-- migracion ANTES que el front de GL-02 (el gate falla cerrado sin las RPCs, D-11).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-370)
DO $precondicion$
DECLARE bad text := ''; v text; n int;
BEGIN
  -- huellas (misma formula que la 370)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4878afd5e7fa74667b466d6994d565ff 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  -- censo de la 370: 0 funciones con PUBLIC; anon ejecuta solo catalogo_planes_visitador_publico
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC (esperado 0); '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- los objetos de la 371 no existen todavia
  IF to_regclass('public.textos_legales') IS NOT NULL THEN bad := bad||'public.textos_legales ya existe; '; END IF;
  IF to_regclass('public.aceptaciones_legales') IS NOT NULL THEN bad := bad||'public.aceptaciones_legales ya existe; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND p.proname IN ('aceptar_textos_legales', 'textos_legales_pendientes', 'textos_legales_pendientes_de',
                             'textos_legales_al_dia', 'aceptaciones_legales_solo_append'));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existen: '||v||'; '; END IF;

  -- columnas de identidad que usa la regla por rol
  n := (SELECT count(*) FROM pg_attribute a WHERE NOT a.attisdropped AND (
          (a.attrelid = 'public.pacientes'::regclass AND a.attname = 'auth_user_id' AND a.atttypid = 'uuid'::regtype)
       OR (a.attrelid = 'public.perfiles'::regclass AND a.attname = 'id' AND a.atttypid = 'uuid'::regtype)
       OR (a.attrelid = 'public.perfiles'::regclass AND a.attname = 'rol' AND a.atttypid = 'text'::regtype)
       OR (a.attrelid = 'public.cuentas_proveedor'::regclass AND a.attname = 'id' AND a.atttypid = 'uuid'::regtype)));
  IF n <> 4 THEN bad := bad||'columnas de identidad '||n||' (esperado 4); '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG371 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: catalogo
CREATE TABLE public.textos_legales (
  codigo    text    PRIMARY KEY CHECK (codigo ~ '^[a-z][a-z_]{0,39}$'),
  version   text    NOT NULL CHECK (version ~ '^[0-9]{1,3}\.[0-9]{1,3}$'),
  aplica_a  text[]  NOT NULL CHECK (cardinality(aplica_a) >= 1
                                    AND aplica_a <@ ARRAY['todos','paciente','profesional']::text[]
                                    AND array_position(aplica_a, NULL) IS NULL),
  exigible  boolean NOT NULL,
  md5       text    NOT NULL CHECK (md5 ~ '^[0-9a-f]{32}$')
);
COMMENT ON TABLE public.textos_legales IS
  'Mig 371 (GL-02). Catalogo minimo de textos legales: version vigente, a quien aplica (todos/paciente/profesional), si se exige y md5 del .md del repo. El cuerpo vive en src/legal/*.md. Escritura solo por migracion.';

ALTER TABLE public.textos_legales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.textos_legales FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.textos_legales TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.textos_legales TO service_role;

CREATE POLICY textos_legales_select ON public.textos_legales
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

INSERT INTO public.textos_legales (codigo, version, aplica_a, exigible, md5) VALUES
  ('terminos',                  '0.1', ARRAY['todos'],       false, '5eb1698ca0a0d9809c0b63482b41ff57'),
  ('privacidad',                '0.1', ARRAY['todos'],       false, 'd2a181910741a1994e9f2487907b7f9e'),
  ('consentimiento_salud',      '0.1', ARRAY['paciente'],    false, '41d9e576b5e5157f030bbfc577f45e66'),
  ('condiciones_profesionales', '0.1', ARRAY['profesional'], false, 'c716f13e1fd19225dfac4b7ac248a456');

-- ---------------------------------------------------------------------------- 2: aceptaciones (append-only)
CREATE TABLE public.aceptaciones_legales (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id  uuid        NOT NULL,
  codigo      text        NOT NULL REFERENCES public.textos_legales (codigo) ON UPDATE RESTRICT ON DELETE RESTRICT,
  version     text        NOT NULL CHECK (version ~ '^[0-9]{1,3}\.[0-9]{1,3}$'),
  aceptado_at timestamptz NOT NULL DEFAULT now(),
  via         text        NOT NULL CHECK (via IN ('registro','login','app')),
  user_agent  text        CHECK (user_agent IS NULL OR char_length(user_agent) <= 300),
  CONSTRAINT aceptaciones_legales_usuario_texto_version_key UNIQUE (usuario_id, codigo, version)
);
COMMENT ON TABLE public.aceptaciones_legales IS
  'Mig 371 (GL-02). Append-only: una fila por usuario/texto/version aceptada. Se escribe solo por aceptar_textos_legales (usuario_id = auth.uid()). UPDATE/DELETE/TRUNCATE dan LG005 para todos. Sin IP.';

ALTER TABLE public.aceptaciones_legales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.aceptaciones_legales FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.aceptaciones_legales TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.aceptaciones_legales TO service_role;

-- la secuencia IDENTITY: nada para authenticated/anon/PUBLIC (P928; el INSERT por IDENTITY no chequea privilegios)
DO $secuencia$
DECLARE v_seq text := pg_get_serial_sequence('public.aceptaciones_legales', 'id');
BEGIN
  IF v_seq IS NULL THEN RAISE EXCEPTION 'MIG371: aceptaciones_legales.id sin secuencia IDENTITY'; END IF;
  EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated', v_seq);
END $secuencia$;

CREATE POLICY aceptaciones_legales_select_propias ON public.aceptaciones_legales
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (usuario_id = auth.uid());

CREATE FUNCTION private.aceptaciones_legales_solo_append()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Las aceptaciones legales son inmutables (intento de %)', TG_OP USING ERRCODE = 'LG005';
END
$function$;
COMMENT ON FUNCTION private.aceptaciones_legales_solo_append() IS
  'Mig 371. BEFORE UPDATE OR DELETE (fila) y BEFORE TRUNCATE (sentencia) de aceptaciones_legales: LG005 para todos.';
REVOKE ALL ON FUNCTION private.aceptaciones_legales_solo_append() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_aceptaciones_legales_solo_append
  BEFORE UPDATE OR DELETE ON public.aceptaciones_legales
  FOR EACH ROW EXECUTE FUNCTION private.aceptaciones_legales_solo_append();
-- TRUNCATE no dispara triggers de fila: este cierra esa puerta (molde de la 246).
CREATE TRIGGER trg_aceptaciones_legales_no_truncate
  BEFORE TRUNCATE ON public.aceptaciones_legales
  FOR EACH STATEMENT EXECUTE FUNCTION private.aceptaciones_legales_solo_append();

-- ---------------------------------------------------------------------------- 3: la regla por rol (una sola fuente)
CREATE FUNCTION private.textos_legales_pendientes_de(p_uid uuid)
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

CREATE FUNCTION private.textos_legales_al_dia(p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT p_uid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.textos_legales_pendientes_de(p_uid));
$function$;
COMMENT ON FUNCTION private.textos_legales_al_dia(uuid) IS
  'Mig 371. true si el uid no tiene textos legales pendientes; uid NULL -> false. No lo usa ninguna RPC todavia (D-12). EXECUTE solo postgres: si una policy o RPC de authenticated lo llama, su migracion lleva el GRANT (regla 10).';
REVOKE ALL ON FUNCTION private.textos_legales_al_dia(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- 4: RPC de lectura
CREATE FUNCTION public.textos_legales_pendientes()
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

-- ---------------------------------------------------------------------------- 5: RPC de escritura
CREATE FUNCTION public.aceptar_textos_legales(p_textos jsonb, p_via text DEFAULT 'login', p_user_agent text DEFAULT NULL)
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

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; n int; r record; st text;
BEGIN
  -- (a) tablas: RLS on (sin FORCE: las RPCs DEFINER escriben como postgres), constraints
  FOR r IN SELECT x.t FROM (VALUES ('public.textos_legales'), ('public.aceptaciones_legales')) x(t) LOOP
    IF to_regclass(r.t) IS NULL THEN bad := bad||r.t||' no existe; '; CONTINUE; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = to_regclass(r.t) AND relrowsecurity AND NOT relforcerowsecurity) THEN
      bad := bad||r.t||' sin RLS (o con FORCE); ';
    END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG371 AUTOCHEQUEO FALLA:%', bad; END IF;
  v := (SELECT string_agg(conname||':'||contype::text, ',' ORDER BY conname COLLATE "C") FROM pg_constraint
         WHERE conrelid IN ('public.textos_legales'::regclass, 'public.aceptaciones_legales'::regclass) AND contype IN ('c','u','p','f'));
  IF v IS DISTINCT FROM 'aceptaciones_legales_codigo_fkey:f,aceptaciones_legales_pkey:p,aceptaciones_legales_user_agent_check:c,'
                      ||'aceptaciones_legales_usuario_texto_version_key:u,aceptaciones_legales_version_check:c,aceptaciones_legales_via_check:c,'
                      ||'textos_legales_aplica_a_check:c,textos_legales_codigo_check:c,textos_legales_md5_check:c,textos_legales_pkey:p,'
                      ||'textos_legales_version_check:c' THEN
    bad := bad||'constraints '||COALESCE(v, '-')||'; ';
  END IF;

  -- (b) ACL exacta de las tablas (sin el dueno) y privilegio efectivo
  v := (SELECT string_agg(g, ',' ORDER BY g COLLATE "C") FROM (
          SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type||':'||pg_get_userbyid(a.grantor)||':'||a.is_grantable::text AS g
            FROM pg_class c, aclexplode(c.relacl) a WHERE c.oid = 'public.textos_legales'::regclass AND a.grantee <> c.relowner) z);
  IF v IS DISTINCT FROM 'authenticated:SELECT:postgres:false,service_role:DELETE:postgres:false,service_role:INSERT:postgres:false,service_role:SELECT:postgres:false,service_role:UPDATE:postgres:false' THEN
    bad := bad||'ACL textos_legales '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(g, ',' ORDER BY g COLLATE "C") FROM (
          SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type||':'||pg_get_userbyid(a.grantor)||':'||a.is_grantable::text AS g
            FROM pg_class c, aclexplode(c.relacl) a WHERE c.oid = 'public.aceptaciones_legales'::regclass AND a.grantee <> c.relowner) z);
  IF v IS DISTINCT FROM 'authenticated:SELECT:postgres:false,service_role:DELETE:postgres:false,service_role:INSERT:postgres:false,service_role:SELECT:postgres:false,service_role:UPDATE:postgres:false' THEN
    bad := bad||'ACL aceptaciones_legales '||COALESCE(v, '-')||'; ';
  END IF;
  FOR r IN SELECT x.t FROM (VALUES ('public.textos_legales'), ('public.aceptaciones_legales')) x(t) LOOP
    IF has_table_privilege('anon', r.t, 'SELECT') OR has_table_privilege('anon', r.t, 'INSERT')
       OR has_table_privilege('authenticated', r.t, 'INSERT') OR has_table_privilege('authenticated', r.t, 'UPDATE')
       OR has_table_privilege('authenticated', r.t, 'DELETE') OR has_table_privilege('authenticated', r.t, 'TRUNCATE')
       OR has_table_privilege('authenticated', r.t, 'REFERENCES') OR has_table_privilege('authenticated', r.t, 'TRIGGER')
       OR has_table_privilege('authenticated', r.t, 'MAINTAIN')
       OR NOT has_table_privilege('authenticated', r.t, 'SELECT') THEN
      bad := bad||r.t||': privilegio efectivo de anon/authenticated distinto de lo esperado; ';
    END IF;
  END LOOP;
  -- privilegios por columna: ninguno
  n := (SELECT count(*) FROM pg_attribute a WHERE a.attrelid IN ('public.textos_legales'::regclass, 'public.aceptaciones_legales'::regclass) AND a.attacl IS NOT NULL);
  IF n <> 0 THEN bad := bad||n||' columnas con ACL propia; '; END IF;

  -- (c) secuencia IDENTITY: nada para authenticated/anon/PUBLIC (explicito y efectivo)
  v := pg_get_serial_sequence('public.aceptaciones_legales', 'id');
  IF v IS NULL THEN
    bad := bad||'aceptaciones_legales.id sin secuencia; ';
  ELSIF EXISTS (SELECT 1 FROM aclexplode(COALESCE((SELECT relacl FROM pg_class WHERE oid = v::regclass), acldefault('s', 'postgres'::regrole))) a
                 WHERE a.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole))
     OR has_sequence_privilege('authenticated', v, 'USAGE') OR has_sequence_privilege('authenticated', v, 'SELECT')
     OR has_sequence_privilege('authenticated', v, 'UPDATE') OR has_sequence_privilege('anon', v, 'USAGE') THEN
    bad := bad||'secuencia '||v||' con privilegios para authenticated/anon/PUBLIC; ';
  END IF;

  -- (d) policies exactas de las 2 tablas
  v := (SELECT string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                 ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                 COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'),
                 E'\n' ORDER BY c.relname, pl.polname)
          FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.textos_legales'::regclass, 'public.aceptaciones_legales'::regclass));
  IF v IS DISTINCT FROM 'aceptaciones_legales|aceptaciones_legales_select_propias|r|true|{authenticated}|(usuario_id = auth.uid())|-'
                      ||E'\n'||'textos_legales|textos_legales_select|r|true|{authenticated}|true|-' THEN
    bad := bad||'policies '||COALESCE(v, '-')||'; ';
  END IF;

  -- (e) triggers de inmutabilidad
  v := (SELECT string_agg(t.tgname||':'||t.tgtype::text||':'||t.tgenabled::text||':'||t.tgfoid::regprocedure::text, ',' ORDER BY t.tgname)
          FROM pg_trigger t WHERE t.tgrelid = 'public.aceptaciones_legales'::regclass AND NOT t.tgisinternal);
  -- tgtype: 27 = ROW|BEFORE|DELETE|UPDATE; 34 = BEFORE|TRUNCATE (sentencia)
  IF v IS DISTINCT FROM 'trg_aceptaciones_legales_no_truncate:34:O:private.aceptaciones_legales_solo_append(),'
                      ||'trg_aceptaciones_legales_solo_append:27:O:private.aceptaciones_legales_solo_append()' THEN
    bad := bad||'triggers '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.textos_legales'::regclass AND NOT t.tgisinternal) THEN
    bad := bad||'textos_legales con triggers; ';
  END IF;

  -- (f) funciones nuevas: DEFINER, search_path = '', ACL exacta
  FOR r IN SELECT x.f, x.acl FROM (VALUES
      ('public.aceptar_textos_legales(jsonb,text,text)',     'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE'),
      ('public.textos_legales_pendientes()',                 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE'),
      ('private.textos_legales_pendientes_de(uuid)',         'postgres:EXECUTE'),
      ('private.textos_legales_al_dia(uuid)',                'postgres:EXECUTE'),
      ('private.aceptaciones_legales_solo_append()',         'postgres:EXECUTE')) x(f, acl) LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; CONTINUE; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND p.prosecdef
                     AND p.proconfig = ARRAY['search_path=""'] AND p.proowner = 'postgres'::regrole) THEN
      bad := bad||r.f||' no es DEFINER con search_path vacio y dueno postgres; ';
    END IF;
    v := (SELECT string_agg(z.g, ',' ORDER BY z.g COLLATE "C") FROM (
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type AS g
              FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE p.oid = to_regprocedure(r.f)) z);
    IF v IS DISTINCT FROM r.acl THEN bad := bad||r.f||' ACL '||COALESCE(v, '-')||' (esperado '||r.acl||'); '; END IF;
  END LOOP;

  -- (g) censo global: 0 funciones con PUBLIC; anon ejecuta solo catalogo_planes_visitador_publico
  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- (h) semilla: 4 textos, version 0.1, exigible = false (D-7); 0 aceptaciones
  v := (SELECT string_agg(codigo||'|'||version||'|'||aplica_a::text||'|'||exigible::text||'|'||md5, E'\n' ORDER BY codigo COLLATE "C")
          FROM public.textos_legales);
  IF v IS DISTINCT FROM 'condiciones_profesionales|0.1|{profesional}|false|c716f13e1fd19225dfac4b7ac248a456'||E'\n'
                      ||'consentimiento_salud|0.1|{paciente}|false|41d9e576b5e5157f030bbfc577f45e66'||E'\n'
                      ||'privacidad|0.1|{todos}|false|d2a181910741a1994e9f2487907b7f9e'||E'\n'
                      ||'terminos|0.1|{todos}|false|5eb1698ca0a0d9809c0b63482b41ff57' THEN
    bad := bad||'semilla '||COALESCE(v, '-')||'; ';
  END IF;
  n := (SELECT count(*) FROM public.aceptaciones_legales);
  IF n <> 0 THEN bad := bad||n||' aceptaciones (esperado 0); '; END IF;

  -- (i) ejercicio: sin sesion las 2 RPCs dan LG001; TRUNCATE da LG005 (la tabla esta vacia: los triggers de fila no
  --     se pueden ejercitar aca, los cubre el probe)
  st := NULL;
  BEGIN PERFORM * FROM public.textos_legales_pendientes(); st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; END;
  IF st IS DISTINCT FROM 'LG001' THEN bad := bad||'textos_legales_pendientes() sin sesion: '||COALESCE(st, '-')||' (esperado LG001); '; END IF;
  st := NULL;
  BEGIN PERFORM public.aceptar_textos_legales('[{"codigo":"terminos","version":"0.1"}]'::jsonb, 'login', NULL); st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; END;
  IF st IS DISTINCT FROM 'LG001' THEN bad := bad||'aceptar_textos_legales sin sesion: '||COALESCE(st, '-')||' (esperado LG001); '; END IF;
  st := NULL;
  BEGIN TRUNCATE public.aceptaciones_legales; st := 'sin error';
  EXCEPTION WHEN OTHERS THEN st := SQLSTATE; END;
  IF st IS DISTINCT FROM 'LG005' THEN bad := bad||'TRUNCATE aceptaciones_legales: '||COALESCE(st, '-')||' (esperado LG005); '; END IF;
  IF private.textos_legales_al_dia(NULL) IS DISTINCT FROM false THEN bad := bad||'textos_legales_al_dia(NULL) no es false; '; END IF;

  -- (j) huellas SIN los objetos nuevos = las post-370 (nada de lo existente cambio)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')
         AND pl.polrelid NOT IN ('public.textos_legales'::regclass, 'public.aceptaciones_legales'::regclass)) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies previas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')
       AND c.oid NOT IN ('public.textos_legales'::regclass, 'public.aceptaciones_legales'::regclass)) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones previas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND p.oid NOT IN ('public.aceptar_textos_legales(jsonb,text,text)'::regprocedure, 'public.textos_legales_pendientes()'::regprocedure,
                           'private.textos_legales_pendientes_de(uuid)'::regprocedure, 'private.textos_legales_al_dia(uuid)'::regprocedure,
                           'private.aceptaciones_legales_solo_append()'::regprocedure)) y);
  IF v IS DISTINCT FROM '4878afd5e7fa74667b466d6994d565ff 384' THEN bad := bad||'ACL de funciones previas '||COALESCE(v, '-')||'; '; END IF;

  -- (k) huellas post-371 completas (calculadas el 7-oct-2026; el dry-run las confirma)
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG371 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
