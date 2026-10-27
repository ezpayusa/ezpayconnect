-- =====================================================================================================================
-- MIG 385 — registrar_clinica_desde_invitacion v2: el registro de clínica por invitación deja de fallar siempre.
-- Diseño: output/diseno-registro-clinica-26oct.md (26-oct-2026). Prerequisito: mig 384 (listados de médicos por país
-- solo con rol 'medico'), aplicada en prod.
--
-- Por qué: la versión viva (RETURNS integer, search_path = public) falla el 100% de las veces. Insertaba la clínica sin
-- doctor_id (NOT NULL -> 23502); si pasara, el RETURNING uuid iba a un INTEGER (22P02); y la membresía en
-- medico_clinicas no tenía fila en medicos (FK -> 23503). La edge dejaba un usuario de auth y un perfil huérfanos.
--
-- Qué hace la v2 (todo en la transacción de la llamada; si algo falla, no queda nada):
--   1. invitación: token, estado 'pendiente' y expires_at > now(), con FOR UPDATE -> si no, RC001;
--   2. la cuenta (auth.users de p_user_id) existe -> si no, RC004; su correo y p_email = el de la invitación -> RC002;
--   3. la cuenta no tiene ninguna identidad en la plataforma (mismo criterio que la mig 327: perfiles, pacientes,
--      medicos, cuentas_proveedor, asesores_perfil, usuario_roles) -> si no, RC003 (caso Clinica ES: el correo ya es
--      de un paciente). La RPC nunca "convierte" una cuenta existente;
--   4. datos: nombre de contacto (p_nombre_contacto o el de la invitación) y nombre de la clínica no vacíos -> RC004;
--   5. perfil: INSERT perfiles rol 'admin_clinica', país de la invitación (la edge v19 deja de insertarlo);
--   6. fila en medicos (id = uid, nombre, país; clinica_id NULL por ahora): requisito de la FK de medico_clinicas,
--      igual que crear-staff-clinica. La 384 lo saca de listar/contar_medicos_por_pais;
--   7. private.crear_clinica_con_dueno_interno(uid, ...): clínica con doctor_id = el admin que se registra (decisión de
--      Oscar, 26-oct) + su membresía (es_principal = true: es la primera del usuario);
--   8. public.asociar_medico_clinica(uid, clínica, true): el mismo camino que crear-staff-clinica. Con auth.uid() NULL
--      (la llama la edge con service_role) no exige gate; ON CONFLICT DO UPDATE deja es_principal = true;
--   9. UPDATE medicos SET clinica_id = la clínica (queda como clinica.qa); 10. invitación -> 'usada', used_at = now();
--   11. RETURN la clínica (uuid).
-- Un advisory lock por uid serializa dos llamadas con la misma cuenta (patrón de la 373): la segunda ve el perfil de la
-- primera y responde RC003, nunca un 23505 crudo.
--
-- Errores (mensajes para el usuario final, en tú, sin eco de datos):
--   RC001  la invitación no existe, venció o ya se usó (el mismo error para los tres casos)
--   RC002  el correo no coincide con el de la invitación
--   RC003  la cuenta ya tiene una identidad en la plataforma
--   RC004  faltan datos para completar el registro (la cuenta, el nombre de contacto o el nombre de la clínica)
--   MIG85  guarda de esta migración
--
-- Cambia el tipo de retorno (integer -> uuid): CREATE OR REPLACE no puede, así que va DROP + CREATE con la MISMA firma
-- de parámetros (los nombres importan: la edge llama con argumentos nombrados).
-- ACL: la función nueva nace con EXECUTE para authenticated y service_role (default privileges de la 344); se revoca
-- PUBLIC, anon y authenticated y queda solo service_role (la llama la edge registrar-clinica-invitacion con la clave de
-- service_role, antes de que exista una sesión). ACL final {postgres=X/postgres,service_role=X/postgres}: la misma de hoy.
--
-- Huellas medidas el 26-oct-2026 18:09:16 UTC (estado post-384):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ d00a1210ec290baa9946988f492c1bb3 411
--   funciones completas SIN registrar_clinica_desde_invitacion ....................... 2ffdb08f23d573abd0e12a7abe3dde70 410
--   ACL de funciones (solo privilegios), public/private ............................. af6b7bf22f370f6ee5ff89ff59eb0ea5 411
--   ACL de relaciones de public ...................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage .................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Después: solo se mueve "funciones completas" (por esta función). "ACL de funciones" queda IDÉNTICA: la huella se arma
-- con regprocedure|grantee|grantor|privilegio y la firma, los grantees (postgres, service_role) y el grantor (postgres)
-- son los mismos de hoy; el oid nuevo no entra en la huella.
-- md5(prosrc): 76d52027eeca678aca8e28354088e07f (v1, CRLF) -> ed19aae358ba091ef9e82ed18451615b (v2).
-- Orden de deploy: esta migración -> edge registrar-clinica-invitacion v19 en el mismo bloque. Entre las dos, la edge v18
-- inserta el perfil antes de llamar y la v2 responde RC003: sigue fallando como hoy, sin regresión nueva.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/385_registro_clinica_invitacion.sql
-- Rollback: supabase/migrations/385_rollback.sql (cadena: 385_rollback -> 384_rollback -> 383_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la función viva v1 (si ya es la v2, la 385 está aplicada)
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)')
               AND p.prorettype = 'uuid'::regtype) THEN
    bad := bad||'registrar_clinica_desde_invitacion ya devuelve uuid (385 aplicada); ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)')
                   AND md5(p.prosrc) = '76d52027eeca678aca8e28354088e07f' AND p.prorettype = 'integer'::regtype AND p.prosecdef
                   AND p.proconfig = ARRAY['search_path=public']
                   AND p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}') THEN
    bad := bad||'registrar_clinica_desde_invitacion no es la v1 medida (md5 '||COALESCE((SELECT md5(p.prosrc) FROM pg_proc p
           WHERE p.oid = to_regprocedure('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)')), 'no existe')||'); ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_clinica_desde_invitacion') <> 1 THEN
    bad := bad||'sobrecargas de registrar_clinica_desde_invitacion; ';
  END IF;
  -- dependencias, rotuladas
  FOR r IN SELECT * FROM (VALUES
      ('private.crear_clinica_con_dueno_interno(uuid,text,uuid,text,text,text)', 'bdd97d7989bdddf4ddfe4dce49da7fae', '{postgres=X/postgres}'),
      ('public.asociar_medico_clinica(uuid,uuid,boolean)', '91a728b9da4c44cf72a028cea9d4e2c7', '{postgres=X/postgres,service_role=X/postgres}')) AS t(firma, md5_vivo, acl)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||COALESCE(p.proacl::text, '-') FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo||' '||r.acl THEN bad := bad||r.firma||' md5/ACL '||COALESCE(v, 'no existe')||'; '; END IF;
  END LOOP;
  -- la 384 aplicada: el predicado de rol 'medico' en las dos funciones
  FOR r IN SELECT * FROM (VALUES ('public.listar_medicos_por_pais(uuid)'), ('public.contar_medicos_por_pais(uuid)')) AS t(firma) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosrc LIKE $l$%AND EXISTS (SELECT 1 FROM public.perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')%$l$) THEN
      bad := bad||r.firma||' sin el predicado de la 384 (aplicar la 384 primero); ';
    END IF;
  END LOOP;
  -- tablas y columnas de las que depende
  IF (SELECT format_type(a.atttypid, a.atttypmod)||' '||a.attnotnull::text FROM pg_attribute a
       WHERE a.attrelid = 'public.clinicas'::regclass AND a.attname = 'doctor_id') IS DISTINCT FROM 'uuid true' THEN
    bad := bad||'clinicas.doctor_id no es uuid NOT NULL; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conname = 'medico_clinicas_medico_id_fkey'
                   AND c.conrelid = 'public.medico_clinicas'::regclass AND c.confrelid = 'public.medicos'::regclass) THEN
    bad := bad||'falta la FK medico_clinicas -> medicos; ';
  END IF;
  -- RC001-RC004 no están en uso en ninguna función
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.prosrc ~ '''RC00[1-4]''') THEN bad := bad||'RC001-RC004 ya están en uso; '; END IF;

  -- huellas (26-oct-2026 18:09:16 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'registrar_clinica_desde_invitacion');
  IF v IS DISTINCT FROM '2ffdb08f23d573abd0e12a7abe3dde70 410' THEN bad := bad||'huella de funciones completas sin esta '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG85: precondición: %', bad USING ERRCODE = 'MIG85';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) registrar_clinica_desde_invitacion v2 (DROP + CREATE: cambia el tipo de retorno)
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text);

