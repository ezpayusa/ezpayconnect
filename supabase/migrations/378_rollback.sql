-- ############################################################################################
-- 378_rollback - deshace la 378: aprobar/reenviar, invitacion_email_notificar, invitacion_edge_url,
--                email_enviado_at y el cambio de solicitar_alta_medico
-- ############################################################################################
-- Precondicion: estado post-378 (md5(prosrc) de las 4 funciones tocadas, la columna y la fila de app_secrets) y
--   NINGUNA invitacion con email_enviado_at: si alguna tiene el correo marcado, el rollback aborta (decidir antes que
--   hacer con ese dato; no se borra en un rollback).
-- Lo que NO se toca: las invitaciones creadas por aprobar/reenviar (filas validas del esquema de la 377), las
--   solicitudes en 'invitada' con su invitacion_id (estado valido de la 377) y las notificaciones ya enviadas
--   (tipo solicitud_alta_invitada, sin FK).
-- solicitar_alta_medico vuelve EXACTA: el cuerpo de abajo es el pg_get_functiondef vivo medido en prod el
--   20-oct-2026 (md5(prosrc) 4979da5532a3ddd08a466929bbfe27c7); el autochequeo lo exige.
-- Autochequeo: las 3 funciones nuevas, la fila y la columna no existen, PV024-PV025 sin uso, y las huellas vuelven a
--   las post-377: funciones (cuerpo, DEFINER, config, ACL) 79ac69a1e89865e79424a09abc36ab58/396, ACL de funciones
--   8d529054.../396, policies cfb5d763.../311, ACL de relaciones de public 9da6a3c4.../2406.
-- Orden global: 378_rollback -> 377_rollback -> 376_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text; n bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.invitaciones_medico'::regclass
                    AND a.attname = 'email_enviado_at' AND NOT a.attisdropped) THEN
    RAISE EXCEPTION 'MIG378_ROLLBACK_PRE FALLA:la columna email_enviado_at no existe; ';
  END IF;
  -- bloquea la escritura de la tabla antes de contar: nadie marca un correo entre el conteo y el DROP COLUMN
  EXECUTE 'LOCK TABLE public.invitaciones_medico IN SHARE ROW EXCLUSIVE MODE';
  EXECUTE 'SELECT count(*) FROM public.invitaciones_medico WHERE email_enviado_at IS NOT NULL' INTO n;
  IF n <> 0 THEN bad := bad||n||' invitaciones con email_enviado_at; '; END IF;

  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.aprobar_solicitud_alta(uuid)'),
                         to_regprocedure('public.reenviar_solicitud_alta(uuid)'),
                         to_regprocedure('private.invitacion_email_notificar(uuid)'),
                         to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)')));
  IF v IS DISTINCT FROM 'e7a2bea305a4f4dfe564f7b14157835b,10bf2ebc64ea42d9409fe7dd495f429b,d34babc6bffa17257b36d849e1fd7f2c,f0d28f9cdc70b277c36a5b337cc0daf5' THEN
    bad := bad||'md5 de las 4 funciones de la 378 '||COALESCE(v, '-')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p
       WHERE p.proname IN ('aprobar_solicitud_alta', 'reenviar_solicitud_alta', 'invitacion_email_notificar', 'solicitar_alta_medico')) <> 4 THEN
    bad := bad||'sobrecargas de las funciones de la 378; ';
  END IF;
  IF (SELECT count(*) FROM private.app_secrets s WHERE s.nombre = 'invitacion_edge_url') <> 1 THEN
    bad := bad||'invitacion_edge_url ausente; ';
  END IF;
  -- nada fuera de la 378 depende de las funciones nuevas ni de la columna
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE (p.prosrc ~ 'invitacion_email_notificar|aprobar_solicitud_alta|reenviar_solicitud_alta|email_enviado_at')
           AND p.oid NOT IN (to_regprocedure('public.aprobar_solicitud_alta(uuid)'),
                             to_regprocedure('public.reenviar_solicitud_alta(uuid)'),
                             to_regprocedure('private.invitacion_email_notificar(uuid)')));
  IF v IS NOT NULL THEN bad := bad||'funciones que usan objetos de la 378 ['||v||']; '; END IF;
  v := (SELECT string_agg(DISTINCT d.classid::regclass::text||':'||d.objid, ', ') FROM pg_depend d
          JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
         WHERE d.refobjid = 'public.invitaciones_medico'::regclass AND a.attname = 'email_enviado_at'
           AND d.classid <> 'pg_description'::regclass);
  IF v IS NOT NULL THEN bad := bad||'objetos que dependen de email_enviado_at ['||v||']; '; END IF;

  -- resto de las funciones = huella post-377 (excluyendo las 4 de la 378)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN ('public.aprobar_solicitud_alta(uuid)'::regprocedure,
                             'public.reenviar_solicitud_alta(uuid)'::regprocedure,
                             'private.invitacion_email_notificar(uuid)'::regprocedure,
                             'public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure));
  IF v IS DISTINCT FROM '4032afa1fb3adcda8b4079e575e8f867 395' THEN bad := bad||'huella del resto de las funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG378_ROLLBACK_PRE FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: deshacer
DROP FUNCTION public.aprobar_solicitud_alta(uuid);
DROP FUNCTION public.reenviar_solicitud_alta(uuid);
DROP FUNCTION private.invitacion_email_notificar(uuid);

-- solicitar_alta_medico: pg_get_functiondef vivo pre-378 (OR REPLACE conserva su ACL)
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

DELETE FROM private.app_secrets WHERE nombre = 'invitacion_edge_url';

ALTER TABLE public.invitaciones_medico DROP COLUMN email_enviado_at;

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.proname IN ('aprobar_solicitud_alta', 'reenviar_solicitud_alta', 'invitacion_email_notificar'));
  IF v IS NOT NULL THEN bad := bad||'funciones que siguen existiendo ['||v||']; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'));
  IF v IS DISTINCT FROM '4979da5532a3ddd08a466929bbfe27c7' THEN bad := bad||'solicitar_alta_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM private.app_secrets s WHERE s.nombre = 'invitacion_edge_url') THEN
    bad := bad||'invitacion_edge_url sigue existiendo; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.invitaciones_medico'::regclass
                AND a.attname = 'email_enviado_at' AND NOT a.attisdropped) THEN
    bad := bad||'la columna email_enviado_at sigue existiendo; ';
  END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.invitaciones_medico'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de invitaciones_medico '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc ~ 'PV02[45]');
  IF v IS NOT NULL THEN bad := bad||'PV024-PV025 en ['||v||']; '; END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '79ac69a1e89865e79424a09abc36ab58 396' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG378_ROLLBACK_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
