-- 170 · Ola A — Consentimiento granular + Documentos del paciente (PHI).
-- Patrón DEFINER calcado de capturar_signo_vital/set_foto_paciente; bucket privado calcado de pacientes-fotos
-- (mig 168); confinamiento por clínica vía private.clinicas_del_usuario(); helper self del paciente
-- private.paciente_es_mio(bigint) (ata auth.uid()→pacientes.auth_user_id).
-- INVARIANTES: consentimientos es APPEND-ONLY (ninguna policy/RPC hace UPDATE/DELETE; revocar = nueva fila
-- concedido=false). Escrituras multi-rol SOLO por RPC DEFINER (lección Ola 1; NO policy INSERT directa).
-- SIN seed de permisos (Oscar carga texto legal después). NO se toca nada existente.

-- ============================================================
-- PIEZA 1 — Catálogo de permisos (estructura, SIN seed)
-- ============================================================
CREATE TABLE public.consentimiento_permisos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      text NOT NULL,                       -- ej. 'grabar_consulta'
  version     int  NOT NULL DEFAULT 1,
  etiqueta    text NOT NULL,                        -- visible al usuario
  texto_legal text NOT NULL,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (codigo, version)
);
ALTER TABLE public.consentimiento_permisos ENABLE ROW LEVEL SECURITY;

-- SELECT: todos los authenticated leen el catálogo.
DROP POLICY IF EXISTS cons_permisos_select ON public.consentimiento_permisos;
CREATE POLICY cons_permisos_select ON public.consentimiento_permisos
  FOR SELECT TO authenticated
  USING (true);

-- Escritura del catálogo: policy de super_admin (ALL). Queda INERTE para la app porque NO se otorga grant
-- de write a authenticated (abajo): se reactivará si en el futuro se agrega un RPC DEFINER de carga.
DROP POLICY IF EXISTS cons_permisos_admin ON public.consentimiento_permisos;
CREATE POLICY cons_permisos_admin ON public.consentimiento_permisos
  FOR ALL TO authenticated
  USING      (COALESCE(private.tiene_rol(ARRAY['super_admin']), false))
  WITH CHECK (COALESCE(private.tiene_rol(ARRAY['super_admin']), false));

-- Tabla NUEVA → nace limpia: solo SELECT para la app (Ola A solo LEE el catálogo). NADA de write a
-- authenticated (se evita el patrón grant-amplio que arrastramos como deuda). La carga de permisos
-- (texto legal) la hace el super_admin por SQL directo (service_role/postgres bypassan RLS y grants),
-- o por un RPC DEFINER futuro — NO por la app.
REVOKE ALL    ON public.consentimiento_permisos FROM anon;
GRANT  SELECT ON public.consentimiento_permisos TO authenticated;
-- Supabase tiene default privileges en el schema public que otorgan ALL a authenticated al crear cualquier
-- tabla. El GRANT SELECT de arriba es aditivo (no define el conjunto) → hay que REVOCAR lo ancho para nacer
-- limpio (solo SELECT). Las escrituras del catálogo van por SQL directo (service_role/postgres bypassan grants).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.consentimiento_permisos FROM authenticated;

-- ============================================================
-- PIEZA 2 — Registro de consentimientos (APPEND-ONLY)
-- ============================================================
CREATE TABLE public.consentimientos (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  paciente_id     bigint  NOT NULL REFERENCES public.pacientes(id),
  permiso_codigo  text    NOT NULL,
  permiso_version int     NOT NULL,
  concedido       boolean NOT NULL,
  via             text    NOT NULL CHECK (via IN ('app','presencial_firma','presencial_papel')),
  capturado_por   uuid,                              -- staff uid, o el propio paciente (auth.uid)
  documento_id    bigint,                            -- FK opcional al papel escaneado (FK añadida en PIEZA 3)
  created_at      timestamptz NOT NULL DEFAULT now()
);
-- "vigente = última" por (paciente, permiso).
CREATE INDEX idx_consentimientos_vigente
  ON public.consentimientos (paciente_id, permiso_codigo, created_at DESC);
ALTER TABLE public.consentimientos ENABLE ROW LEVEL SECURITY;

