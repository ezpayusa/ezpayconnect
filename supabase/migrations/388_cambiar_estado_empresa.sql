-- =====================================================================================================================
-- MIG 388 — Familia B: el super_admin suspende / reactiva / reabre empresas proveedoras por RPC.
-- Diseño: output/diseno-388-389-17nov.md (17-nov-2026), D-1 a D-9 aprobadas como recomienda la sección 7, salvo:
--   D-8: MedicosPrueba queda activa, sin corrección (esta migración no la toca);
--   D-10: el GUC app.resolver_empresa_rpc se REUSA y NO se renombra (tampoco en la 389).
--
-- Por qué: hoy suspender y reactivar son un UPDATE directo del super_admin sobre empresas_proveedoras
-- (EmpresasProveedorasPage.cambiarEstado) más una llamada aparte a notificar_empresa_estado, y una empresa 'rechazada' no
-- tiene salida. Esta migración agrega el camino por RPC; la 389 retira la escritura directa (después del front nuevo).
--
-- Qué hace (PURAMENTE ADITIVA: no toca el guard, ni resolver_empresa, ni notificar_empresa_estado, ni policies, ni grants
-- de tabla):
--   public.cambiar_estado_empresa(p_empresa_id uuid, p_accion text) RETURNS jsonb, SECURITY DEFINER, search_path = '',
--   VOLATILE. Orden:
--     1. sin sesión -> EP001;
--     2. acción (lower(btrim)) fuera de {'suspender','reactivar','reabrir'} -> EP005. Se reusa EP005 porque la cabecera
--        de la 386 lo define como "dato inválido: acción desconocida, …" y resolver_empresa ya lo usa así; no revela nada
--        de la empresa (va antes de leerla);
--     3. el llamante no es super_admin activo (private.tiene_rol, COALESCE fail-closed; D2: el admin_pais NO) -> EP002,
--        ANTES de leer la fila (un no autorizado no toma el lock ni distingue si existe);
--     4. SELECT … FOR UPDATE; no existe -> EP002 con el mismo mensaje;
--     5. transiciones válidas, y solo esas: suspender activa -> suspendida; reactivar suspendida -> activa; reabrir
--        rechazada -> pendiente. Cualquier otra, incluida repetir la acción, -> EP006 (D-2; sin no-op silencioso);
--     6. pone app.resolver_empresa_rpc = 'on' (local a la transacción) solo alrededor del UPDATE, igual que
--        resolver_empresa (D-10): el guard exige ese GUC + current_user = 'postgres' para escribir las columnas de
--        revisión. UPDATE de estado + updated_at; 'reabrir' además pone motivo_rechazo, revisado_por y revisado_at en
--        NULL (D-3: una pendiente queda sin revisar, como al nacer); suspender y reactivar no tocan esas columnas;
--     7. aviso a la empresa con public.notificar_empresa_estado (texto actual, D-5: reactivar dice "Empresa aprobada") +
--        private.push_notificar por cada aviso creado, en un sub-bloque con EXCEPTION como resolver_empresa: si falla, el
--        cambio de estado queda hecho y notificado = false. Diferencia deliberada con resolver_empresa: el push excluye
--        los avisos 'empresa' que ya existían con created_at = now() ANTES de esta llamada (v_previas), para que dos
--        llamadas en una misma transacción no re-encolen el push de la primera. Por PostgREST cada llamada es su propia
--        transacción y el resultado es el mismo que el de resolver_empresa;
--     8. devuelve {empresa_id, estado (el nuevo), notificado}, el mismo shape que resolver_empresa.
--   Sin motivo para suspender (D-4). Sin historial de revisiones (D-3, backlog).
--   ACL: REVOKE ALL de PUBLIC y anon; EXECUTE para authenticated y service_role (service_role ya lo da el default de la
--   344 y queda explícito, igual que en la 386/387). Sin sesión de usuario (service_role sin sub) la RPC da EP001.
--   El cuerpo de la función NO lleva líneas de comentario: harness_run.py las quita antes de enviar, y con una adentro el
--   md5(prosrc) de una corrida con la 388 inyectada no coincidiría con el del apply por `db query -f`.
--
-- Errores (mensajes para el usuario final, en tú, sin eco de datos):
--   EP001  no hay sesión                                      (reusado de la 386, mismo texto)
--   EP002  la empresa no existe o no puedes gestionarla        (reusado, mismo texto; también el admin_pais)
--   EP005  la acción no es válida                              (reusado, mismo texto)
--   EP006  NUEVO: la empresa no está en un estado que permita esta acción (transición inválida o repetida)
--   MIG88  guarda de esta migración
--
-- Huellas medidas el 17-nov-2026 18:18:45 UTC (estado post-387):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ 6ef5bdb38d4a4a33a594943ad611865d 414
--   ACL de funciones (solo privilegios), public/private ............................. faf529bf0e6934677f743e35fa899f8d 414
--   ACL de relaciones de public ...................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage .................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Después: funciones completas y ACL de funciones se mueven SOLO por cambiar_estado_empresa (sin ella siguen en
-- 6ef5bdb3…/414 y faf529bf…/414; el total pasa a 415); relaciones y policies IDÉNTICAS.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/388_cambiar_estado_empresa.sql
-- Rollback: supabase/migrations/388_rollback.sql (cadena: 388_rollback -> 387_rollback -> 386_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 388 no está aplicada
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'cambiar_estado_empresa') THEN
    bad := bad||'cambiar_estado_empresa ya existe (388 aplicada); ';
  END IF;
  -- la 387 aplicada y las funciones de las que depende, exactas (md5(prosrc) + SECURITY DEFINER + config + ACL)
  FOR r IN SELECT * FROM (VALUES
      ('public.obtener_empresa_pais(uuid)', 'e2d732d47724d5bcc5fafd794334e4a1', true, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.listar_empresas_pais(uuid,text)', 'f554317d0b1b0976df9cca289b092ca4', true, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24', true, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.notificar_empresa_estado(uuid)', '72cf7417810b164753223c49d88dc8c4', true, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.puede_admin_pais(uuid,text[])', '8bc2928e369d98e305355440df8b52ac', true, '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.push_notificar(text,text)', '90e6e8ec7eb37240e400a7c5768a8997', true, '{postgres=X/postgres}'),
      ('private.tiene_rol(text[])', '2032eb10b9e9a90e5be58100607370e3', true, '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.rol_usuario()', '51df907aba35bf44abd671a3f23b7234', true, '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.empresas_proveedoras_guard_update()', '2f248d00366785c4c1e569f814a7e27c', false, '{postgres=X/postgres}')) AS t(firma, md5_vivo, secdef, acl)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo||' '||r.secdef::text||' {"search_path=\"\""} '||r.acl THEN
      bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); ';
    END IF;
  END LOOP;
  -- el trigger del guard sigue enganchado
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.empresas_proveedoras'::regclass
                   AND t.tgname = 'empresas_proveedoras_guard_update'
                   AND t.tgfoid = to_regprocedure('private.empresas_proveedoras_guard_update()') AND NOT t.tgisinternal) THEN
    bad := bad||'trigger empresas_proveedoras_guard_update no enganchado al guard; ';
  END IF;
  -- los 4 estados del CHECK (las 3 transiciones dependen de ellos)
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname = 'empresas_proveedoras_estado_chk'
        AND c.conrelid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM $c$CHECK ((estado = ANY (ARRAY['pendiente'::text, 'activa'::text, 'suspendida'::text, 'rechazada'::text])))$c$ THEN
    bad := bad||'CHECK de estado distinto del medido; ';
  END IF;

  -- huellas post-387 (17-nov-2026 18:18:45 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '6ef5bdb38d4a4a33a594943ad611865d 414' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'faf529bf0e6934677f743e35fa899f8d 414' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG88: precondición: %', bad USING ERRCODE = 'MIG88';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) cambiar_estado_empresa
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.cambiar_estado_empresa(p_empresa_id uuid, p_accion text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_accion text := lower(btrim(COALESCE(p_accion, '')));
  v_estado text;
  v_desde text;
  v_nuevo text;
  v_previas uuid[];
  v_notificado boolean := false;
  r record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Tu sesión no está activa. Vuelve a iniciar sesión.' USING ERRCODE = 'EP001';
  END IF;
  IF v_accion NOT IN ('suspender', 'reactivar', 'reabrir') THEN
    RAISE EXCEPTION 'La acción no es válida.' USING ERRCODE = 'EP005';
  END IF;
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false) THEN
    RAISE EXCEPTION 'La empresa no existe o no puedes gestionarla.' USING ERRCODE = 'EP002';
  END IF;

  SELECT e.estado INTO v_estado
    FROM public.empresas_proveedoras e
   WHERE e.id = p_empresa_id
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La empresa no existe o no puedes gestionarla.' USING ERRCODE = 'EP002';
  END IF;

  v_desde := CASE v_accion WHEN 'suspender' THEN 'activa' WHEN 'reactivar' THEN 'suspendida' ELSE 'rechazada' END;
  v_nuevo := CASE v_accion WHEN 'suspender' THEN 'suspendida' WHEN 'reactivar' THEN 'activa' ELSE 'pendiente' END;
  IF v_estado IS DISTINCT FROM v_desde THEN
    RAISE EXCEPTION 'La empresa no está en un estado que permita esta acción.' USING ERRCODE = 'EP006';
  END IF;

  PERFORM pg_catalog.set_config('app.resolver_empresa_rpc', 'on', true);
  UPDATE public.empresas_proveedoras e
     SET estado = v_nuevo,
         motivo_rechazo = CASE WHEN v_accion = 'reabrir' THEN NULL ELSE e.motivo_rechazo END,
         revisado_por = CASE WHEN v_accion = 'reabrir' THEN NULL ELSE e.revisado_por END,
         revisado_at = CASE WHEN v_accion = 'reabrir' THEN NULL ELSE e.revisado_at END,
         updated_at = now()
   WHERE e.id = p_empresa_id;
  PERFORM pg_catalog.set_config('app.resolver_empresa_rpc', 'off', true);

  BEGIN
    v_previas := ARRAY(SELECT n.id FROM public.notificaciones n WHERE n.tipo = 'empresa' AND n.created_at = now());
    PERFORM public.notificar_empresa_estado(p_empresa_id);
    FOR r IN
      SELECT n.id FROM public.notificaciones n
       WHERE n.tipo = 'empresa' AND n.created_at = now()
         AND NOT (n.id = ANY (v_previas))
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
-- b) ACL (sin grants nuevos de tabla)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.cambiar_estado_empresa(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cambiar_estado_empresa(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'cambiar_estado_empresa') <> 1 THEN bad := bad||'cambiar_estado_empresa: sobrecargas <> 1; '; END IF;
  v := (SELECT p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.cambiar_estado_empresa(uuid,text)'));
  IF v IS DISTINCT FROM 'true v {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} be01192509075ca4acb18cfc8c6502ab' THEN
    bad := bad||'cambiar_estado_empresa '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF has_function_privilege('anon', 'public.cambiar_estado_empresa(uuid,text)', 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF has_function_privilege('public', 'public.cambiar_estado_empresa(uuid,text)', 'EXECUTE') THEN bad := bad||'PUBLIC con EXECUTE; '; END IF;

  -- las que no se tocan, por nombre (también entran en la huella de abajo)
  FOR r IN SELECT * FROM (VALUES
      ('public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24'),
      ('public.notificar_empresa_estado(uuid)', '72cf7417810b164753223c49d88dc8c4'),
      ('private.empresas_proveedoras_guard_update()', '2f248d00366785c4c1e569f814a7e27c')) AS t(firma, md5_vivo)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md5_vivo THEN
      bad := bad||r.firma||' cambió; ';
    END IF;
  END LOOP;

  -- funciones completas: solo se movió cambiar_estado_empresa
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'cambiar_estado_empresa');
  IF v IS DISTINCT FROM '6ef5bdb38d4a4a33a594943ad611865d 414' THEN bad := bad||'cambió otra función (funciones completas sin la nueva) '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 415 THEN
    bad := bad||'el total de funciones no es 415; ';
  END IF;
  -- ACL de funciones: sin la nueva, idéntica
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname <> 'cambiar_estado_empresa') y);
  IF v IS DISTINCT FROM 'faf529bf0e6934677f743e35fa899f8d 414' THEN bad := bad||'huella de ACL de funciones sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public: idéntica
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
    RAISE EXCEPTION 'MIG88: autochequeo: %', bad USING ERRCODE = 'MIG88';
  END IF;
END $autochequeo$;

COMMIT;