CREATE FUNCTION public.registrar_clinica_desde_invitacion(p_token uuid, p_user_id uuid, p_email text, p_nombre_contacto text, p_telefono text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_inv        record;
  v_email_auth text;
  v_nombre     text;
  v_clinica    uuid;
BEGIN
  -- 1) invitación vigente y pendiente, bloqueada hasta el final de la transacción
  SELECT i.id, i.email, i.pais_id, i.nombre_clinica, i.nombre_contacto, i.direccion, i.telefono INTO v_inv
    FROM public.invitaciones_clinica i
   WHERE i.token = p_token AND i.estado = 'pendiente' AND i.expires_at > now()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta invitación no es válida, ya venció o ya se usó. Pide una nueva invitación.' USING ERRCODE = 'RC001';
  END IF;

  -- 2) la cuenta existe y su correo es el de la invitación
  SELECT NULLIF(btrim(u.email), '') INTO v_email_auth FROM auth.users u WHERE u.id = p_user_id;
  IF v_email_auth IS NULL THEN
    RAISE EXCEPTION 'Faltan datos para completar el registro: la cuenta.' USING ERRCODE = 'RC004';
  END IF;
  IF lower(v_email_auth) IS DISTINCT FROM lower(btrim(v_inv.email))
     OR lower(btrim(p_email)) IS DISTINCT FROM lower(btrim(v_inv.email)) THEN
    RAISE EXCEPTION 'El correo no coincide con el de la invitación.' USING ERRCODE = 'RC002';
  END IF;

  -- 3) identidad única (mismo criterio que la mig 327): la cuenta no puede tener ninguna identidad previa
  PERFORM pg_advisory_xact_lock(hashtextextended('registrar_clinica_desde_invitacion:'||p_user_id::text, 0));
  IF EXISTS (SELECT 1 FROM public.perfiles          WHERE id = p_user_id)
  OR EXISTS (SELECT 1 FROM public.pacientes         WHERE auth_user_id = p_user_id)
  OR EXISTS (SELECT 1 FROM public.medicos           WHERE id = p_user_id)
  OR EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_user_id)
  OR EXISTS (SELECT 1 FROM public.asesores_perfil   WHERE id = p_user_id)
  OR EXISTS (SELECT 1 FROM public.usuario_roles     WHERE usuario_id = p_user_id) THEN
    RAISE EXCEPTION 'Esta cuenta ya está registrada en la plataforma. Inicia sesión con ella o pide la invitación para otro correo.'
      USING ERRCODE = 'RC003';
  END IF;

  -- 4) datos
  v_nombre := COALESCE(NULLIF(btrim(p_nombre_contacto), ''), NULLIF(btrim(v_inv.nombre_contacto), ''));
  IF v_nombre IS NULL THEN
    RAISE EXCEPTION 'Faltan datos para completar el registro: el nombre de contacto.' USING ERRCODE = 'RC004';
  END IF;
  IF NULLIF(btrim(v_inv.nombre_clinica), '') IS NULL THEN
    RAISE EXCEPTION 'Faltan datos para completar el registro: el nombre de la clínica.' USING ERRCODE = 'RC004';
  END IF;

  -- 5) perfil
  INSERT INTO public.perfiles (id, email, nombre_completo, rol, pais_id, activo)
  VALUES (p_user_id, v_email_auth, v_nombre, 'admin_clinica', v_inv.pais_id, true);

  -- 6) fila en medicos (requisito de la FK de medico_clinicas; la 384 la saca de los listados de médicos)
  INSERT INTO public.medicos (id, nombre_completo, pais_id)
  VALUES (p_user_id, v_nombre, v_inv.pais_id);

  -- 7) clínica con el admin como dueño (doctor_id) + su membresía
  v_clinica := private.crear_clinica_con_dueno_interno(
    p_user_id, btrim(v_inv.nombre_clinica), v_inv.pais_id, v_inv.direccion,
    COALESCE(NULLIF(btrim(p_telefono), ''), v_inv.telefono), lower(btrim(v_inv.email)));

  -- 8) membresía principal por el mismo camino que crear-staff-clinica
  PERFORM public.asociar_medico_clinica(p_user_id, v_clinica, true);

  -- 9) la fila de medicos queda con su clínica (como clinica.qa)
  UPDATE public.medicos SET clinica_id = v_clinica WHERE id = p_user_id;

  -- 10) invitación usada
  UPDATE public.invitaciones_clinica SET estado = 'usada', used_at = now() WHERE id = v_inv.id;

  RETURN v_clinica;
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) ACL: solo service_role (la edge). Sin PUBLIC, anon ni authenticated (los default privileges de la 344 le dan
--    EXECUTE a authenticated a toda función nueva de public: por eso el REVOKE explícito).
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- d) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
  c_f CONSTANT text := 'public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)';
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_clinica_desde_invitacion') <> 1 THEN
    bad := bad||'más de una sobrecarga (o ninguna); ';
  END IF;
  IF to_regprocedure(c_f) IS NULL THEN
    RAISE EXCEPTION 'MIG85: autochequeo: la función no existe' USING ERRCODE = 'MIG85';
  END IF;
  IF (SELECT p.prorettype FROM pg_proc p WHERE p.oid = to_regprocedure(c_f)) IS DISTINCT FROM 'uuid'::regtype THEN bad := bad||'prorettype distinto de uuid; '; END IF;
  IF (SELECT p.proconfig FROM pg_proc p WHERE p.oid = to_regprocedure(c_f)) IS DISTINCT FROM ARRAY['search_path=""'] THEN bad := bad||'proconfig sin search_path vacío; '; END IF;
  IF (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure(c_f)) IS DISTINCT FROM true THEN bad := bad||'no es SECURITY DEFINER; '; END IF;
  v := (SELECT p.proacl::text FROM pg_proc p WHERE p.oid = to_regprocedure(c_f));
  IF v IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN bad := bad||'ACL '||COALESCE(v, 'NULL')||'; '; END IF;
  IF has_function_privilege('anon', c_f, 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF has_function_privilege('authenticated', c_f, 'EXECUTE') THEN bad := bad||'authenticated con EXECUTE; '; END IF;
  IF NOT has_function_privilege('service_role', c_f, 'EXECUTE') THEN bad := bad||'service_role sin EXECUTE; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(c_f));
  IF v IS DISTINCT FROM 'ed19aae358ba091ef9e82ed18451615b' THEN bad := bad||'md5(prosrc) '||COALESCE(v, '-')||'; '; END IF;

  -- funciones completas: solo se movió esta
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'registrar_clinica_desde_invitacion');
  IF v IS DISTINCT FROM '2ffdb08f23d573abd0e12a7abe3dde70 410' THEN bad := bad||'cambió otra función (funciones completas sin esta) '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de funciones: idéntica (misma firma, mismos grantees y grantor que la v1)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public y policies: idénticas
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
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG85: autochequeo: %', bad USING ERRCODE = 'MIG85';
  END IF;
END $autochequeo$;

COMMIT;
