-- =====================================================================================================================
-- MIG 389 — Familia B, cierre: se retira la escritura directa del super_admin sobre empresas_proveedoras.
-- Diseño: output/diseno-388-389-17nov.md §4 (17-nov-2026); D-6, D-7 y D-9 aprobadas como recomienda la sección 7;
-- D-10: el GUC app.resolver_empresa_rpc NO se renombra.
--
-- Por qué: desde la 388 + el front del PR #89, el super_admin cambia el estado de una empresa SOLO por RPC
-- (resolver_empresa: aprobar/rechazar; cambiar_estado_empresa: suspender/reactivar/reabrir). Lo que queda de la
-- escritura directa ya no tiene consumidor y es superficie: la policy "Admin ezpay actualiza empresas" deja editar
-- nombre/NIT/contacto de CUALQUIER empresa sin rastro (y ni mira perfiles.activo), y el guard todavía exime al
-- super_admin de la regla de estado/tipo/país/plan.
--
-- Censo (17-nov-2026, contra origin/main e7ddbff, las 38 edges vivas y el prosrc vivo):
--   escritores directos como authenticated: SOLO src/proveedor/hooks/useProveedorAuth.ts:150 (actualizarEmpresa), con
--   las columnas de CAMPOS_PERFIL (src/proveedor/lib/perfilEmpresa.ts:7-14: nombre_empresa, ruc_nit, ciudad, direccion,
--   email_contacto, telefono); sus dos llamadores mandan solo esas (ProveedorPerfilPage.tsx:66 por diff con esa
--   whitelist; LabPerfilPage.tsx:31 con un form de esas 6). Ninguna edge viva escribe la tabla.
--   notificar_empresa_estado: la llaman solo resolver_empresa y cambiar_estado_empresa (DEFINER); ni el front ni una
--   edge viva la llaman.
--   policy "Admin ezpay actualiza empresas": sin consumidor (el front de la 388 ya no hace UPDATE directo; ninguna
--   función la menciona).
--
-- Qué hace (y nada más):
--   1. private.empresas_proveedoras_guard_update(): v_exento pierde `OR private.tiene_rol(ARRAY['super_admin'])`.
--      Quedan exentos solo por current_user (service_role, postgres, supabase_admin, supabase_auth_admin: las RPCs
--      DEFINER y los fixtures del harness). Se mantienen intactas la regla del GUC (v_rpc = current_user 'postgres' +
--      app.resolver_empresa_rpc 'on') para las columnas de revisión y la de transición pendiente -> activa|rechazada.
--      Resultado: NINGÚN usuario, super_admin incluido, cambia estado/tipo/país/plan ni columnas de revisión fuera de
--      las RPCs. Mismo nombre, firma, INVOKER, search_path y ACL (CREATE OR REPLACE). El cuerpo nuevo no lleva líneas
--      de comentario (harness_run.py las quita al inyectar una migración y el md5 no coincidiría).
--   2. D-6: DROP POLICY "Admin ezpay actualiza empresas". Un UPDATE directo del super_admin pasa a afectar 0 filas
--      (sin policy UPDATE que lo habilite); el guard queda como segunda barrera.
--   3. D-7: UPDATE de authenticated POR COLUMNA: REVOKE UPDATE de la tabla + GRANT UPDATE de las 6 columnas del
--      censo. Cierra created_at/updated_at/id para el proveedor (el guard no los mira). SELECT y el resto sin tocar;
--      anon (r, WL_ANON_LEGACY) sin tocar (backlog familia 2). Toda columna nueva del perfil va a necesitar su GRANT.
--   4. D-9: REVOKE EXECUTE de notificar_empresa_estado(uuid) a PUBLIC, anon y authenticated: queda para postgres
--      (las RPCs DEFINER que la llaman) y service_role. Cierra el reenvío manual de avisos.
-- Sin errcodes nuevos (MIG89 = guarda).
--
-- Huellas medidas el 17-nov-2026 19:56:19 UTC (estado post-388):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ f8e2dd272b161f3f0d69f31b32c9c877 415
--   ACL de funciones (solo privilegios), public/private ............................. 51d87b443777a680da5891b25fe41e6f 415
--   ACL de relaciones de public ...................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage .................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Qué se mueve (lo exige el autochequeo):
--   funciones completas: SOLO el guard (cuerpo) y notificar_empresa_estado (ACL; la huella incluye proacl). Sin esas
--     dos: 7fa35a9772eaa8febde0772a270d6803 413, antes y después.
--   ACL de funciones: SOLO notificar_empresa_estado (pierde authenticated). Sin ella: 705392cce9c8191fa6bce4361c75bd30 414.
--   ACL de relaciones de public: SOLO empresas_proveedoras (authenticated pasa de rw a r; la huella mira relacl, no los
--     grants por columna): 2445 -> 2444. Sin la tabla: 485ce08f3b5972d1ea24ed0c7d599062 2426.
--   policies: SOLO el DROP: 314 -> 313 = 4b9da3e2955e1156feca9c8585c37fab 313 (la huella de hoy sin esa policy).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/389_empresas_cierre_escritura_directa.sql
-- Rollback: supabase/migrations/389_rollback.sql (cadena: 389_rollback -> 388_rollback -> 387_rollback -> ...).
-- Orden de despliegue: el front de la 388 (PR #89) tiene que estar en Production ANTES de aplicar esta migración (la
-- base no lo puede comprobar: va en el checklist del apply).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- funciones de las que depende o que toca, exactas (md5(prosrc) + SECURITY DEFINER + config + ACL); la 388 aplicada
  FOR r IN SELECT * FROM (VALUES
      ('private.empresas_proveedoras_guard_update()', '2f248d00366785c4c1e569f814a7e27c', false, '{"search_path=\"\""}', '{postgres=X/postgres}'),
      ('public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.cambiar_estado_empresa(uuid,text)', 'be01192509075ca4acb18cfc8c6502ab', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.listar_empresas_pais(uuid,text)', 'f554317d0b1b0976df9cca289b092ca4', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.obtener_empresa_pais(uuid)', 'e2d732d47724d5bcc5fafd794334e4a1', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.notificar_empresa_estado(uuid)', '72cf7417810b164753223c49d88dc8c4', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.aprobar_personalizacion(uuid)', '1be49d9abf92a4da3a5c43f4e1f1aa3d', true, '{search_path=public}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)', 'fae23eeeacb393328f774386ccd88479', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.trg_guard_tema_columns()', 'c28b30d803b7edec11a8e21e02baa399', false, '{search_path=public}', '{postgres=X/postgres}'),
      ('private.mi_empresa_onboarding()', '58097b3c4755458774653102bf9a2f3d', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.mi_rol_onboarding()', 'd5d591038913e7d762374bc3a9fbc6c2', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.mi_empresa_propia()', '177ae79baa15002bbdb04e3a08f3480e', true, '{"search_path=\"\""}', '{postgres=X/postgres,authenticated=X/postgres}')) AS t(firma, md5_vivo, secdef, cfg, acl)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo||' '||r.secdef::text||' '||r.cfg||' '||r.acl THEN
      bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); ';
    END IF;
  END LOOP;
  -- triggers de la tabla enganchados
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text, '; ' ORDER BY t.tgname) FROM pg_trigger t
       WHERE t.tgrelid = 'public.empresas_proveedoras'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'empresas_proveedoras_guard_update->private.empresas_proveedoras_guard_update(); trigger_guard_tema_empresas->private.trg_guard_tema_columns()' THEN
    bad := bad||'triggers de la tabla distintos de los medidos; ';
  END IF;
  -- las 4 policies de la tabla, con su definición (la 389 no está aplicada: la policy del super_admin existe)
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass);
  IF v IS DISTINCT FROM '2b53ef56aeca25f25ee491ca89d02ea7 4' THEN bad := bad||'policies de la tabla '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de la tabla y ninguna columna con grants propios
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=rw/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de la tabla distinta de la medida; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL) THEN
    bad := bad||'la tabla ya tiene grants por columna; ';
  END IF;

  -- huellas post-388 (17-nov-2026 19:56:19 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f8e2dd272b161f3f0d69f31b32c9c877 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '51d87b443777a680da5891b25fe41e6f 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG89: precondición: %', bad USING ERRCODE = 'MIG89';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Guard sin la exención del super_admin
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.empresas_proveedoras_guard_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = ''
AS $fn$
DECLARE v_exento boolean; v_rpc boolean;
BEGIN
  v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin');
  v_rpc := current_user = 'postgres'
           AND COALESCE(pg_catalog.current_setting('app.resolver_empresa_rpc', true), '') = 'on';

  IF TG_OP = 'INSERT' THEN
    IF NOT v_exento AND NEW.estado IS DISTINCT FROM 'pendiente' THEN
      NEW.estado := 'pendiente';
    END IF;
    IF NOT v_rpc AND (NEW.motivo_rechazo IS NOT NULL OR NEW.revisado_por IS NOT NULL OR NEW.revisado_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

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

  IF ( NEW.motivo_rechazo IS DISTINCT FROM OLD.motivo_rechazo
    OR NEW.revisado_por   IS DISTINCT FROM OLD.revisado_por
    OR NEW.revisado_at    IS DISTINCT FROM OLD.revisado_at )
     AND NOT v_rpc THEN
    RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.estado = 'pendiente' AND NEW.estado IN ('activa', 'rechazada') AND NOT (v_rpc OR v_exento) THEN
    RAISE EXCEPTION 'No autorizado a resolver la empresa'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) D-6: sin UPDATE directo del super_admin
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Admin ezpay actualiza empresas" ON public.empresas_proveedoras;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) D-7: UPDATE de authenticated solo en las 6 columnas del perfil
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE UPDATE ON public.empresas_proveedoras FROM authenticated;
GRANT UPDATE (nombre_empresa, ruc_nit, ciudad, direccion, email_contacto, telefono) ON public.empresas_proveedoras TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) D-9: notificar_empresa_estado solo para postgres (RPCs DEFINER) y service_role
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.notificar_empresa_estado(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; src text;
BEGIN
  -- guard: cuerpo nuevo exacto, sin la exención del super_admin, con la regla del GUC; INVOKER, search_path, ACL
  SELECT p.prosrc INTO src FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()');
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()'));
  IF v IS DISTINCT FROM '8e7102b67317e97ada88884ac7783b1e false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'guard '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF src ILIKE '%super_admin%' OR src ILIKE '%tiene_rol%' THEN bad := bad||'el guard todavía menciona al super_admin; '; END IF;
  IF src NOT LIKE '%app.resolver_empresa_rpc%' OR src NOT LIKE '%v_rpc := current_user = ''postgres''%' THEN
    bad := bad||'el guard perdió la regla del GUC; ';
  END IF;
  -- triggers sin cambio
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text, '; ' ORDER BY t.tgname) FROM pg_trigger t
       WHERE t.tgrelid = 'public.empresas_proveedoras'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'empresas_proveedoras_guard_update->private.empresas_proveedoras_guard_update(); trigger_guard_tema_empresas->private.trg_guard_tema_columns()' THEN
    bad := bad||'triggers de la tabla cambiaron; ';
  END IF;
  -- policy borrada y las otras 3 idénticas
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass AND pl.polname = 'Admin ezpay actualiza empresas') THEN
    bad := bad||'la policy Admin ezpay actualiza empresas sigue; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass);
  IF v IS DISTINCT FROM '257c5ba14604d9baf3b37d81c0b2d80a 3' THEN bad := bad||'las 3 policies que quedan '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de la tabla: authenticated solo SELECT a nivel tabla; el resto igual
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de la tabla '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass), '-')||'; ';
  END IF;
  -- grants por columna: EXACTAMENTE UPDATE de authenticated en las 6 del perfil, nada más
  v := (SELECT string_agg(a.attname||'='||a.attacl::text, '; ' ORDER BY a.attname)
          FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL);
  IF v IS DISTINCT FROM 'ciudad={authenticated=w/postgres}; direccion={authenticated=w/postgres}; email_contacto={authenticated=w/postgres}; nombre_empresa={authenticated=w/postgres}; ruc_nit={authenticated=w/postgres}; telefono={authenticated=w/postgres}' THEN
    bad := bad||'grants por columna '||COALESCE(v, '(ninguno)')||'; ';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.empresas_proveedoras', 'SELECT') THEN bad := bad||'authenticated perdió SELECT; '; END IF;
  IF has_column_privilege('authenticated', 'public.empresas_proveedoras', 'estado', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.empresas_proveedoras', 'created_at', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.empresas_proveedoras', 'id', 'UPDATE') THEN
    bad := bad||'authenticated todavía puede UPDATE fuera de las 6 columnas; ';
  END IF;
  -- notificar_empresa_estado: sin authenticated, anon ni PUBLIC; cuerpo sin cambio
  v := (SELECT md5(p.prosrc)||' '||COALESCE(p.proacl::text, '-') FROM pg_proc p WHERE p.oid = to_regprocedure('public.notificar_empresa_estado(uuid)'));
  IF v IS DISTINCT FROM '72cf7417810b164753223c49d88dc8c4 {postgres=X/postgres,service_role=X/postgres}' THEN bad := bad||'notificar_empresa_estado '||COALESCE(v, '-')||'; '; END IF;
  IF has_function_privilege('authenticated', 'public.notificar_empresa_estado(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.notificar_empresa_estado(uuid)', 'EXECUTE')
     OR has_function_privilege('public', 'public.notificar_empresa_estado(uuid)', 'EXECUTE') THEN
    bad := bad||'notificar_empresa_estado todavía ejecutable por authenticated/anon/PUBLIC; ';
  END IF;

  -- huellas: funciones completas, solo se movieron el guard y notificar_empresa_estado
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN (to_regprocedure('private.empresas_proveedoras_guard_update()'), to_regprocedure('public.notificar_empresa_estado(uuid)')));
  IF v IS DISTINCT FROM '7fa35a9772eaa8febde0772a270d6803 413' THEN bad := bad||'cambió otra función (funciones completas sin guard ni notificar) '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 415 THEN
    bad := bad||'el total de funciones no es 415; ';
  END IF;
  -- ACL de funciones: solo se movió notificar_empresa_estado
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.oid <> to_regprocedure('public.notificar_empresa_estado(uuid)')) y);
  IF v IS DISTINCT FROM '705392cce9c8191fa6bce4361c75bd30 414' THEN bad := bad||'cambió la ACL de otra función '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public: solo se movió empresas_proveedoras (2445 -> 2444)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'empresas_proveedoras') x);
  IF v IS DISTINCT FROM '485ce08f3b5972d1ea24ed0c7d599062 2426' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  -- policies: la huella de hoy sin la policy borrada (314 -> 313)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '4b9da3e2955e1156feca9c8585c37fab 313' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG89: autochequeo: %', bad USING ERRCODE = 'MIG89';
  END IF;
END $autochequeo$;

COMMIT;
