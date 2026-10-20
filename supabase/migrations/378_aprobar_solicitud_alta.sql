-- ############################################################################################
-- 378 - aprobar una solicitud de alta de medico -> invitacion precargada + correo (paso 5 de la familia enrolamiento)
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\recon378\ y C:\tmp\mig378\m1-m5.sql). Estado vivo medido:
--   - md5(prosrc): solicitar_alta_medico 4979da5532a3ddd08a466929bbfe27c7, cancelar_solicitud_alta
--     34ff13a23b4681dddd44118b7b2dc1e1, rechazar_solicitud_alta a028473675bea99b8b4bc89108b5ac47, listar_solicitudes_alta
--     90b37826b44f1b7e18813f9916867286, private.email_notificar 6f4a84b3e1864b10c36d691c51e086ff, private.push_notificar
--     90e6e8ec7eb37240e400a7c5768a8997, private.puede_admin_pais 8bc2928e369d98e305355440df8b52ac.
--   - private.app_secrets (nombre PK, valor; ACL solo postgres): email_edge_url (termina en /notificar-email),
--     email_secret, push_edge_url, push_secret; invitacion_edge_url no existe.
--   - public.invitaciones_medico: 14 columnas, sin email_enviado_at, sin triggers, sin privilegios por columna, ACL
--     {postgres=arwdDxtm, authenticated=arwd, service_role=arwdDxtm}. La consumen validar-invitacion-medico,
--     registrar-medico-invitacion y registrar_medico_desde_invitacion con '*' o columnas sueltas: una columna nueva
--     no les cambia nada. registrar_medico_desde_invitacion copia especialidad (texto) y especialidad_id a medicos y,
--     sin clinica_id, crea el consultorio del medico (ruta B).
--   - PV024 y PV025 sin uso en prod ni en el repo; aprobar_solicitud_alta, reenviar_solicitud_alta e
--     invitacion_email_notificar no existen.
--   - Huellas post-377: funciones (cuerpo, DEFINER, config, ACL) 79ac69a1e89865e79424a09abc36ab58/396; ACL de funciones
--     8d5290543497cb8984e6d9b289176818/396; ACL de relaciones de public 9da6a3c4ca75cd58b3a3053603bf03fe/2406; policies
--     cfb5d7632f071052d491e02a6a5e0932/311.
--
-- Que hace:
--   1. invitaciones_medico.email_enviado_at (timestamptz, sin default): claim del correo; lo pone y lo libera la edge
--      enviar-invitacion-medico (service_role).
--   2. private.app_secrets 'invitacion_edge_url' = email_edge_url con el ultimo segmento cambiado por
--      enviar-invitacion-medico (derivado en SQL; el archivo no tiene ninguna URL).
--   3. private.invitacion_email_notificar(uuid): mismo patron que private.email_notificar (DEFINER, search_path = '',
--      EXECUTE solo postgres, no-op si falta la URL o el secreto, best-effort); manda {invitacion_id} con x-email-secret
--      (el secreto de notificar-email). pg_net encola en la transaccion: si la RPC aborta, no sale nada.
--   4. aprobar_solicitud_alta(uuid): admin de pais del pais de la solicitud o super_admin. Crea la invitacion
--      (sin clinica, especialidad texto = nombre del catalogo, created_by = quien aprueba), pasa la solicitud a
--      'invitada', avisa al visitador (in-app + push, texto generico) y dispara el correo. No devuelve el token.
--   5. reenviar_solicitud_alta(uuid): mismo gate; cancela la invitacion actual (si no esta usada), expira las vencidas
--      del correo (PV025 si queda otra vigente), crea otra con los mismos datos y dispara el correo. Sin aviso al visitador.
--   6. solicitar_alta_medico: misma firma; unico cambio, antes del INSERT: si el correo tiene una invitacion
--      'pendiente' no vencida (de cualquier origen) -> PV021 con el mismo mensaje (cierra el backlog 377 (a)).
--
-- Errcodes: reusa PV021/PV022/PV023 de la 377. Nuevos:
--   PV024 el correo ya tiene cuenta en MED (aprobar y reenviar); PV025 el correo ya tiene una invitacion vigente
--   (aprobar y reenviar). Proximo libre: PV026.
--
-- md5(prosrc) de las funciones nuevas o cambiadas (calculado sobre este archivo, sin CR; el autochequeo lo exige):
--   aprobar_solicitud_alta e7a2bea305a4f4dfe564f7b14157835b, reenviar_solicitud_alta d34babc6bffa17257b36d849e1fd7f2c,
--   private.invitacion_email_notificar 10bf2ebc64ea42d9409fe7dd495f429b, solicitar_alta_medico f0d28f9cdc70b277c36a5b337cc0daf5.
--
-- Huellas esperadas despues: ACL de relaciones de public y policies sin cambio; ACL de funciones y funciones completas
--   iguales a las de antes excluyendo las 3 nuevas (y solicitar_alta_medico en la huella completa).
--
-- Deploy: la edge enviar-invitacion-medico (verify_jwt = false) va ANTES que esta migracion. Sin la edge, la RPC
--   funciona igual y el correo se pierde (pg_net recibe un 404; la invitacion queda con email_enviado_at NULL y se
--   puede reenviar).
--
-- Front: nada todavia (PV024/PV025 sin mapear).
--
-- Rollback: 378_rollback.sql (aborta si alguna invitacion tiene email_enviado_at). Orden global:
--   378_rollback -> 377_rollback -> 376_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'),
                         to_regprocedure('public.cancelar_solicitud_alta(uuid)'),
                         to_regprocedure('public.rechazar_solicitud_alta(uuid,text)'),
                         to_regprocedure('public.listar_solicitudes_alta(text)')));
  IF v IS DISTINCT FROM '34ff13a23b4681dddd44118b7b2dc1e1,90b37826b44f1b7e18813f9916867286,a028473675bea99b8b4bc89108b5ac47,4979da5532a3ddd08a466929bbfe27c7' THEN
    bad := bad||'md5 de las 4 RPCs de la 377 '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.email_notificar(uuid,text)'));
  IF v IS DISTINCT FROM '6f4a84b3e1864b10c36d691c51e086ff' THEN bad := bad||'email_notificar md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.push_notificar(text,text)'));
  IF v IS DISTINCT FROM '90e6e8ec7eb37240e400a7c5768a8997' THEN bad := bad||'push_notificar md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.puede_admin_pais(uuid,text[])'));
  IF v IS DISTINCT FROM '8bc2928e369d98e305355440df8b52ac' THEN bad := bad||'puede_admin_pais md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.proname IN ('aprobar_solicitud_alta', 'reenviar_solicitud_alta', 'invitacion_email_notificar')
            OR (p.proname = 'solicitar_alta_medico' AND p.oid <> to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)')));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existentes ['||v||']; '; END IF;
  -- app_secrets: email_edge_url (una fila, termina en /notificar-email) y email_secret; sin invitacion_edge_url.
  -- Los mensajes nunca muestran valores.
  IF (SELECT count(*) FROM private.app_secrets s WHERE s.nombre = 'email_edge_url' AND s.valor ~ '^https://[^/]+/.+/notificar-email$') <> 1 THEN
    bad := bad||'email_edge_url ausente o sin terminar en /notificar-email; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.app_secrets s WHERE s.nombre = 'email_secret' AND COALESCE(s.valor, '') <> '') THEN
    bad := bad||'email_secret ausente o vacio; ';
  END IF;
  IF EXISTS (SELECT 1 FROM private.app_secrets s WHERE s.nombre = 'invitacion_edge_url') THEN
    bad := bad||'invitacion_edge_url ya existe; ';
  END IF;
  -- invitaciones_medico: sin la columna nueva, ACL y privilegios por columna como en el recon
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.invitaciones_medico'::regclass AND a.attname = 'email_enviado_at') THEN
    bad := bad||'la columna email_enviado_at ya existe; ';
  END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.invitaciones_medico'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de invitaciones_medico '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.invitaciones_medico'::regclass AND a.attacl IS NOT NULL) THEN
    bad := bad||'invitaciones_medico con privilegios por columna; ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc ~ 'PV02[45]');
  IF v IS NOT NULL THEN bad := bad||'PV024-PV025 en uso en ['||v||']; '; END IF;
  -- huellas post-377
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cfb5d7632f071052d491e02a6a5e0932 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9da6a3c4ca75cd58b3a3053603bf03fe 2406' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8d5290543497cb8984e6d9b289176818 396' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  -- huella completa de funciones (cuerpo, DEFINER, config, ACL), medida en prod el 20-oct-2026
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '79ac69a1e89865e79424a09abc36ab58 396' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG378_PRE FALLA:%', bad; END IF;

  -- huella de las funciones de public/private sin solicitar_alta_medico (la unica existente que se toca): el
  -- autochequeo exige que, excluyendo las 4 tocadas, quede igual
  CREATE TEMP TABLE mig378_huella ON COMMIT DROP AS
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid <> 'public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: columna de claim del correo
ALTER TABLE public.invitaciones_medico ADD COLUMN email_enviado_at timestamptz;

