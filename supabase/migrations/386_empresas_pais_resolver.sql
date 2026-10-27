-- =====================================================================================================================
-- MIG 386 — Familia B: el admin de país ve y resuelve (aprueba / rechaza con motivo) las empresas proveedoras de SU país.
-- Diseño: output/diseno-familia-b-27oct.md (27-oct-2026), decisiones D1-D11 aprobadas tal como recomienda la sección (g).
--
-- Por qué: empresas_proveedoras tiene 2 policies de SELECT (super_admin y "la propia empresa") y ninguna para admin_pais:
-- el admin de país ve 0 filas (sin 42501: el grant de tabla existe) mientras contar_proveedores_por_pais (DEFINER) le
-- cuenta 8. Aprobar hoy es un UPDATE directo que solo pasa el super_admin; 'rechazada' existe en el CHECK pero nadie la
-- escribe y no hay dónde guardar el motivo. NO se amplían policies ni grants de tabla: todo va por 2 RPCs DEFINER.
--
-- Qué hace:
--   a) columnas nuevas en empresas_proveedoras (nullable): motivo_rechazo text, revisado_por uuid (FK -> perfiles ON
--      DELETE RESTRICT: quien resolvió es un perfil de admin; borrar ese perfil con revisiones a su nombre debe fallar,
--      no dejar la revisión huérfana ni anónima), revisado_at timestamptz;
--      CHECK empresas_proveedoras_motivo_rechazo_chk: 'rechazada' exige motivo con algún carácter que no sea espacio, y
--      el motivo no pasa de 500 caracteres. La precondición exige 0 filas 'rechazada' (hoy: 0).
--   b) private.empresas_proveedoras_guard_update (CREATE OR REPLACE, misma firma, INVOKER, search_path='', ACL igual):
--      - lo de hoy, INTACTO y en el mismo orden: estado/tipo/pais_id/planes solo los cambia un exento (service_role,
--        postgres, supabase_admin, supabase_auth_admin o super_admin). La exención del super_admin para estado la
--        retira la 387;
--      - NUEVO: motivo_rechazo / revisado_por / revisado_at solo se escriben con el GUC de transacción
--        app.resolver_empresa_rpc = 'on' Y current_user = 'postgres' (o sea: desde resolver_empresa, que es DEFINER
--        de postgres). Vale para INSERT y UPDATE y para todos, super_admin incluido. Mismo patrón que
--        app.personalizacion_rpc (trg_guard_tema_columns), más el chequeo de current_user;
--      - NUEVO: la transición pendiente -> activa|rechazada exige el GUC o ser exento. Hoy es redundante con la regla
--        anterior (todo cambio de estado de un no exento ya da 42501); queda para cuando la 387 saque al super_admin
--        de los exentos.
--   c) public.listar_empresas_pais(p_pais_id, p_estado DEFAULT NULL): bandeja por país (super_admin o admin_pais de
--      ESE país; p_pais_id NULL -> EP005 para todos, D6). Devuelve id, nombre_empresa, tipo, estado, pais_id,
--      email_contacto, telefono (D8), created_at, motivo_rechazo, revisado_at y tiene_plan_activo (D5: alguna fila de
--      empresa_capacidades activa y vigente, el mismo criterio que mis_capacidades; no otorga nada).
--   d) public.resolver_empresa(p_empresa_id, p_accion, p_motivo DEFAULT NULL): 'aprobar' | 'rechazar' (D2: nada de
--      suspender/reactivar), solo desde 'pendiente', gate por el país de la empresa ANTES de revelar si existe (el mismo
--      error para "no existe" y "no es tu país"), FOR UPDATE, motivo normalizado (bordes con espacios/tabs/saltos) y
--      obligatorio al rechazar; escribe estado + motivo_rechazo (NULL al aprobar) + revisado_por = auth.uid() +
--      revisado_at = now() + updated_at. Aviso a la empresa: public.notificar_empresa_estado (in-app, contenido
--      server-side, sin el motivo, accion_url interna '/proveedor/dashboard') y private.push_notificar por cada aviso
--      creado (D4: el push lleva el aviso, nunca el motivo). El aviso va en un sub-bloque con EXCEPTION (patrón 383):
--      si falla, la resolución queda hecha y la RPC devuelve notificado = false. Sin correo (D10).
--   e) ACL: las 2 RPCs con EXECUTE para authenticated y service_role (default privileges de la 344); se revoca PUBLIC y
--      anon. Sin grants nuevos de tabla.
--
-- Errores (mensajes para el usuario final, en tú, sin eco de datos):
--   EP001  no hay sesión
--   EP002  la empresa no existe o no puedes gestionarla / no puedes ver las empresas de ese país (mismo error)
--   EP003  la empresa ya no está pendiente (ya fue resuelta)
--   EP004  motivo de rechazo inválido: vacío o de más de 500 caracteres
--   EP005  dato inválido: acción desconocida, estado de filtro desconocido o país sin indicar
--   MIG86  guarda de esta migración
--
-- Huellas medidas el 27-oct-2026 19:11:18 UTC (estado post-385):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ cb4ab540ceea52520740a6e03133522e 411
--   funciones completas SIN listar_empresas_pais, resolver_empresa y el guard ........ f0a72054b27c11410c469b59336f46ac 410
--   ACL de funciones (solo privilegios), public/private ............................. af6b7bf22f370f6ee5ff89ff59eb0ea5 411
--   ACL de relaciones de public ...................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage .................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Después:
--   - funciones completas: se mueve SOLO por las 2 nuevas y el guard (sin esas 3 sigue en f0a72054…/410; el total pasa
--     a 413); notificar_empresa_estado no cambia;
--   - ACL de funciones: cambia por las 2 nuevas (sin ellas sigue en af6b7bf2…/411; el total pasa a 413);
--   - ACL de relaciones de public: IDÉNTICA (9b8f5af8…/2445). La huella mira pg_class.relacl, y ADD COLUMN no toca la
--     ACL de la tabla ni crea ACL por columna; las constraints nuevas tampoco entran;
--   - policies: IDÉNTICAS (no se agrega ninguna).
-- Ojo (anon): la tabla tiene SELECT de tabla para anon (legado, WL_ANON_LEGACY), que por privilegio cubre también las
-- columnas nuevas. No hay policy para anon, así que anon lee 0 filas. Cerrar el privilegio es el REVOKE de anon de la
-- familia 2 (backlog), fuera de esta migración. anon no tiene UPDATE.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/386_empresas_pais_resolver.sql
-- Rollback: supabase/migrations/386_rollback.sql (cadena: 386_rollback -> 385_rollback -> 384_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 386 no está aplicada
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('listar_empresas_pais', 'resolver_empresa')) THEN
    bad := bad||'listar_empresas_pais o resolver_empresa ya existen (386 aplicada); ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass
               AND a.attname IN ('motivo_rechazo', 'revisado_por', 'revisado_at') AND NOT a.attisdropped) THEN
    bad := bad||'empresas_proveedoras ya tiene columnas de revisión (386 aplicada); ';
  END IF;
  -- la 385 aplicada
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)'))
     IS DISTINCT FROM 'ed19aae358ba091ef9e82ed18451615b' THEN
    bad := bad||'la 385 no está aplicada (registrar_clinica_desde_invitacion no es la v2); ';
  END IF;
  -- las funciones de las que depende, rotuladas (md5(prosrc) + SECURITY DEFINER + config + ACL)
  FOR r IN SELECT * FROM (VALUES
      ('private.empresas_proveedoras_guard_update()', '9737a58927e36a2355b592fd1861f8a5', false, '{postgres=X/postgres}'),
      ('public.notificar_empresa_estado(uuid)', '72cf7417810b164753223c49d88dc8c4', true, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.puede_admin_pais(uuid,text[])', '8bc2928e369d98e305355440df8b52ac', true, '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.push_notificar(text,text)', '90e6e8ec7eb37240e400a7c5768a8997', true, '{postgres=X/postgres}')) AS t(firma, md5_vivo, secdef, acl)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo||' '||r.secdef::text||' {"search_path=\"\""} '||r.acl THEN
      bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); ';
    END IF;
  END LOOP;
  -- el trigger del guard sigue enganchado igual
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.empresas_proveedoras'::regclass
                   AND t.tgname = 'empresas_proveedoras_guard_update'
                   AND t.tgfoid = to_regprocedure('private.empresas_proveedoras_guard_update()') AND NOT t.tgisinternal) THEN
    bad := bad||'trigger empresas_proveedoras_guard_update no enganchado al guard; ';
  END IF;
  -- tabla: ACL, estados del CHECK, sin filas 'rechazada' (el CHECK nuevo les exigiría motivo)
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=rw/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de empresas_proveedoras distinta de la medida; ';
  END IF;
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname = 'empresas_proveedoras_estado_chk'
        AND c.conrelid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM $c$CHECK ((estado = ANY (ARRAY['pendiente'::text, 'activa'::text, 'suspendida'::text, 'rechazada'::text])))$c$ THEN
    bad := bad||'CHECK de estado distinto del medido; ';
  END IF;
  IF EXISTS (SELECT 1 FROM public.empresas_proveedoras e WHERE e.estado = 'rechazada') THEN
    bad := bad||'hay empresas rechazadas sin motivo: el CHECK nuevo no se puede crear; ';
  END IF;
  IF to_regclass('public.empresa_capacidades') IS NULL THEN bad := bad||'falta empresa_capacidades; '; END IF;
  -- EP001-EP005 no están en uso en ninguna función
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.prosrc ~ 'EP00[1-5]') THEN bad := bad||'EP001-EP005 ya están en uso; '; END IF;

  -- huellas (27-oct-2026 19:11:18 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'cb4ab540ceea52520740a6e03133522e 411' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG86: precondición: %', bad USING ERRCODE = 'MIG86';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) COLUMNAS DE REVISIÓN + CHECK
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.empresas_proveedoras
  ADD COLUMN motivo_rechazo text,
  ADD COLUMN revisado_por uuid,
  ADD COLUMN revisado_at timestamptz,
  ADD CONSTRAINT empresas_proveedoras_revisado_por_fkey
    FOREIGN KEY (revisado_por) REFERENCES public.perfiles (id) ON DELETE RESTRICT,
  ADD CONSTRAINT empresas_proveedoras_motivo_rechazo_chk
    CHECK ((estado <> 'rechazada' OR (motivo_rechazo IS NOT NULL AND motivo_rechazo ~ '[^[:space:]]'))
           AND (motivo_rechazo IS NULL OR char_length(motivo_rechazo) <= 500));

-- ---------------------------------------------------------------------------------------------------------------------
-- b) GUARD: las columnas de revisión y la transición pendiente -> activa|rechazada pasan por resolver_empresa
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.empresas_proveedoras_guard_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = ''
AS $fn$
DECLARE v_exento boolean; v_rpc boolean;
BEGIN
  v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
              OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false);
  -- mig 386: el camino de resolver_empresa (DEFINER de postgres que pone el GUC de transacción)
  v_rpc := current_user = 'postgres'
           AND COALESCE(pg_catalog.current_setting('app.resolver_empresa_rpc', true), '') = 'on';

  IF TG_OP = 'INSERT' THEN
    IF NOT v_exento AND NEW.estado IS DISTINCT FROM 'pendiente' THEN
      NEW.estado := 'pendiente';   -- toda empresa creada por un no-privilegiado nace pendiente
    END IF;
    -- mig 386: una empresa no nace revisada
    IF NOT v_rpc AND (NEW.motivo_rechazo IS NOT NULL OR NEW.revisado_por IS NOT NULL OR NEW.revisado_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF ( NEW.estado                     IS DISTINCT FROM OLD.estado
    OR NEW.tipo                       IS DISTINCT FROM OLD.tipo
    OR NEW.pais_id                    IS DISTINCT FROM OLD.pais_id
    OR NEW.dias_ventaja_reserva       IS DISTINCT FROM OLD.dias_ventaja_reserva
    OR NEW.ventana_prioridad_visitas  IS DISTINCT FROM OLD.ventana_prioridad_visitas )
  THEN
    IF NOT v_exento THEN
      RAISE EXCEPTION 'No autorizado a modificar estado/tipo/pais/plan de la empresa'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- mig 386: columnas de revisión, solo por resolver_empresa (para todos, super_admin incluido)
  IF ( NEW.motivo_rechazo IS DISTINCT FROM OLD.motivo_rechazo
    OR NEW.revisado_por   IS DISTINCT FROM OLD.revisado_por
    OR NEW.revisado_at    IS DISTINCT FROM OLD.revisado_at )
     AND NOT v_rpc THEN
    RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
      USING ERRCODE = '42501';
  END IF;

  -- mig 386: pendiente -> activa|rechazada por resolver_empresa o, hasta la 387, por un exento
  IF OLD.estado = 'pendiente' AND NEW.estado IN ('activa', 'rechazada') AND NOT (v_rpc OR v_exento) THEN
    RAISE EXCEPTION 'No autorizado a resolver la empresa'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) listar_empresas_pais
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.listar_empresas_pais(p_pais_id uuid, p_estado text DEFAULT NULL)
 RETURNS TABLE (id uuid, nombre_empresa text, tipo text, estado text, pais_id uuid, email_contacto text, telefono text,
                created_at timestamptz, motivo_rechazo text, revisado_at timestamptz, tiene_plan_activo boolean)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Tu sesión no está activa. Vuelve a iniciar sesión.' USING ERRCODE = 'EP001';
  END IF;
  IF p_pais_id IS NULL THEN
    RAISE EXCEPTION 'Elige un país para ver sus empresas.' USING ERRCODE = 'EP005';
  END IF;
  IF p_estado IS NOT NULL AND p_estado NOT IN ('pendiente', 'activa', 'suspendida', 'rechazada') THEN
    RAISE EXCEPTION 'El filtro de estado no es válido.' USING ERRCODE = 'EP005';
  END IF;
  -- super_admin, o admin_pais de ESE país (COALESCE: fail-closed)
  IF NOT COALESCE(private.puede_admin_pais(p_pais_id, ARRAY['super_admin'::text]), false) THEN
    RAISE EXCEPTION 'No puedes ver las empresas de este país.' USING ERRCODE = 'EP002';
  END IF;

  RETURN QUERY
  SELECT e.id, e.nombre_empresa, e.tipo, e.estado, e.pais_id, e.email_contacto, e.telefono, e.created_at,
         e.motivo_rechazo, e.revisado_at,
         EXISTS (SELECT 1 FROM public.empresa_capacidades ec
                  WHERE ec.empresa_id = e.id AND ec.activa = true AND (ec.hasta IS NULL OR ec.hasta > now()))
    FROM public.empresas_proveedoras e
   WHERE e.pais_id = p_pais_id
     AND (p_estado IS NULL OR e.estado = p_estado)
   ORDER BY e.created_at DESC, e.id;
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- d) resolver_empresa
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.resolver_empresa(p_empresa_id uuid, p_accion text, p_motivo text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_accion text := lower(btrim(COALESCE(p_accion, '')));
  v_motivo text;
  v_estado text;
  v_pais uuid;
  v_nuevo text;
  v_notificado boolean := false;
  r record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Tu sesión no está activa. Vuelve a iniciar sesión.' USING ERRCODE = 'EP001';
  END IF;
  IF v_accion NOT IN ('aprobar', 'rechazar') THEN
    RAISE EXCEPTION 'La acción no es válida.' USING ERRCODE = 'EP005';
  END IF;
  -- el motivo se valida antes de tocar filas (no revela nada de la empresa); al aprobar se ignora
  IF v_accion = 'rechazar' THEN
    v_motivo := regexp_replace(COALESCE(p_motivo, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
    IF v_motivo = '' OR char_length(v_motivo) > 500 THEN
      RAISE EXCEPTION 'Escribe el motivo del rechazo (hasta 500 caracteres).' USING ERRCODE = 'EP004';
    END IF;
  END IF;

  -- gate por el país de la empresa ANTES de revelar si existe: el mismo error para "no existe" y "no es tu país"
  SELECT e.estado, e.pais_id INTO v_estado, v_pais
    FROM public.empresas_proveedoras e
   WHERE e.id = p_empresa_id
     FOR UPDATE;
  IF NOT FOUND OR NOT COALESCE(private.puede_admin_pais(v_pais, ARRAY['super_admin'::text]), false) THEN
    RAISE EXCEPTION 'La empresa no existe o no puedes gestionarla.' USING ERRCODE = 'EP002';
  END IF;
  IF v_estado IS DISTINCT FROM 'pendiente' THEN
    RAISE EXCEPTION 'Esta empresa ya fue revisada.' USING ERRCODE = 'EP003';
  END IF;

  v_nuevo := CASE v_accion WHEN 'aprobar' THEN 'activa' ELSE 'rechazada' END;

  PERFORM pg_catalog.set_config('app.resolver_empresa_rpc', 'on', true);
  UPDATE public.empresas_proveedoras e
     SET estado = v_nuevo,
         motivo_rechazo = CASE WHEN v_nuevo = 'rechazada' THEN v_motivo END,
         revisado_por = v_uid,
         revisado_at = now(),
         updated_at = now()
   WHERE e.id = p_empresa_id;
  PERFORM pg_catalog.set_config('app.resolver_empresa_rpc', 'off', true);

  -- aviso a la empresa: in-app por notificar_empresa_estado (lee el estado de la base; sin motivo) + push de cada aviso
  -- creado en esta transacción. Best-effort: si algo falla, la resolución queda hecha y notificado = false.
  BEGIN
    PERFORM public.notificar_empresa_estado(p_empresa_id);
    FOR r IN
      SELECT n.id FROM public.notificaciones n
       WHERE n.tipo = 'empresa' AND n.created_at = now()
         AND n.usuario_id IN (SELECT cp.id FROM public.cuentas_proveedor cp
                               WHERE cp.empresa_id = p_empresa_id AND cp.activo = true)
    LOOP
      PERFORM private.push_notificar('notificaciones', r.id::text);
    END LOOP;
    v_notificado := true;
  EXCEPTION WHEN OTHERS THEN
    v_notificado := false;
  END;

  RETURN jsonb_build_object('empresa_id', p_empresa_id, 'estado', v_nuevo, 'notificado', v_notificado);
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- e) ACL de las 2 RPCs (sin grants nuevos de tabla)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.listar_empresas_pais(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolver_empresa(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_empresas_pais(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolver_empresa(uuid, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- f) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- las 2 RPCs: 1 sobrecarga, DEFINER, search_path vacío, ACL exacta, md5
  FOR r IN SELECT * FROM (VALUES
      ('listar_empresas_pais', 'public.listar_empresas_pais(uuid,text)', 'f554317d0b1b0976df9cca289b092ca4'),
      ('resolver_empresa', 'public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24')) AS t(nombre, firma, md5_esperado)
  LOOP
    IF (SELECT count(*) FROM pg_proc p WHERE p.proname = r.nombre) <> 1 THEN bad := bad||r.nombre||': sobrecargas <> 1; '; END IF;
    IF to_regprocedure(r.firma) IS NULL THEN
      bad := bad||r.firma||' no existe; ';
      CONTINUE;
    END IF;
    v := (SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM 'true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} '||r.md5_esperado THEN
      bad := bad||r.firma||' '||COALESCE(v, '-')||'; ';
    END IF;
    IF has_function_privilege('anon', r.firma, 'EXECUTE') THEN bad := bad||r.firma||' anon con EXECUTE; '; END IF;
  END LOOP;
  -- el guard: INVOKER, search_path vacío, ACL de siempre, con el GUC, md5 nuevo
  v := (SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()'));
  IF v IS DISTINCT FROM 'false {"search_path=\"\""} {postgres=X/postgres} 2f248d00366785c4c1e569f814a7e27c' THEN bad := bad||'guard '||COALESCE(v, '-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()')
                   AND p.prosrc LIKE '%app.resolver_empresa_rpc%') THEN bad := bad||'guard sin el GUC; '; END IF;
  -- columnas y constraints
  v := (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod)||':'||a.attnotnull::text||':'||COALESCE(a.attacl::text, '-'), ',' ORDER BY a.attname)
          FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass
           AND a.attname IN ('motivo_rechazo', 'revisado_por', 'revisado_at') AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'motivo_rechazo:text:false:-,revisado_at:timestamp with time zone:false:-,revisado_por:uuid:false:-' THEN
    bad := bad||'columnas '||COALESCE(v, '-')||'; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.empresas_proveedoras'::regclass
                   AND c.conname = 'empresas_proveedoras_motivo_rechazo_chk' AND c.contype = 'c' AND c.convalidated) THEN
    bad := bad||'falta el CHECK de motivo; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.empresas_proveedoras'::regclass
                   AND c.conname = 'empresas_proveedoras_revisado_por_fkey' AND c.contype = 'f'
                   AND c.confrelid = 'public.perfiles'::regclass AND c.confdeltype = 'r') THEN
    bad := bad||'falta la FK revisado_por -> perfiles ON DELETE RESTRICT; ';
  END IF;
  -- anon: sin escritura en las columnas nuevas (la lectura por privilegio viene del SELECT de tabla legado; 0 filas por RLS)
  IF has_column_privilege('anon', 'public.empresas_proveedoras', 'motivo_rechazo', 'UPDATE')
     OR has_column_privilege('anon', 'public.empresas_proveedoras', 'revisado_por', 'UPDATE')
     OR has_column_privilege('anon', 'public.empresas_proveedoras', 'revisado_at', 'UPDATE') THEN
    bad := bad||'anon puede escribir columnas de revisión; ';
  END IF;
  -- la tabla: misma ACL, mismas policies (4), RLS ON
  IF (SELECT c.relacl::text||' '||c.relrowsecurity::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=rw/postgres,service_role=arwdDxtm/postgres} true' THEN
    bad := bad||'ACL o RLS de empresas_proveedoras cambió; ';
  END IF;

  -- funciones completas: solo se movieron las 2 nuevas y el guard
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname NOT IN ('listar_empresas_pais', 'resolver_empresa', 'empresas_proveedoras_guard_update'));
  IF v IS DISTINCT FROM 'f0a72054b27c11410c469b59336f46ac 410' THEN bad := bad||'cambió otra función (funciones completas sin las 3) '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 413 THEN
    bad := bad||'el total de funciones no es 413; ';
  END IF;
  -- ACL de funciones: sin las 2 nuevas, idéntica
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname NOT IN ('listar_empresas_pais', 'resolver_empresa')) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones sin las 2 nuevas '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public: idéntica (ADD COLUMN no toca relacl ni crea ACL por columna)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  -- policies: idénticas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG86: autochequeo: %', bad USING ERRCODE = 'MIG86';
  END IF;
END $autochequeo$;

COMMIT;
