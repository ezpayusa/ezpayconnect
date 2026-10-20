-- ############################################################################################
-- 377 - solicitudes de alta de medico por el visitador (paso 4 de la familia enrolamiento)
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\recon_alta\ y C:\tmp\mig377\r1-r7.sql). Estado vivo medido:
--   - public.solicitudes_alta_medico no existe; ningun nombre de las 4 RPCs esta tomado.
--   - md5(prosrc): enrolar_medico 58e441f3a68a5f80645f9b8f0452ffca, private.visitador_ve_medico
--     92275e4d96bc7f601f937dbe24d5ee34, private.puede_admin_pais 8bc2928e369d98e305355440df8b52ac, private.push_notificar
--     90e6e8ec7eb37240e400a7c5768a8997, private.mi_pais 64ec50953f8d351c300c60a23b05f0a6.
--   - PV018-PV029 sin uso en prod ni en el repo (en uso: PV001-PV003, PV010-PV017).
--   - Huellas post-376: ACL de funciones 9c59aeca.../392, policies 8a8dc5cf.../309, ACL de relaciones de public
--     1889d1d8.../2393; huella completa de funciones (cuerpo, DEFINER, config, ACL) 58ec02c714546c1d5a0f2a90e5aa2509/392.
--   - Predicado vivo de "Proveedor ve visitas segun rol" (visitas_agendadas): empresa_id = mi_empresa_proveedor() AND
--     (mi_rol_proveedor() IN (admin, editor) OR cuenta_proveedor_id = auth.uid() OR propuesta_por = auth.uid() OR
--     (mi_rol_proveedor() = 'supervisor' AND supervisa_cuenta_proveedor(cuenta_proveedor_id))). Aca la cuenta es
--     solicitado_por y no hay propuesta_por.
--   - Default privileges de postgres en public: tabla nueva -> authenticated arwd, service_role arwdDxtm, anon nada.
--
-- Que crea:
--   1. public.solicitudes_alta_medico: la solicitud que carga el visitador (datos del medico + autorizacion). Estados
--      pendiente -> invitada (378) -> registrada (379); o rechazada (admin de pais) / cancelada (laboratorio).
--      UNIQUE parcial por email en pendiente/invitada: un medico tiene a lo sumo una solicitud en curso, de cualquier
--      empresa. RLS ON; authenticated solo SELECT (2 policies SELECT, 0 de escritura: toda escritura va por RPC);
--      service_role SELECT/INSERT/UPDATE/DELETE (regla 3 de GRANTs explicitos); anon nada.
--   2. RPCs DEFINER, search_path = '', EXECUTE solo authenticated y service_role:
--      solicitar_alta_medico, cancelar_solicitud_alta, rechazar_solicitud_alta, listar_solicitudes_alta.
--      La aprobacion (crear la invitacion precargada) es la 378 y el enrolamiento al registrarse la 379.
--
-- Errcodes: reusa PV010/PV011/PV014/PV016/PV017 con el mismo significado que en enrolar_medico (no eres visitador
--   activo / sin plan activo en el pais / sin modulo de enrolamiento / no es laboratorio farmaceutico / rol sin
--   permiso). Nuevos:
--   PV018 falta la autorizacion del medico; PV019 dato invalido (mensaje por campo, tambien el motivo del rechazo);
--   PV020 el correo no se puede usar (existe en MED y no es un medico activo de tu pais; mensaje generico);
--   PV021 el medico ya tiene una solicitud en curso (sin nombrar a la empresa); PV022 la solicitud ya no esta
--   pendiente; PV023 la solicitud no existe o no puedes gestionarla (mismo error para los dos casos).
--   Proximo libre: PV024.
--
-- md5(prosrc) de las funciones nuevas (calculado sobre este archivo, sin CR; el autochequeo lo exige):
--   solicitar_alta_medico 4979da5532a3ddd08a466929bbfe27c7, cancelar_solicitud_alta 34ff13a23b4681dddd44118b7b2dc1e1,
--   rechazar_solicitud_alta a028473675bea99b8b4bc89108b5ac47, listar_solicitudes_alta 90b37826b44f1b7e18813f9916867286.
--
-- Avisos: in-app (public.notificaciones) + private.push_notificar en la misma transaccion (best-effort).
--   solicitar -> cada admin_pais activo del pais; si no hay ninguno, cada super_admin activo. Texto generico, sin datos
--   del medico (el push sale del servidor). accion_url /admin-ezpay/pais/<pais_id>/solicitudes-alta-medicos.
--   rechazar -> al visitador que la pidio, accion_url /visitador/solicitudes.
--
-- Sin cambios a funciones existentes, policies existentes ni ACL de otras relaciones: el autochequeo exige las huellas
--   previas excluyendo la tabla y las 4 funciones nuevas.
--
-- Front: nada todavia (PWA del visitador y bandeja del admin de pais van aparte). PV018-PV023 sin mapear.
--
-- Rollback: 377_rollback.sql (aborta si la tabla tiene filas). Orden global: 377_rollback -> 376_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regclass('public.solicitudes_alta_medico') IS NOT NULL THEN bad := bad||'la tabla solicitudes_alta_medico ya existe; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.proname IN ('solicitar_alta_medico', 'cancelar_solicitud_alta', 'rechazar_solicitud_alta', 'listar_solicitudes_alta'));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existentes ['||v||']; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.enrolar_medico(uuid)'));
  IF v IS DISTINCT FROM '58e441f3a68a5f80645f9b8f0452ffca' THEN bad := bad||'enrolar_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.visitador_ve_medico(uuid)'));
  IF v IS DISTINCT FROM '92275e4d96bc7f601f937dbe24d5ee34' THEN bad := bad||'visitador_ve_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.puede_admin_pais(uuid,text[])'));
  IF v IS DISTINCT FROM '8bc2928e369d98e305355440df8b52ac' THEN bad := bad||'puede_admin_pais md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.push_notificar(text,text)'));
  IF v IS DISTINCT FROM '90e6e8ec7eb37240e400a7c5768a8997' THEN bad := bad||'push_notificar md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.mi_pais()'));
  IF v IS DISTINCT FROM '64ec50953f8d351c300c60a23b05f0a6' THEN bad := bad||'mi_pais md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc ~ 'PV0(1[89]|2[0-3])');
  IF v IS NOT NULL THEN bad := bad||'PV018-PV023 en uso en ['||v||']; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  -- huella completa de funciones (cuerpo, DEFINER, config, ACL), medida en prod el 20-oct-2026
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '58ec02c714546c1d5a0f2a90e5aa2509 392' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG377_PRE FALLA:%', bad; END IF;

  -- huella de TODAS las funciones de public/private (todavia sin las 4 nuevas): el autochequeo exige que, excluyendo
  -- las 4 nuevas, quede igual (ningun efecto colateral sobre otra funcion)
  CREATE TEMP TABLE mig377_huella ON COMMIT DROP AS
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace);
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: tabla
CREATE TABLE public.solicitudes_alta_medico (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          uuid        NOT NULL REFERENCES public.empresas_proveedoras(id) ON DELETE RESTRICT,
  solicitado_por      uuid        NOT NULL REFERENCES public.cuentas_proveedor(id) ON DELETE RESTRICT,
  pais_id             uuid        NOT NULL REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  nombre_completo     text        NOT NULL,
  email               text        NOT NULL,
  telefono            text,
  especialidad_id     uuid        REFERENCES public.especialidades(id) ON DELETE RESTRICT,
  numero_colegiado    text,
  nombre_clinica      text,
  autorizacion_medico boolean     NOT NULL,
  autorizacion_at     timestamptz NOT NULL DEFAULT now(),
  estado              text        NOT NULL DEFAULT 'pendiente',
  motivo_rechazo      text,
  revisado_por        uuid        REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  revisado_at         timestamptz,
  invitacion_id       uuid        REFERENCES public.invitaciones_medico(id) ON DELETE RESTRICT,  -- lo llena la 378
  medico_id           uuid        REFERENCES public.medicos(id) ON DELETE RESTRICT,              -- lo llena la 379
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT solicitudes_alta_medico_nombre_check
    CHECK (char_length(btrim(nombre_completo)) BETWEEN 3 AND 150),
  CONSTRAINT solicitudes_alta_medico_email_check
    CHECK (email = lower(btrim(email)) AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  CONSTRAINT solicitudes_alta_medico_autorizacion_check
    CHECK (autorizacion_medico = true),
  CONSTRAINT solicitudes_alta_medico_estado_check
    CHECK (estado IN ('pendiente', 'invitada', 'registrada', 'rechazada', 'cancelada')),
  CONSTRAINT solicitudes_alta_medico_motivo_check
    CHECK (estado <> 'rechazada' OR char_length(btrim(COALESCE(motivo_rechazo, ''))) >= 5)
);

COMMENT ON TABLE public.solicitudes_alta_medico IS
  'Solicitudes de alta de medico cargadas por un visitador (mig 377). Escritura solo por RPC DEFINER.';

-- un medico (por correo normalizado) tiene a lo sumo una solicitud en curso, de cualquier empresa
CREATE UNIQUE INDEX solicitudes_alta_medico_email_en_curso_uniq
  ON public.solicitudes_alta_medico (email) WHERE estado IN ('pendiente', 'invitada');
CREATE INDEX solicitudes_alta_medico_pais_estado_idx    ON public.solicitudes_alta_medico (pais_id, estado);
CREATE INDEX solicitudes_alta_medico_empresa_estado_idx ON public.solicitudes_alta_medico (empresa_id, estado);

ALTER TABLE public.solicitudes_alta_medico ENABLE ROW LEVEL SECURITY;

-- Grants explicitos: authenticated solo SELECT (toda escritura por RPC DEFINER), service_role SIUD (regla 3), anon nada.
REVOKE ALL ON TABLE public.solicitudes_alta_medico FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.solicitudes_alta_medico TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.solicitudes_alta_medico TO service_role;

-- (a) laboratorio: mismo predicado que "Proveedor ve visitas segun rol" (la cuenta es solicitado_por)
CREATE POLICY solicitudes_alta_medico_select_laboratorio ON public.solicitudes_alta_medico
  FOR SELECT TO authenticated
  USING (
    empresa_id = public.mi_empresa_proveedor()
    AND (
         public.mi_rol_proveedor() = ANY (ARRAY['admin', 'editor'])
      OR solicitado_por = auth.uid()
      OR (public.mi_rol_proveedor() = 'supervisor' AND public.supervisa_cuenta_proveedor(solicitado_por))
    )
  );

-- (b) admin de pais del pais de la solicitud, o super_admin (fail-closed)
CREATE POLICY solicitudes_alta_medico_select_admin_pais ON public.solicitudes_alta_medico
  FOR SELECT TO authenticated
  USING (COALESCE(private.puede_admin_pais(pais_id, ARRAY['super_admin']), false));

-- ---------------------------------------------------------------------------- 2a: solicitar_alta_medico
CREATE FUNCTION public.solicitar_alta_medico(p_nombre text, p_email text, p_telefono text, p_especialidad_id uuid, p_numero_colegiado text, p_nombre_clinica text, p_autorizado boolean)
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

-- ---------------------------------------------------------------------------- 2b: cancelar_solicitud_alta
CREATE FUNCTION public.cancelar_solicitud_alta(p_solicitud_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v       record;
  v_found boolean;
BEGIN
  SELECT s.empresa_id, s.solicitado_por, s.estado INTO v
    FROM public.solicitudes_alta_medico s
   WHERE s.id = p_solicitud_id
   FOR UPDATE;
  v_found := FOUND;

  -- la cuenta que la pidio o un admin de esa empresa (cuenta y empresa activas); inexistente y ajena dan el mismo error
  IF NOT v_found OR NOT COALESCE(
       v.empresa_id = public.mi_empresa_proveedor()
       AND (v.solicitado_por = auth.uid() OR public.mi_rol_proveedor() = 'admin'), false) THEN
    RAISE EXCEPTION 'La solicitud no existe o no puedes gestionarla.' USING ERRCODE = 'PV023';
  END IF;
  IF v.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'La solicitud ya no está pendiente.' USING ERRCODE = 'PV022';
  END IF;

  UPDATE public.solicitudes_alta_medico
     SET estado = 'cancelada', updated_at = now()
   WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok', true, 'estado', 'cancelada');
END;
$function$;

-- ---------------------------------------------------------------------------- 2c: rechazar_solicitud_alta
CREATE FUNCTION public.rechazar_solicitud_alta(p_solicitud_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v        record;
  v_found  boolean;
  v_motivo text;
  v_nid    uuid;
BEGIN
  SELECT s.pais_id, s.solicitado_por, s.estado INTO v
    FROM public.solicitudes_alta_medico s
   WHERE s.id = p_solicitud_id
   FOR UPDATE;
  v_found := FOUND;

  -- admin de pais del pais de la solicitud o super_admin (fail-closed); inexistente y ajena dan el mismo error
  IF NOT v_found OR NOT COALESCE(private.puede_admin_pais(v.pais_id, ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'La solicitud no existe o no puedes gestionarla.' USING ERRCODE = 'PV023';
  END IF;

  v_motivo := btrim(p_motivo);
  IF v_motivo IS NULL OR char_length(v_motivo) NOT BETWEEN 5 AND 500 THEN
    RAISE EXCEPTION 'El motivo del rechazo debe tener entre 5 y 500 caracteres.' USING ERRCODE = 'PV019';
  END IF;
  IF v.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'La solicitud ya no está pendiente.' USING ERRCODE = 'PV022';
  END IF;

  UPDATE public.solicitudes_alta_medico
     SET estado = 'rechazada', motivo_rechazo = v_motivo, revisado_por = auth.uid(), revisado_at = now(),
         updated_at = now()
   WHERE id = p_solicitud_id;

  -- aviso al visitador que la pidio (texto generico; el motivo se ve en Mis solicitudes)
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
  VALUES (v.solicitado_por, 'solicitud_alta_rechazada', 'Solicitud de alta rechazada',
          'Una de tus solicitudes de alta de médico fue rechazada. Revisa el motivo en Mis solicitudes.',
          '/visitador/solicitudes', jsonb_build_object('solicitud_id', p_solicitud_id), v.pais_id)
  RETURNING id INTO v_nid;
  PERFORM private.push_notificar('notificaciones', v_nid::text);

  RETURN jsonb_build_object('ok', true, 'estado', 'rechazada');
END;
$function$;

-- ---------------------------------------------------------------------------- 2d: listar_solicitudes_alta
CREATE FUNCTION public.listar_solicitudes_alta(p_estado text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, empresa_id uuid, empresa_nombre text, solicitado_por uuid, solicitante_nombre text, pais_id uuid, nombre_completo text, email text, telefono text, especialidad_id uuid, especialidad_nombre text, numero_colegiado text, nombre_clinica text, autorizacion_at timestamp with time zone, estado text, motivo_rechazo text, revisado_at timestamp with time zone, invitacion_id uuid, medico_id uuid, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- misma visibilidad que las 2 policies SELECT de la tabla; sin autoridad -> 0 filas
  SELECT s.id, s.empresa_id, ep.nombre_empresa, s.solicitado_por, cp.nombre_completo, s.pais_id, s.nombre_completo,
         s.email, s.telefono, s.especialidad_id, es.nombre, s.numero_colegiado, s.nombre_clinica, s.autorizacion_at,
         s.estado, s.motivo_rechazo, s.revisado_at, s.invitacion_id, s.medico_id, s.created_at, s.updated_at
    FROM public.solicitudes_alta_medico s
    JOIN public.empresas_proveedoras ep ON ep.id = s.empresa_id
    JOIN public.cuentas_proveedor cp ON cp.id = s.solicitado_por
    LEFT JOIN public.especialidades es ON es.id = s.especialidad_id
   WHERE (p_estado IS NULL OR s.estado = p_estado)
     AND (
          COALESCE(
            s.empresa_id = public.mi_empresa_proveedor()
            AND (
                 public.mi_rol_proveedor() = ANY (ARRAY['admin', 'editor'])
              OR s.solicitado_por = auth.uid()
              OR (public.mi_rol_proveedor() = 'supervisor' AND public.supervisa_cuenta_proveedor(s.solicitado_por))
            ), false)
       OR COALESCE(private.puede_admin_pais(s.pais_id, ARRAY['super_admin']), false)
     )
   ORDER BY (s.estado = 'pendiente') DESC, s.created_at DESC;
$function$;

-- ACL: solo authenticated y service_role (sin PUBLIC ni anon)
REVOKE ALL ON FUNCTION public.solicitar_alta_medico(text, text, text, uuid, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancelar_solicitud_alta(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rechazar_solicitud_alta(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.listar_solicitudes_alta(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.solicitar_alta_medico(text, text, text, uuid, text, text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancelar_solicitud_alta(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rechazar_solicitud_alta(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.listar_solicitudes_alta(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 3: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text; r_act record; r_ini record;
BEGIN
  -- tabla: RLS, ACL exacta, sin privilegios por columna
  IF NOT COALESCE((SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = to_regclass('public.solicitudes_alta_medico')), false) THEN
    bad := bad||'tabla sin RLS o inexistente; ';
  END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = to_regclass('public.solicitudes_alta_medico'));
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwd/postgres}' THEN
    bad := bad||'ACL de la tabla '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = to_regclass('public.solicitudes_alta_medico') AND a.attacl IS NOT NULL) THEN
    bad := bad||'privilegios por columna; ';
  END IF;
  IF has_table_privilege('anon', 'public.solicitudes_alta_medico', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
    bad := bad||'anon con privilegios; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.solicitudes_alta_medico', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
    bad := bad||'authenticated con escritura; ';
  END IF;

  -- policies: exactamente las 2 SELECT TO authenticated, permissive; 0 de escritura
  v := (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                          ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text, ', ' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = to_regclass('public.solicitudes_alta_medico'));
  IF v IS DISTINCT FROM 'solicitudes_alta_medico_select_admin_pais|r|true|{authenticated}, solicitudes_alta_medico_select_laboratorio|r|true|{authenticated}' THEN
    bad := bad||'policies '||COALESCE(v, '-')||'; ';
  END IF;

  -- CHECKs e indice unico parcial
  v := (SELECT string_agg(c.conname, ',' ORDER BY c.conname) FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.solicitudes_alta_medico') AND c.contype = 'c');
  IF v IS DISTINCT FROM 'solicitudes_alta_medico_autorizacion_check,solicitudes_alta_medico_email_check,solicitudes_alta_medico_estado_check,solicitudes_alta_medico_motivo_check,solicitudes_alta_medico_nombre_check' THEN
    bad := bad||'CHECKs '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(c.conname, ',' ORDER BY c.conname) FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.solicitudes_alta_medico') AND c.contype = 'f'
           AND pg_get_constraintdef(c.oid) LIKE '%ON DELETE RESTRICT');
  IF v IS DISTINCT FROM 'solicitudes_alta_medico_empresa_id_fkey,solicitudes_alta_medico_especialidad_id_fkey,solicitudes_alta_medico_invitacion_id_fkey,solicitudes_alta_medico_medico_id_fkey,solicitudes_alta_medico_pais_id_fkey,solicitudes_alta_medico_revisado_por_fkey,solicitudes_alta_medico_solicitado_por_fkey' THEN
    bad := bad||'FKs RESTRICT '||COALESCE(v, '-')||'; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_index i
                  WHERE i.indexrelid = to_regclass('public.solicitudes_alta_medico_email_en_curso_uniq')
                    AND i.indisunique AND i.indpred IS NOT NULL) THEN
    bad := bad||'falta el indice unico parcial por email; ';
  END IF;

  -- las 4 funciones: DEFINER, search_path = '', ACL exacta, dueno postgres
  v := (SELECT string_agg(p.oid::regprocedure::text||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||
                          COALESCE(p.proacl::text, '-')||'|'||pg_get_userbyid(p.proowner), E'\n' ORDER BY p.oid::regprocedure::text COLLATE "C")
          FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'),
                         to_regprocedure('public.cancelar_solicitud_alta(uuid)'),
                         to_regprocedure('public.rechazar_solicitud_alta(uuid,text)'),
                         to_regprocedure('public.listar_solicitudes_alta(text)')));
  IF v IS DISTINCT FROM
       'cancelar_solicitud_alta(uuid)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres'||E'\n'||
       'listar_solicitudes_alta(text)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres'||E'\n'||
       'rechazar_solicitud_alta(uuid,text)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres'||E'\n'||
       'solicitar_alta_medico(text,text,text,uuid,text,text,boolean)|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|postgres' THEN
    bad := bad||'funciones nuevas (DEFINER/config/ACL/dueno): '||COALESCE(v, '-')||'; ';
  END IF;
  -- md5(prosrc) de las 4 (calculado sobre el archivo, sin CR)
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'),
                         to_regprocedure('public.cancelar_solicitud_alta(uuid)'),
                         to_regprocedure('public.rechazar_solicitud_alta(uuid,text)'),
                         to_regprocedure('public.listar_solicitudes_alta(text)')));
  IF v IS DISTINCT FROM '34ff13a23b4681dddd44118b7b2dc1e1,90b37826b44f1b7e18813f9916867286,a028473675bea99b8b4bc89108b5ac47,4979da5532a3ddd08a466929bbfe27c7' THEN
    bad := bad||'md5 de las funciones nuevas '||COALESCE(v, '-')||'; ';
  END IF;
  -- PV018-PV023 solo en las funciones nuevas
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p WHERE p.prosrc ~ 'PV0(1[89]|2[0-3])');
  IF v IS DISTINCT FROM 'cancelar_solicitud_alta(uuid), rechazar_solicitud_alta(uuid,text), solicitar_alta_medico(text,text,text,uuid,text,text,boolean)' THEN
    bad := bad||'PV018-PV023 en ['||COALESCE(v, 'ninguna')||']; ';
  END IF;

  -- resto de las funciones intacto (huella del paso 0, excluyendo las 4 nuevas)
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO r_act
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid NOT IN ('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure,
                       'public.cancelar_solicitud_alta(uuid)'::regprocedure,
                       'public.rechazar_solicitud_alta(uuid,text)'::regprocedure,
                       'public.listar_solicitudes_alta(text)'::regprocedure);
  SELECT t.h, t.n INTO r_ini FROM pg_temp.mig377_huella t;
  IF r_act.h IS DISTINCT FROM r_ini.h OR r_act.n IS DISTINCT FROM r_ini.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(r_act.h, '-')||'/'||COALESCE(r_act.n::text, '-')||' vs '||COALESCE(r_ini.h, '-')||'/'||COALESCE(r_ini.n::text, '-')||'; ';
  END IF;

  -- huellas globales previas, excluyendo la tabla y las funciones nuevas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.solicitudes_alta_medico'::regclass) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')
       AND cl.oid <> 'public.solicitudes_alta_medico'::regclass) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.oid NOT IN ('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure,
                           'public.cancelar_solicitud_alta(uuid)'::regprocedure,
                           'public.rechazar_solicitud_alta(uuid,text)'::regprocedure,
                           'public.listar_solicitudes_alta(text)'::regprocedure)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG377_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