COMMENT ON COLUMN public.invitaciones_medico.email_enviado_at IS
  'Claim del correo de invitacion (mig 378): lo pone la edge enviar-invitacion-medico antes de enviar y lo vuelve a NULL si el envio falla.';

-- ---------------------------------------------------------------------------- 2: URL de la edge, derivada de la de notificar-email
INSERT INTO private.app_secrets (nombre, valor)
SELECT 'invitacion_edge_url', regexp_replace(s.valor, '/notificar-email$', '/enviar-invitacion-medico')
  FROM private.app_secrets s
 WHERE s.nombre = 'email_edge_url';

-- ---------------------------------------------------------------------------- 3: private.invitacion_email_notificar
CREATE FUNCTION private.invitacion_email_notificar(p_invitacion_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_invitacion_id IS NULL THEN RETURN; END IF;
  SELECT valor INTO v_url    FROM private.app_secrets WHERE nombre = 'invitacion_edge_url';
  SELECT valor INTO v_secret FROM private.app_secrets WHERE nombre = 'email_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;   -- no configurado -> no-op (seguro por defecto)
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-email-secret', v_secret),
    body    := jsonb_build_object('invitacion_id', p_invitacion_id)
  );
EXCEPTION WHEN others THEN RETURN;   -- best-effort: el correo nunca tumba la aprobacion
END;
$function$;