-- SELECT: paciente dueño OR staff con pertenencia OR super_admin.
-- (Escritura: SOLO por RPC DEFINER — NO hay policy INSERT/UPDATE/DELETE → append-only.)
DROP POLICY IF EXISTS consentimientos_select ON public.consentimientos;
CREATE POLICY consentimientos_select ON public.consentimientos
  FOR SELECT TO authenticated
  USING (
    COALESCE(private.paciente_es_mio(paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(paciente_id::integer) )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  );

REVOKE ALL    ON public.consentimientos FROM anon;
GRANT  SELECT ON public.consentimientos TO authenticated; -- sin INSERT/UPDATE/DELETE: escritura solo vía RPC DEFINER
-- Contrarresta los default privileges de Supabase (ALL a authenticated al crear tabla en public): nacer
-- limpio en SELECT only endurece el append-only (RPC DEFINER corre como owner, ajeno a estos grants).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.consentimientos FROM authenticated;

-- ============================================================
-- PIEZA 3 — Documentos del paciente + bucket privado + storage policies
-- ============================================================
CREATE TABLE public.documentos_paciente (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  paciente_id bigint NOT NULL REFERENCES public.pacientes(id),
  tipo        text   NOT NULL,                       -- 'consentimiento_firmado','examen_externo','dpi','otro'
  descripcion text,
  path        text   NOT NULL,                       -- {clinica_id}/{paciente_id}/{uuid}.{ext} en bucket privado
  subido_por  uuid,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.documentos_paciente ENABLE ROW LEVEL SECURITY;

-- SELECT: paciente dueño OR staff con pertenencia OR super_admin. (Escritura: solo RPC DEFINER.)
DROP POLICY IF EXISTS documentos_paciente_select ON public.documentos_paciente;
CREATE POLICY documentos_paciente_select ON public.documentos_paciente
  FOR SELECT TO authenticated
  USING (
    COALESCE(private.paciente_es_mio(paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(paciente_id::integer) )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  );

REVOKE ALL    ON public.documentos_paciente FROM anon;
GRANT  SELECT ON public.documentos_paciente TO authenticated;
-- Contrarresta los default privileges de Supabase (ALL a authenticated al crear tabla en public): SELECT only
-- (escritura del registro solo vía RPC DEFINER registrar_documento_paciente).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.documentos_paciente FROM authenticated;

-- FK opcional consentimientos.documento_id → documentos_paciente (ahora que la tabla existe).
ALTER TABLE public.consentimientos
  ADD CONSTRAINT consentimientos_documento_fk
  FOREIGN KEY (documento_id) REFERENCES public.documentos_paciente(id);

-- Bucket privado SEPARADO de pacientes-fotos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('pacientes-documentos', 'pacientes-documentos', false)
ON CONFLICT (id) DO NOTHING;

-- 3 storage policies calcadas EXACTAS de pacientes-fotos (mig 168): confinadas por 1er segmento (clínica).
DROP POLICY IF EXISTS pacientes_docs_insert ON storage.objects;
CREATE POLICY pacientes_docs_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'pacientes-documentos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

DROP POLICY IF EXISTS pacientes_docs_update ON storage.objects;
CREATE POLICY pacientes_docs_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'pacientes-documentos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  )
  WITH CHECK (
    bucket_id = 'pacientes-documentos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

DROP POLICY IF EXISTS pacientes_docs_select ON storage.objects;
CREATE POLICY pacientes_docs_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'pacientes-documentos' AND (
      split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

-- ============================================================
-- PIEZA 4 — RPCs DEFINER (search_path='', gate fail-closed, REVOKE PUBLIC/anon + GRANT authenticated)
-- ============================================================

-- 4.1 path_documento_paciente — calcado de path_foto_paciente; path con uuid + extensión sanitizada.
CREATE OR REPLACE FUNCTION public.path_documento_paciente(p_paciente_id bigint, p_ext text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid     uuid;
  v_clinica uuid;
  v_ext     text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Gate: solo staff (medico/asistente) con pertenencia. El paciente NO sube papeles en v1.
  IF NOT ( private.tiene_rol(ARRAY['medico','asistente_medico'])
       AND private.paciente_en_clinica_de(p_paciente_id::integer) )
  THEN RAISE EXCEPTION 'No autorizado: rol o pertenencia'; END IF;

  -- Sanitizar extensión: solo alfanumérico, lowercase, 1..5 chars.
  v_ext := lower(regexp_replace(COALESCE(p_ext, ''), '[^A-Za-z0-9]', '', 'g'));
  IF v_ext = '' OR length(v_ext) > 5 THEN RAISE EXCEPTION 'Extensión inválida'; END IF;

  -- v_clinica = intersección paciente∩caller (preferencia clinica_primaria_id, fallback cita).
  SELECT pa.clinica_primaria_id INTO v_clinica
    FROM public.pacientes pa
    WHERE pa.id = p_paciente_id
      AND pa.clinica_primaria_id IN (SELECT private.clinicas_de(v_uid));
  IF v_clinica IS NULL THEN
    SELECT c.clinica_id INTO v_clinica
      FROM public.citas c
      WHERE c.paciente_id = p_paciente_id
        AND c.clinica_id IN (SELECT private.clinicas_de(v_uid))
      ORDER BY c.clinica_id
      LIMIT 1;
  END IF;
  IF v_clinica IS NULL THEN RAISE EXCEPTION 'Sin clínica compartida con el paciente'; END IF;

  RETURN jsonb_build_object(
    'path', v_clinica::text || '/' || p_paciente_id::text || '/' || gen_random_uuid()::text || '.' || v_ext,
    'clinica_id', v_clinica,
    'paciente_id', p_paciente_id
  );
END;
$function$;
REVOKE ALL     ON FUNCTION public.path_documento_paciente(bigint, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.path_documento_paciente(bigint, text) TO authenticated;

-- 4.2 registrar_documento_paciente — staff sube el registro tras la subida al bucket.
CREATE OR REPLACE FUNCTION public.registrar_documento_paciente(
  p_paciente_id bigint, p_tipo text, p_path text, p_descripcion text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_id  bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF NOT ( private.tiene_rol(ARRAY['medico','asistente_medico'])
       AND private.paciente_en_clinica_de(p_paciente_id::integer) )
  THEN RAISE EXCEPTION 'No autorizado: rol o pertenencia'; END IF;

  IF p_path IS NULL OR length(trim(p_path)) = 0 THEN RAISE EXCEPTION 'Path vacío'; END IF;
  IF p_tipo IS NULL OR length(trim(p_tipo)) = 0 THEN RAISE EXCEPTION 'Tipo vacío'; END IF;

  -- Defensivo: el 1er segmento del path (clinica) debe ser una clínica del caller.
  IF NOT (split_part(p_path, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu))
  THEN RAISE EXCEPTION 'Path fuera de tu clínica'; END IF;

  INSERT INTO public.documentos_paciente (paciente_id, tipo, descripcion, path, subido_por)
  VALUES (p_paciente_id, p_tipo, p_descripcion, p_path, v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'path', p_path, 'tipo', p_tipo);
END;
$function$;
REVOKE ALL     ON FUNCTION public.registrar_documento_paciente(bigint, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_documento_paciente(bigint, text, text, text) TO authenticated;

-- 4.3 listar_documentos_paciente — lectura (paciente dueño OR staff pertenencia OR super_admin).
CREATE OR REPLACE FUNCTION public.listar_documentos_paciente(p_paciente_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF NOT (
       COALESCE(private.paciente_es_mio(p_paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(p_paciente_id::integer) )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  ) THEN RAISE EXCEPTION 'No autorizado'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
             jsonb_build_object(
               'id', d.id, 'tipo', d.tipo, 'descripcion', d.descripcion,
               'path', d.path, 'subido_por', d.subido_por, 'created_at', d.created_at
             ) ORDER BY d.created_at DESC
           )
    FROM public.documentos_paciente d
    WHERE d.paciente_id = p_paciente_id
  ), '[]'::jsonb);
END;
$function$;
REVOKE ALL     ON FUNCTION public.listar_documentos_paciente(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_documentos_paciente(bigint) TO authenticated;

-- 4.4 registrar_consentimiento — gate DOBLE (app⇒paciente; presencial⇒staff). Cubre conceder Y revocar.
CREATE OR REPLACE FUNCTION public.registrar_consentimiento(
  p_paciente_id bigint, p_permiso_codigo text, p_concedido boolean, p_via text, p_documento_id bigint DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid         uuid;
  v_version     int;
  v_id          bigint;
  v_es_paciente boolean;
  v_es_staff    boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF p_via IS NULL OR p_via NOT IN ('app','presencial_firma','presencial_papel')
  THEN RAISE EXCEPTION 'Vía inválida'; END IF;

  v_es_paciente := COALESCE(private.paciente_es_mio(p_paciente_id), false);
  v_es_staff    := private.tiene_rol(ARRAY['medico','asistente_medico'])
               AND private.paciente_en_clinica_de(p_paciente_id::integer);

  -- Gate doble: app ⇒ el caller es el paciente; presencial ⇒ el caller es staff con pertenencia.
  IF p_via = 'app' THEN
    IF NOT v_es_paciente THEN RAISE EXCEPTION 'No autorizado: vía app requiere ser el paciente'; END IF;
  ELSE
    IF NOT v_es_staff THEN RAISE EXCEPTION 'No autorizado: vía presencial requiere staff con pertenencia'; END IF;
  END IF;

  -- Defensivo (confinamiento): si se enlaza un documento, debe ser de ESTE paciente.
  IF p_documento_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.documentos_paciente d
                   WHERE d.id = p_documento_id AND d.paciente_id = p_paciente_id)
    THEN RAISE EXCEPTION 'Documento no pertenece al paciente'; END IF;
  END IF;

  -- permiso_version = la versión ACTIVA más alta del código.
  SELECT cp.version INTO v_version
    FROM public.consentimiento_permisos cp
    WHERE cp.codigo = p_permiso_codigo AND cp.activo = true
    ORDER BY cp.version DESC
    LIMIT 1;
  IF v_version IS NULL THEN RAISE EXCEPTION 'Permiso inexistente o inactivo: %', p_permiso_codigo; END IF;

  -- Append-only: SIEMPRE INSERT (conceder o revocar = nueva fila).
  INSERT INTO public.consentimientos
    (paciente_id, permiso_codigo, permiso_version, concedido, via, capturado_por, documento_id)
  VALUES
    (p_paciente_id, p_permiso_codigo, v_version, p_concedido, p_via, v_uid, p_documento_id)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id, 'permiso_codigo', p_permiso_codigo, 'permiso_version', v_version,
    'concedido', p_concedido, 'via', p_via
  );
END;
$function$;
REVOKE ALL     ON FUNCTION public.registrar_consentimiento(bigint, text, boolean, text, bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_consentimiento(bigint, text, boolean, text, bigint) TO authenticated;

-- 4.5 estado_consentimiento_paciente — estado VIGENTE (DISTINCT ON: la fila más reciente por código).
CREATE OR REPLACE FUNCTION public.estado_consentimiento_paciente(p_paciente_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF NOT (
       COALESCE(private.paciente_es_mio(p_paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(p_paciente_id::integer) )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  ) THEN RAISE EXCEPTION 'No autorizado'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
             jsonb_build_object(
               'codigo', s.permiso_codigo, 'concedido', s.concedido, 'via', s.via,
               'permiso_version', s.permiso_version, 'created_at', s.created_at
             )
           )
    FROM (
      SELECT DISTINCT ON (c.permiso_codigo)
             c.permiso_codigo, c.concedido, c.via, c.permiso_version, c.created_at
      FROM public.consentimientos c
      WHERE c.paciente_id = p_paciente_id
      ORDER BY c.permiso_codigo, c.created_at DESC, c.id DESC  -- id DESC desempata created_at idéntico (vigente = el más nuevo)
    ) s
  ), '[]'::jsonb);
END;
$function$;
REVOKE ALL     ON FUNCTION public.estado_consentimiento_paciente(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.estado_consentimiento_paciente(bigint) TO authenticated;