-- ---------------------------------------------------------------------------- 4: aprobar_solicitud_alta
CREATE FUNCTION public.aprobar_solicitud_alta(p_solicitud_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v       record;
  v_found boolean;
  v_esp   text;
  v_inv   uuid;
  v_nid   uuid;
BEGIN
  SELECT s.pais_id, s.solicitado_por, s.estado, s.email, s.nombre_completo, s.telefono, s.especialidad_id INTO v
    FROM public.solicitudes_alta_medico s
   WHERE s.id = p_solicitud_id
   FOR UPDATE;
  v_found := FOUND;

  -- admin de pais del pais de la solicitud o super_admin (fail-closed); inexistente y ajena dan el mismo error
  IF NOT v_found OR NOT COALESCE(private.puede_admin_pais(v.pais_id, ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'La solicitud no existe o no puedes gestionarla.' USING ERRCODE = 'PV023';
  END IF;
  IF v.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'La solicitud ya no está pendiente.' USING ERRCODE = 'PV022';
  END IF;

  -- misma llave que solicitar_alta_medico: serializa contra otra solicitud o aprobacion del mismo correo
  PERFORM pg_advisory_xact_lock(hashtextextended('solicitud_alta_medico:' || v.email, 0));

  IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v.email) THEN
    RAISE EXCEPTION 'Este correo ya tiene cuenta en MED: rechaza la solicitud o pide al visitador que enrole al médico.' USING ERRCODE = 'PV024';
  END IF;

  -- las invitaciones vencidas de ese correo dejan de bloquear (quedaban en 'pendiente'); una vigente bloquea
  UPDATE public.invitaciones_medico i
     SET estado = 'expirada'
   WHERE lower(i.email) = v.email AND i.estado = 'pendiente' AND i.expires_at <= now();
  IF EXISTS (SELECT 1 FROM public.invitaciones_medico i
              WHERE lower(i.email) = v.email AND i.estado = 'pendiente' AND i.expires_at > now()) THEN
    RAISE EXCEPTION 'Este correo ya tiene una invitación vigente de MED. Espera a que el médico la use o a que venza.' USING ERRCODE = 'PV025';
  END IF;

  -- especialidad: texto legacy = nombre del catalogo, en paralelo con el id (como InvitacionesMedicosPage)
  SELECT e.nombre INTO v_esp FROM public.especialidades e WHERE e.id = v.especialidad_id;

  INSERT INTO public.invitaciones_medico
    (pais_id, email, nombre_completo, telefono, especialidad, especialidad_id, clinica_id, created_by)
  VALUES
    (v.pais_id, v.email, v.nombre_completo, v.telefono, v_esp, v.especialidad_id, NULL, auth.uid())
  RETURNING id INTO v_inv;

  UPDATE public.solicitudes_alta_medico
     SET estado = 'invitada', invitacion_id = v_inv, revisado_por = auth.uid(), revisado_at = now(), updated_at = now()
   WHERE id = p_solicitud_id;

  -- aviso al visitador que la pidio (texto generico)
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
  VALUES (v.solicitado_por, 'solicitud_alta_invitada', 'Solicitud de alta aprobada',
          'Una de tus solicitudes de alta de médico fue aprobada. El médico recibirá una invitación por correo.',
          '/visitador/solicitudes', jsonb_build_object('solicitud_id', p_solicitud_id), v.pais_id)
  RETURNING id INTO v_nid;
  PERFORM private.push_notificar('notificaciones', v_nid::text);

  -- correo con el link (sale despues del COMMIT; si la transaccion aborta, no sale)
  PERFORM private.invitacion_email_notificar(v_inv);

  RETURN jsonb_build_object('ok', true, 'estado', 'invitada', 'invitacion_id', v_inv);
END;
$function$;

-- ---------------------------------------------------------------------------- 5: reenviar_solicitud_alta
CREATE FUNCTION public.reenviar_solicitud_alta(p_solicitud_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v          record;
  v_found    boolean;
  v_inv_est  text;
  v_esp      text;
  v_inv      uuid;
BEGIN
  SELECT s.pais_id, s.estado, s.email, s.nombre_completo, s.telefono, s.especialidad_id, s.invitacion_id INTO v
    FROM public.solicitudes_alta_medico s
   WHERE s.id = p_solicitud_id
   FOR UPDATE;
  v_found := FOUND;

  -- mismo gate que aprobar_solicitud_alta
  IF NOT v_found OR NOT COALESCE(private.puede_admin_pais(v.pais_id, ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'La solicitud no existe o no puedes gestionarla.' USING ERRCODE = 'PV023';
  END IF;
  IF v.estado <> 'invitada' THEN
    RAISE EXCEPTION 'La invitación de esta solicitud ya no se puede reenviar.' USING ERRCODE = 'PV022';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('solicitud_alta_medico:' || v.email, 0));

  -- la invitacion actual, bloqueada (registrar_medico_desde_invitacion la toma FOR UPDATE al registrar)
  IF v.invitacion_id IS NOT NULL THEN
    SELECT i.estado INTO v_inv_est FROM public.invitaciones_medico i WHERE i.id = v.invitacion_id FOR UPDATE;
    IF v_inv_est = 'usada' THEN
      RAISE EXCEPTION 'La invitación de esta solicitud ya no se puede reenviar.' USING ERRCODE = 'PV022';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v.email) THEN
    RAISE EXCEPTION 'Este correo ya tiene cuenta en MED: rechaza la solicitud o pide al visitador que enrole al médico.' USING ERRCODE = 'PV024';
  END IF;

  UPDATE public.invitaciones_medico
     SET estado = 'cancelada'
   WHERE id = v.invitacion_id;

  -- mismo bloque que aprobar: las vencidas de ese correo dejan de bloquear; otra vigente (no la recien cancelada) bloquea
  UPDATE public.invitaciones_medico i
     SET estado = 'expirada'
   WHERE lower(i.email) = v.email AND i.estado = 'pendiente' AND i.expires_at <= now();
  IF EXISTS (SELECT 1 FROM public.invitaciones_medico i
              WHERE lower(i.email) = v.email AND i.estado = 'pendiente' AND i.expires_at > now()
                AND i.id IS DISTINCT FROM v.invitacion_id) THEN
    RAISE EXCEPTION 'Este correo ya tiene una invitación vigente de MED. Espera a que el médico la use o a que venza.' USING ERRCODE = 'PV025';
  END IF;

  SELECT e.nombre INTO v_esp FROM public.especialidades e WHERE e.id = v.especialidad_id;

  INSERT INTO public.invitaciones_medico
    (pais_id, email, nombre_completo, telefono, especialidad, especialidad_id, clinica_id, created_by)
  VALUES
    (v.pais_id, v.email, v.nombre_completo, v.telefono, v_esp, v.especialidad_id, NULL, auth.uid())
  RETURNING id INTO v_inv;

  UPDATE public.solicitudes_alta_medico
     SET invitacion_id = v_inv, updated_at = now()
   WHERE id = p_solicitud_id;

  PERFORM private.invitacion_email_notificar(v_inv);

  RETURN jsonb_build_object('ok', true, 'estado', 'invitada', 'invitacion_id', v_inv);
END;
$function$;

-- ---------------------------------------------------------------------------- 6: solicitar_alta_medico (misma firma)
CREATE OR REPLACE FUNCTION public.solicitar_alta_medico(p_nombre text, p_email text, p_telefono text, p_especialidad_id uuid, p_numero_colegiado text, p_nombre_clinica text, p_autorizado boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_empresa    uuid;
  v_tipo       text;
  v_rol        text;
  v_pais       uuid;
  v_nombre     text;
  v_email      text;
  v_telefono   text;
  v_colegiado  text;
  v_clinica    text;
  v_medico     uuid;
  v_id         uuid;
  v_nid        uuid;
  v_avisados   int := 0;
  rec          record;
BEGIN
  -- 1) Visitador activo (empresa derivada de la sesion). Mismos gates y mensajes que enrolar_medico.
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  SELECT ep.tipo::text INTO v_tipo FROM public.empresas_proveedoras ep WHERE ep.id = v_empresa;
  IF v_tipo IS DISTINCT FROM 'laboratorio_farmaceutico' THEN
    RAISE EXCEPTION 'Solo un laboratorio farmacéutico puede enrolar médicos.' USING ERRCODE = 'PV016';
  END IF;

  v_rol := public.mi_rol_proveedor();
  IF v_rol IS NULL OR v_rol NOT IN ('admin', 'supervisor', 'visitador_medico') THEN
    RAISE EXCEPTION 'Tu rol en la empresa no te permite enrolar médicos.' USING ERRCODE = 'PV017';
  END IF;

  IF NOT COALESCE(private.empresa_tiene_capacidad(v_empresa, 'enrolamiento'), false) THEN
    RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de enrolamiento. Contacta a soporte para activarlo.' USING ERRCODE = 'PV014';
  END IF;

  -- 2) Pais de la solicitud = el del visitador, con un plan de visitador vigente de su empresa en ese pais
  --    (mismo criterio de vigencia que private.visitador_ve_medico).
  v_pais := private.mi_pais();
  IF v_pais IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.planes_visitador_contratados pvc
        WHERE pvc.empresa_id = v_empresa
          AND pvc.pais_id = v_pais
          AND pvc.estado = 'activo'
          AND CURRENT_DATE BETWEEN pvc.fecha_inicio AND pvc.fecha_fin) THEN
    RAISE EXCEPTION 'No tienes un plan activo que cubra tu país.' USING ERRCODE = 'PV011';
  END IF;

  -- 3) Autorizacion del medico
  IF p_autorizado IS NOT TRUE THEN
    RAISE EXCEPTION 'Necesitas la autorización del médico para solicitar su alta.' USING ERRCODE = 'PV018';
  END IF;

  -- 4) Datos (vacio = sin dato en los opcionales)
  v_nombre    := btrim(p_nombre);
  v_email     := lower(btrim(p_email));
  v_telefono  := NULLIF(btrim(p_telefono), '');
  v_colegiado := NULLIF(btrim(p_numero_colegiado), '');
  v_clinica   := NULLIF(btrim(p_nombre_clinica), '');
  IF v_nombre IS NULL OR char_length(v_nombre) NOT BETWEEN 3 AND 150 THEN
    RAISE EXCEPTION 'El nombre del médico debe tener entre 3 y 150 caracteres.' USING ERRCODE = 'PV019';
  END IF;
  IF v_email IS NULL OR char_length(v_email) > 254 OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'El correo del médico no es válido.' USING ERRCODE = 'PV019';
  END IF;
  IF v_telefono IS NOT NULL AND (char_length(v_telefono) > 30
     OR char_length(regexp_replace(v_telefono, '[^0-9]', '', 'g')) NOT BETWEEN 7 AND 15) THEN
    RAISE EXCEPTION 'El teléfono debe tener entre 7 y 15 dígitos.' USING ERRCODE = 'PV019';
  END IF;
  IF p_especialidad_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.especialidades e WHERE e.id = p_especialidad_id AND e.activo) THEN
    RAISE EXCEPTION 'La especialidad elegida no existe.' USING ERRCODE = 'PV019';
  END IF;
  IF v_colegiado IS NOT NULL AND char_length(v_colegiado) > 30 THEN
    RAISE EXCEPTION 'El número de colegiado no puede tener más de 30 caracteres.' USING ERRCODE = 'PV019';
  END IF;
  IF v_clinica IS NOT NULL AND char_length(v_clinica) > 150 THEN
    RAISE EXCEPTION 'El nombre de la clínica no puede tener más de 150 caracteres.' USING ERRCODE = 'PV019';
  END IF;

  -- 5) Serializa por correo normalizado (dos visitadores con el mismo medico a la vez)
  PERFORM pg_advisory_xact_lock(hashtextextended('solicitud_alta_medico:' || v_email, 0));

  -- 6) El correo ya existe en MED: si es un medico activo de este pais se ofrece enrolarlo directo (sin crear nada);
  --    si es cualquier otra cuenta, error generico (no se revela que tipo de cuenta es).
  IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v_email) THEN
    SELECT p.id INTO v_medico
      FROM auth.users u
      JOIN public.perfiles p ON p.id = u.id
      JOIN public.medicos m ON m.id = p.id
     WHERE lower(u.email) = v_email
       AND p.rol = 'medico'
       AND p.activo IS TRUE
       AND p.pais_id = v_pais
     LIMIT 1;
    IF v_medico IS NOT NULL THEN
      RETURN jsonb_build_object('estado', 'existe', 'medico_id', v_medico);
    END IF;
    RAISE EXCEPTION 'No puedes solicitar el alta con este correo.' USING ERRCODE = 'PV020';
  END IF;

  -- 7) Una sola solicitud en curso por medico, de cualquier empresa (sin nombrarla)
  IF EXISTS (SELECT 1 FROM public.solicitudes_alta_medico s
              WHERE s.email = v_email AND s.estado IN ('pendiente', 'invitada')) THEN
    RAISE EXCEPTION 'Este médico ya tiene una solicitud en curso.' USING ERRCODE = 'PV021';
  END IF;

  -- 7b) Ni una invitacion vigente de MED para ese correo, de cualquier origen (mig 378)
  IF EXISTS (SELECT 1 FROM public.invitaciones_medico i
              WHERE lower(i.email) = v_email AND i.estado = 'pendiente' AND i.expires_at > now()) THEN
    RAISE EXCEPTION 'Este médico ya tiene una solicitud en curso.' USING ERRCODE = 'PV021';
  END IF;

  BEGIN
    INSERT INTO public.solicitudes_alta_medico
      (empresa_id, solicitado_por, pais_id, nombre_completo, email, telefono, especialidad_id, numero_colegiado,
       nombre_clinica, autorizacion_medico, autorizacion_at)
    VALUES
      (v_empresa, auth.uid(), v_pais, v_nombre, v_email, v_telefono, p_especialidad_id, v_colegiado,
       v_clinica, true, now())
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Este médico ya tiene una solicitud en curso.' USING ERRCODE = 'PV021';
  END;

  -- 8) Aviso a los admin de pais activos del pais; si no hay ninguno, a los super_admin activos.
  --    Texto generico: sin datos del medico (el push sale del servidor).
  FOR rec IN SELECT p.id FROM public.perfiles p
              WHERE p.rol = 'admin_pais' AND p.activo IS TRUE AND p.pais_id = v_pais LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
    VALUES (rec.id, 'solicitud_alta_medico', 'Nueva solicitud de alta de médico',
            'Un laboratorio solicitó el alta de un médico. Revísala en la bandeja de solicitudes.',
            '/admin-ezpay/pais/' || v_pais::text || '/solicitudes-alta-medicos',
            jsonb_build_object('solicitud_id', v_id), v_pais)
    RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
    v_avisados := v_avisados + 1;
  END LOOP;
  IF v_avisados = 0 THEN
    FOR rec IN SELECT p.id FROM public.perfiles p WHERE p.rol = 'super_admin' AND p.activo IS TRUE LOOP
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
      VALUES (rec.id, 'solicitud_alta_medico', 'Nueva solicitud de alta de médico',
              'Un laboratorio solicitó el alta de un médico. Revísala en la bandeja de solicitudes.',
              '/admin-ezpay/pais/' || v_pais::text || '/solicitudes-alta-medicos',
              jsonb_build_object('solicitud_id', v_id), v_pais)
      RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('estado', 'creada', 'solicitud_id', v_id);
END;
$function$;

-- ---------------------------------------------------------------------------- 7: ACL
-- RPCs: solo authenticated y service_role (sin PUBLIC ni anon). solicitar_alta_medico conserva la suya (OR REPLACE).
REVOKE ALL ON FUNCTION public.aprobar_solicitud_alta(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reenviar_solicitud_alta(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aprobar_solicitud_alta(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reenviar_solicitud_alta(uuid) TO authenticated, service_role;
-- helper de private: solo postgres (lo llaman las RPCs DEFINER)
REVOKE ALL ON FUNCTION private.invitacion_email_notificar(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- 8: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text; r_act record; r_ini record;
BEGIN
  -- columna nueva: timestamptz, nullable, sin default; tabla con la misma ACL y sin privilegios por columna
  v := (SELECT format_type(a.atttypid, a.atttypmod)||'|'||(NOT a.attnotnull)::text||'|'||a.atthasdef::text
          FROM pg_attribute a
         WHERE a.attrelid = 'public.invitaciones_medico'::regclass AND a.attname = 'email_enviado_at' AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'timestamp with time zone|true|false' THEN bad := bad||'columna email_enviado_at '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.invitaciones_medico'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de invitaciones_medico '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.invitaciones_medico'::regclass AND a.attacl IS NOT NULL) THEN
    bad := bad||'invitaciones_medico con privilegios por columna; ';
  END IF;

  -- invitacion_edge_url: una fila, termina en /enviar-invitacion-medico y es email_edge_url con ese segmento cambiado
  -- (los mensajes nunca muestran valores)
  IF (SELECT count(*) FROM private.app_secrets s
       WHERE s.nombre = 'invitacion_edge_url' AND s.valor ~ '/enviar-invitacion-medico$'
         AND s.valor = (SELECT regexp_replace(e.valor, '/notificar-email$', '/enviar-invitacion-medico')
                          FROM private.app_secrets e WHERE e.nombre = 'email_edge_url')) <> 1 THEN
    bad := bad||'invitacion_edge_url ausente o no derivada de email_edge_url; ';
  END IF;

  -- las 4 funciones tocadas: DEFINER, search_path = '', ACL exacta, dueno postgres
  v := (SELECT string_agg(p.oid::regprocedure::text||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||
                          COALESCE(p.proacl::text, '-')||'|'||pg_get_userbyid(p.proowner), E'\n' ORDER BY p.oid::regprocedure::text COLLATE "C")
          FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.aprobar_solicitud_alta(uuid)'),
                         to_regprocedure('public.reenviar_solicitud_alta(uuid)'),
                         to_regprocedure('private.invitacion_email_notificar(uuid)'),
                         to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)')));
  IF v IS DISTINCT FROM
       'aprobar_solicitud_alta(uuid)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres'||E'\n'||
       'private.invitacion_email_notificar(uuid)|true|{"search_path=\"\""}|{postgres=X/postgres}|postgres'||E'\n'||
       'reenviar_solicitud_alta(uuid)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres'||E'\n'||
       'solicitar_alta_medico(text,text,text,uuid,text,text,boolean)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres' THEN
    bad := bad||'funciones (DEFINER/config/ACL/dueno): '||COALESCE(v, '-')||'; ';
  END IF;
  -- sin sobrecargas
  IF (SELECT count(*) FROM pg_proc p
       WHERE p.proname IN ('aprobar_solicitud_alta', 'reenviar_solicitud_alta', 'invitacion_email_notificar', 'solicitar_alta_medico')) <> 4 THEN
    bad := bad||'sobrecargas de las funciones tocadas; ';
  END IF;
  -- md5(prosrc) de las 4 (calculado sobre el archivo, sin CR)
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.aprobar_solicitud_alta(uuid)'),
                         to_regprocedure('public.reenviar_solicitud_alta(uuid)'),
                         to_regprocedure('private.invitacion_email_notificar(uuid)'),
                         to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)')));
  IF v IS DISTINCT FROM 'e7a2bea305a4f4dfe564f7b14157835b,10bf2ebc64ea42d9409fe7dd495f429b,d34babc6bffa17257b36d849e1fd7f2c,f0d28f9cdc70b277c36a5b337cc0daf5' THEN
    bad := bad||'md5 de las funciones tocadas '||COALESCE(v, '-')||'; ';
  END IF;
  -- las otras 3 RPCs de la 377, sin cambio
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.cancelar_solicitud_alta(uuid)'),
                         to_regprocedure('public.rechazar_solicitud_alta(uuid,text)'),
                         to_regprocedure('public.listar_solicitudes_alta(text)')));
  IF v IS DISTINCT FROM '34ff13a23b4681dddd44118b7b2dc1e1,90b37826b44f1b7e18813f9916867286,a028473675bea99b8b4bc89108b5ac47' THEN
    bad := bad||'md5 de cancelar/listar/rechazar '||COALESCE(v, '-')||'; ';
  END IF;
  -- PV024-PV025 solo en aprobar y reenviar
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p WHERE p.prosrc ~ 'PV02[45]');
  IF v IS DISTINCT FROM 'aprobar_solicitud_alta(uuid), reenviar_solicitud_alta(uuid)' THEN
    bad := bad||'PV024-PV025 en ['||COALESCE(v, 'ninguna')||']; ';
  END IF;

  -- resto de las funciones intacto (huella del paso 0, excluyendo las 4 tocadas)
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO r_act
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid NOT IN ('public.aprobar_solicitud_alta(uuid)'::regprocedure,
                       'public.reenviar_solicitud_alta(uuid)'::regprocedure,
                       'private.invitacion_email_notificar(uuid)'::regprocedure,
                       'public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure);
  SELECT t.h, t.n INTO r_ini FROM pg_temp.mig378_huella t;
  IF r_act.h IS DISTINCT FROM r_ini.h OR r_act.n IS DISTINCT FROM r_ini.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(r_act.h, '-')||'/'||COALESCE(r_act.n::text, '-')||' vs '||COALESCE(r_ini.h, '-')||'/'||COALESCE(r_ini.n::text, '-')||'; ';
  END IF;

  -- huellas globales: policies y ACL de relaciones sin cambio; ACL de funciones igual excluyendo las 3 nuevas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cfb5d7632f071052d491e02a6a5e0932 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9da6a3c4ca75cd58b3a3053603bf03fe 2406' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.oid NOT IN ('public.aprobar_solicitud_alta(uuid)'::regprocedure,
                           'public.reenviar_solicitud_alta(uuid)'::regprocedure,
                           'private.invitacion_email_notificar(uuid)'::regprocedure)) y);
  IF v IS DISTINCT FROM '8d5290543497cb8984e6d9b289176818 396' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG378_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
