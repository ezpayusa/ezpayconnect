-- ############################################################################################
-- 335 - P4 fase 2 de 3: resultados de examen congelados, correccion con motivo, eventos de
--       liberacion y storage sin sobrescritura (examenes / storage resultados-examenes)
-- ############################################################################################
-- Spec: docs/specs/P4-revisiones-inmutables-spec-2026-09-26.md (v3), seccion MIG 335. Decisiones
-- D5, D6, D7, D10 de examenes; respuestas R3 y R6 de Oscar; C6 (rollback con CRLF), C8 (fixtures).
--
-- Antes (medido 26-sep, main 22adc27): el laboratorio reescribe resultados/archivo/fecha de un
-- examen completado con UPDATE directo, un completado puede volver a pendiente, el bucket permite
-- sobrescribir objetos (resultados_scoped_update), liberar/revertir no dejan rastro propio y
-- authenticated conserva MAINTAIN sobre examenes. El front ya sube sin upsert (PR #7, 22adc27).
--
-- Esta migracion:
--   (a) public.examen_revisiones: append-only, una fila por correccion con los valores ANTERIORES.
--   (b) public.examen_liberacion_eventos: append-only, una fila por liberacion o reversion (D7).
--       Las dos: RLS + FORCE, una policy SELECT via private.puede_ver_historial_examen (lab dueno,
--       medico del examen o tratante, admin clinica, super_admin; el paciente no, R3).
--   (c) private.examenes_resultado_congelado (BEFORE UPDATE OF resultados, archivo_url,
--       fecha_resultado, estado): EX032 un completado no vuelve atras (para todos); EX031 el
--       resultado de un completado solo cambia con la llave corregir:<id> (para todos, postgres
--       incluido).
--   (d) private.path_resultado_referenciado: el path figura en examen_adjuntos, examenes.archivo_url
--       o examen_revisiones.archivo_url_anterior (normalizado). DEFINER: la policy de storage no
--       depende de que el caller pueda leer examen_revisiones (leccion de la mig 284).
--   (e) private.historial_examen_inmutable: EX033 en UPDATE/DELETE de las dos tablas nuevas.
--   (f) private.notificar_resultado_corregido: aviso sin PHI al medico y al paciente.
--   (g) public.corregir_resultado_examen: correccion con motivo por el laboratorio dueno
--       (EX023-EX030, EX034; 42501 de exigir_empresa_activa). fecha_resultado NO cambia (R6).
--   (h) liberar_examen_al_paciente, liberar_orden_al_paciente, revertir_liberacion_examen: escriben
--       su evento. El cuerpo nuevo de liberar_examen_al_paciente va en LF (el previo era CRLF, C6).
--   (i) paciente_examenes(): DROP + CREATE con la columna final `corregido`; EXECUTE exacto.
--   (j) storage: DROP resultados_scoped_update (sin sobrescritura); resultados_scoped_delete usa el
--       helper (tampoco se borra un archivo que quedo en el historial).
--   (k) REVOKE MAINTAIN (D10) + TRUNCATE/TRIGGER/REFERENCES (ya fuera desde la 333) en examenes.
--
-- Llave de correccion: ezpay.examen_llave = 'corregir:<examen_id>', GUC local a la transaccion,
-- puesta solo por la RPC. El cliente no puede ejecutar set_config (pg_catalog no esta expuesto).
--
-- NO toca: notificar_resultado_examen, puede_ver_examen, registrar_examen_adjunto,
-- examenes_congelar_identidad, crear_orden_examen_medico/_walkin, notificar_orden_lab,
-- contexto_ia_paciente, exigir_empresa_activa (precondicion y autochequeo por md5), las policies de
-- examenes ni los grants por columna de la 332. El DELETE directo de examenes es la 336.
--
-- Errcodes EX023-EX034 (EX021 queda reservado sin uso). Probes P897-P905. Rollback: 335_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
DO $pre$
DECLARE bad text := ''; x text; r record; n int;
BEGIN
  -- las 4 funciones que la 335 reemplaza y las que no toca: md5 exacto
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)',                  '7c980b20f713d0cf49e7235da30838e1'),
      ('public.liberar_orden_al_paciente(uuid)',                      '96a54d314911a439af77e426ebe46611'),
      ('public.revertir_liberacion_examen(integer)',                  '4a7f4912f3330543d2d7a47b2a06fbc6'),
      ('public.paciente_examenes()',                                  'a14ea485045b28883d81a0dd9fe7cd83'),
      ('public.notificar_resultado_examen(integer)',                  '33a7a110c39574c5a40f7ca1495d2686'),
      ('public.notificar_orden_lab(uuid)',                            '59fafc8572840548c27ad39a759cba47'),
      ('private.puede_ver_examen(integer)',                           '2b8150875b99dfb5df9fdb3d8af62ae0'),
      ('public.registrar_examen_adjunto(integer,text,text)',          '245fb6669aa3fb22f8e62ca40a8b3467'),
      ('public.contexto_ia_paciente(bigint)',                         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('private.examenes_congelar_identidad()',                       'f0ff903d5c5af6e137ba6b6aed0bad9a'),
      ('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)',    '79a994588ab2b4458135272efb59b867'),
      ('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)', '434d122370e340d895c8540a290379f3'),
      ('private.exigir_empresa_activa()',                             'd62cc5a3c6edf0aaf48488e59a8d1e9b')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- C6: el cuerpo previo de liberar_examen_al_paciente es CRLF (27 \r, 27 \n)
  SELECT (length(prosrc) - length(replace(prosrc, E'\r', '')))::text||'/'||(length(prosrc) - length(replace(prosrc, E'\n', '')))::text
    INTO x FROM pg_proc WHERE oid = to_regprocedure('public.liberar_examen_al_paciente(integer)');
  IF x IS DISTINCT FROM '27/27' THEN bad := bad||'CRLF de liberar_examen_al_paciente='||COALESCE(x,'-')||'; '; END IF;
  -- helpers que usan las funciones y la policy nuevas
  FOR r IN SELECT f FROM unnest(ARRAY['private.tiene_rol(text[])','private.tiene_permiso(text)','public.mi_empresa_proveedor()',
      'private.medico_atiende_paciente(bigint)','private.es_admin_clinica(uuid)','private.push_notificar(text,text)']) f LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; END IF;
  END LOOP;
  -- nombres libres
  IF to_regclass('public.examen_revisiones') IS NOT NULL THEN bad := bad||'examen_revisiones ya existe; '; END IF;
  IF to_regclass('public.examen_liberacion_eventos') IS NOT NULL THEN bad := bad||'examen_liberacion_eventos ya existe; '; END IF;
  SELECT string_agg(p.oid::regprocedure::text, ',') INTO x FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname = 'public' AND p.proname = 'corregir_resultado_examen')
      OR (ns.nspname = 'private' AND p.proname IN ('puede_ver_historial_examen','examenes_resultado_congelado','path_resultado_referenciado',
                                                    'historial_examen_inmutable','notificar_resultado_corregido'));
  IF x IS NOT NULL THEN bad := bad||'funciones ya existen: '||x||'; '; END IF;
  SELECT string_agg(tgname, ',') INTO x FROM pg_trigger
   WHERE tgname IN ('trg_examenes_resultado_congelado','trg_examen_rev_inmutable','trg_examen_lib_inmutable');
  IF x IS NOT NULL THEN bad := bad||'triggers ya existen: '||x||'; '; END IF;
  SELECT count(*) INTO n FROM pg_proc WHERE prosrc ~ 'EX0(2[3-9]|3[0-4])';
  IF n <> 0 THEN bad := bad||n||' funcion(es) ya usan EX023-EX034; '; END IF;
  -- estado previo que la 335 reemplaza
  SELECT string_agg(tgname, ',' ORDER BY tgname COLLATE "C") INTO x FROM pg_trigger WHERE tgrelid = 'public.examenes'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_examenes_congelar_identidad' THEN bad := bad||'triggers de examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT relacl::text INTO x FROM pg_class WHERE oid = 'public.examenes'::regclass;
  IF x IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=rdm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attname) INTO x FROM pg_attribute a
   WHERE a.attrelid = 'public.examenes'::regclass AND a.attacl IS NOT NULL;
  IF x IS DISTINCT FROM 'archivo_url={authenticated=w/postgres},estado={authenticated=w/postgres},fecha_resultado={authenticated=w/postgres},resultados={authenticated=w/postgres}' THEN
    bad := bad||'grants por columna de examenes='||COALESCE(x,'-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = 'public.examen_estado'::regtype AND enumlabel = 'completado') THEN
    bad := bad||'examen_estado sin completado; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_update'
       AND cmd = 'UPDATE' AND permissive = 'PERMISSIVE' AND roles::text = '{authenticated}'
       AND qual = '((bucket_id = ''resultados-examenes''::text) AND ((split_part(name, ''/''::text, 1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY[''super_admin''::text])))'
       AND with_check = qual) THEN
    bad := bad||'resultados_scoped_update distinta de la medida; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_delete'
       AND cmd = 'DELETE' AND permissive = 'PERMISSIVE' AND roles::text = '{authenticated}' AND with_check IS NULL
       AND qual = '((bucket_id = ''resultados-examenes''::text) AND ((split_part(name, ''/''::text, 1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY[''super_admin''::text])) AND (NOT (EXISTS ( SELECT 1'||E'\n'||'   FROM examen_adjuntos a'||E'\n'||'  WHERE (a.storage_path = objects.name)))) AND (NOT (EXISTS ( SELECT 1'||E'\n'||'   FROM examenes e'||E'\n'||'  WHERE (COALESCE(NULLIF(split_part(e.archivo_url, ''/resultados-examenes/''::text, 2), ''''::text), e.archivo_url) = objects.name)))))') THEN
    bad := bad||'resultados_scoped_delete distinta de la medida; '; END IF;
  -- paciente_examenes: firma unica, EXECUTE exacto y sin dependientes (el DROP es seguro)
  SELECT count(*) INTO n FROM pg_proc WHERE proname = 'paciente_examenes';
  IF n <> 1 THEN bad := bad||n||' firmas de paciente_examenes; '; END IF;
  SELECT proacl::text INTO x FROM pg_proc WHERE oid = to_regprocedure('public.paciente_examenes()');
  IF x IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'ACL paciente_examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT count(*) INTO n FROM pg_depend WHERE refobjid = to_regprocedure('public.paciente_examenes()');
  IF n <> 0 THEN bad := bad||n||' dependiente(s) de paciente_examenes; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG335 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- snapshot del contenido de examenes: la migracion no puede cambiar ninguna fila
CREATE TEMP TABLE _snap335 ON COMMIT DROP AS
SELECT md5(COALESCE(string_agg(to_jsonb(e)::text, '|' ORDER BY e.id), '')) AS examenes FROM public.examenes e;

-- ----------------------------------------------------------------- (a) tabla de revisiones
CREATE TABLE public.examen_revisiones (
  id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  examen_id                integer NOT NULL CONSTRAINT examen_revisiones_examen_id_fkey
                             REFERENCES public.examenes(id) ON DELETE RESTRICT,
  laboratorio_id           uuid    NOT NULL,
  revision                 integer NOT NULL,
  resultados_anterior      text    NULL,
  archivo_url_anterior     text    NULL,
  fecha_resultado_anterior date    NULL,
  liberado_al_corregir     boolean NOT NULL,
  motivo                   text    NOT NULL CONSTRAINT examen_revisiones_motivo_check CHECK (btrim(motivo) <> ''),
  corregido_por            uuid    NOT NULL,
  corregido_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT examen_revisiones_examen_revision_key UNIQUE (examen_id, revision)
);
-- el UNIQUE (examen_id, revision) ya sirve de indice para examen_id (columna inicial), igual que en la 334
CREATE INDEX idx_examen_rev_archivo ON public.examen_revisiones USING btree (archivo_url_anterior);
COMMENT ON TABLE public.examen_revisiones IS
  'Historial append-only de correcciones de resultados (mig 335): una fila por correccion con los valores ANTERIORES. La escribe solo corregir_resultado_examen; UPDATE/DELETE -> EX033 para todos.';

-- ------------------------------------------------------------- (b) eventos de liberacion
CREATE TABLE public.examen_liberacion_eventos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  examen_id   integer NOT NULL CONSTRAINT examen_liberacion_eventos_examen_id_fkey
                REFERENCES public.examenes(id) ON DELETE RESTRICT,
  evento      text    NOT NULL CONSTRAINT examen_liberacion_eventos_evento_check CHECK (evento IN ('liberado','revertido')),
  via         text    NOT NULL CONSTRAINT examen_liberacion_eventos_via_check CHECK (via IN ('examen','orden')),
  orden_id    uuid    NULL,
  actor       uuid    NOT NULL,
  ocurrido_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_examen_lib_ev_examen ON public.examen_liberacion_eventos USING btree (examen_id);
COMMENT ON TABLE public.examen_liberacion_eventos IS
  'Eventos append-only de liberacion y reversion de resultados al paciente (mig 335, D7). Los escriben liberar_examen_al_paciente, liberar_orden_al_paciente y revertir_liberacion_examen; UPDATE/DELETE -> EX033 para todos.';

-- ------------------------------------------------------------------ helper de visibilidad
CREATE FUNCTION private.puede_ver_historial_examen(p_examen_id integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- private.puede_ver_examen SIN la rama del paciente (R3): el paciente no ve el historial
  SELECT COALESCE((
    SELECT (e.medico_id = auth.uid())
        OR private.medico_atiende_paciente((e.paciente_id)::bigint)
        OR ((e.clinica_id IS NOT NULL) AND private.es_admin_clinica(e.clinica_id))
        OR (e.laboratorio_id = public.mi_empresa_proveedor())
        OR private.tiene_rol(ARRAY['super_admin'::text])
      FROM public.examenes e
     WHERE e.id = p_examen_id
  ), false)
$function$;
COMMENT ON FUNCTION private.puede_ver_historial_examen(integer) IS
  'Mig 335. Quien ve el historial de un examen (revisiones y eventos): medico del examen, tratante, admin de la clinica, laboratorio dueno, super_admin. El paciente no (R3). Fail-closed.';

ALTER TABLE public.examen_revisiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examen_revisiones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.examen_liberacion_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examen_liberacion_eventos FORCE ROW LEVEL SECURITY;

CREATE POLICY examen_rev_select ON public.examen_revisiones
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.puede_ver_historial_examen(examen_id));
CREATE POLICY examen_lib_ev_select ON public.examen_liberacion_eventos
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.puede_ver_historial_examen(examen_id));

-- los default privileges de postgres en public dan arwdDxtm a authenticated y service_role: se
-- parte de cero y se otorga exactamente lo de la regla del 30-oct
REVOKE ALL ON TABLE public.examen_revisiones, public.examen_liberacion_eventos FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.examen_revisiones, public.examen_liberacion_eventos TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.examen_revisiones, public.examen_liberacion_eventos TO service_role;
REVOKE ALL ON SEQUENCE public.examen_revisiones_id_seq, public.examen_liberacion_eventos_id_seq FROM PUBLIC, anon, authenticated;

-- --------------------------------------------------------------- (c) resultado congelado
CREATE FUNCTION private.examenes_resultado_congelado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF OLD.estado::text = 'completado' THEN
    -- D5: un completado no vuelve atras, para nadie (tampoco con la llave ni como postgres)
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'Un examen completado no puede volver a un estado anterior' USING ERRCODE = 'EX032';
    END IF;
    -- el resultado vigente solo cambia por corregir_resultado_examen (llave atada al id)
    IF (NEW.resultados IS DISTINCT FROM OLD.resultados
        OR NEW.archivo_url IS DISTINCT FROM OLD.archivo_url
        OR NEW.fecha_resultado IS DISTINCT FROM OLD.fecha_resultado)
       AND COALESCE(current_setting('ezpay.examen_llave', true), '') IS DISTINCT FROM 'corregir:'||OLD.id THEN
      RAISE EXCEPTION 'El resultado de un examen completado solo se corrige con motivo' USING ERRCODE = 'EX031';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
COMMENT ON FUNCTION private.examenes_resultado_congelado() IS
  'Mig 335. BEFORE UPDATE OF resultados, archivo_url, fecha_resultado, estado ON examenes, para todos (postgres incluido): EX032 un completado no cambia de estado; EX031 su resultado solo cambia con la llave corregir:<id>. No mira las columnas de liberacion.';

-- --------------------------------------------------------- (d) path referenciado (storage)
CREATE FUNCTION private.path_resultado_referenciado(p_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- misma normalizacion que resultados_scoped_select: una fila historica puede guardar la URL completa
  SELECT EXISTS (SELECT 1 FROM public.examen_adjuntos a WHERE a.storage_path = p_path)
      OR EXISTS (SELECT 1 FROM public.examenes e
                  WHERE COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/', 2), ''), e.archivo_url) = p_path)
      OR EXISTS (SELECT 1 FROM public.examen_revisiones r
                  WHERE COALESCE(NULLIF(split_part(r.archivo_url_anterior, '/resultados-examenes/', 2), ''), r.archivo_url_anterior) = p_path)
$function$;
COMMENT ON FUNCTION private.path_resultado_referenciado(text) IS
  'Mig 335. true si el path del bucket resultados-examenes esta referenciado por examen_adjuntos, examenes.archivo_url o examen_revisiones.archivo_url_anterior (normalizados). DEFINER: la policy de storage no depende de lo que el caller pueda leer.';

-- ----------------------------------------------------------------------- (e) inmutabilidad
CREATE FUNCTION private.historial_examen_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Las revisiones y eventos de exámenes son inmutables' USING ERRCODE = 'EX033';
END
$function$;
COMMENT ON FUNCTION private.historial_examen_inmutable() IS
  'Mig 335. BEFORE UPDATE OR DELETE de examen_revisiones y examen_liberacion_eventos: EX033 para todos.';

-- ------------------------------------------------------------------ (f) aviso de correccion
CREATE FUNCTION private.notificar_resultado_corregido(p_examen_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_mid uuid; v_pid integer; v_url text;
BEGIN
  -- Nueva a proposito (no se reusa notificar_resultado_examen: su gate exige que el caller sea el
  -- laboratorio, su texto dice "listo" y no avisa al paciente). Sin PHI: ni tipo, ni resultado, ni
  -- nombre (P412/P413). La llama solo corregir_resultado_examen.
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_url := CASE WHEN v.paciente_id IS NOT NULL
                THEN '/medico/pacientes/' || v.paciente_id::text || '/detalle'
                ELSE '/medico/citas' END;

  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen corregido',
              'El laboratorio corrigió un resultado de examen que ya estaba liberado.', v_url,
              jsonb_build_object('examen_id', v.id, 'paciente_id', v.paciente_id, 'corregido', true))
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;
  END IF;

  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen corregido',
              'Se corrigió un resultado de examen que ya podías ver. Revísalo en tu portal.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
END
$function$;
COMMENT ON FUNCTION private.notificar_resultado_corregido(integer) IS
  'Mig 335. Aviso sin PHI de "resultado corregido" al medico (notificaciones) y al paciente (notificaciones_pacientes), con push. Solo EXECUTE postgres; la llama corregir_resultado_examen si el examen ya estaba liberado.';

-- --------------------------------------------------------------------------- (g) la RPC
CREATE FUNCTION public.corregir_resultado_examen(
  p_examen_id integer, p_motivo text, p_resultados text, p_archivo_path text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_ex     public.examenes%ROWTYPE;
  v_motivo text;
  v_res    text;
  v_path   text;
  v_arch   text;
  v_rev    integer;
  v_notif  boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicie sesión' USING ERRCODE = 'EX023';
  END IF;
  -- gate de cuenta de la 326: cuenta proveedora inactiva o empresa no activa -> 42501
  PERFORM private.exigir_empresa_activa();

  SELECT * INTO v_ex FROM public.examenes e WHERE e.id = p_examen_id FOR UPDATE;
  -- mismo codigo para "no existe" (no se revela la existencia). laboratorio_id NULL no es de nadie.
  -- El COALESCE cubre el helper NULL (caller sin cuenta, cuenta inactiva o empresa no activa):
  -- la comparacion da NULL y el COALESCE la vuelve false, asi que el gate corta (fail-closed, P480).
  IF NOT FOUND OR v_ex.laboratorio_id IS NULL
     OR NOT COALESCE(v_ex.laboratorio_id = public.mi_empresa_proveedor(), false) THEN
    RAISE EXCEPTION 'No autorizado: el examen no es de su laboratorio' USING ERRCODE = 'EX024';
  END IF;
  IF NOT COALESCE(private.tiene_permiso('resultados_cargar'), false) THEN
    RAISE EXCEPTION 'No autorizado: no tiene permiso para cargar resultados' USING ERRCODE = 'EX025';
  END IF;
  IF v_ex.estado::text <> 'completado' THEN
    RAISE EXCEPTION 'El examen no está completado: cargue el resultado normalmente' USING ERRCODE = 'EX026';
  END IF;
  v_motivo := btrim(p_motivo);
  IF v_motivo IS NULL OR v_motivo = '' OR length(v_motivo) > 500 THEN
    RAISE EXCEPTION 'El motivo de la corrección es obligatorio (máximo 500 caracteres)' USING ERRCODE = 'EX027';
  END IF;

  v_res  := NULLIF(btrim(p_resultados), '');
  v_path := NULLIF(btrim(p_archivo_path), '');
  IF v_path IS NOT NULL THEN
    -- archivo NUEVO de su laboratorio: en su carpeta, distinto del vigente y sin referencias (el
    -- vigente ya es una referencia; se compara tambien normalizado por las filas con URL completa)
    IF left(v_path, length(v_ex.laboratorio_id::text) + 1) IS DISTINCT FROM v_ex.laboratorio_id::text || '/'
       OR v_path IS NOT DISTINCT FROM v_ex.archivo_url
       OR v_path IS NOT DISTINCT FROM COALESCE(NULLIF(split_part(v_ex.archivo_url, '/resultados-examenes/', 2), ''), v_ex.archivo_url)
       OR private.path_resultado_referenciado(v_path) THEN
      RAISE EXCEPTION 'El archivo corregido debe ser un archivo nuevo de su laboratorio' USING ERRCODE = 'EX029';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'resultados-examenes' AND o.name = v_path) THEN
      RAISE EXCEPTION 'El archivo corregido no existe en el almacenamiento' USING ERRCODE = 'EX030';
    END IF;
  END IF;
  v_arch := COALESCE(v_path, v_ex.archivo_url);
  IF v_res IS NULL AND v_arch IS NULL THEN
    RAISE EXCEPTION 'El resultado corregido no puede quedar vacío' USING ERRCODE = 'EX034';
  END IF;
  IF v_res IS NOT DISTINCT FROM v_ex.resultados AND v_arch IS NOT DISTINCT FROM v_ex.archivo_url THEN
    RAISE EXCEPTION 'La corrección no cambia el resultado' USING ERRCODE = 'EX028';
  END IF;

  -- revision con los valores ANTERIORES (el FOR UPDATE del examen serializa el max+1)
  SELECT COALESCE(max(r.revision), 0) + 1 INTO v_rev FROM public.examen_revisiones r WHERE r.examen_id = v_ex.id;
  INSERT INTO public.examen_revisiones
    (examen_id, laboratorio_id, revision, resultados_anterior, archivo_url_anterior, fecha_resultado_anterior,
     liberado_al_corregir, motivo, corregido_por)
  VALUES
    (v_ex.id, v_ex.laboratorio_id, v_rev, v_ex.resultados, v_ex.archivo_url, v_ex.fecha_resultado,
     v_ex.liberado_al_paciente, v_motivo, v_uid);

  -- R6: fecha_resultado no cambia; la fecha de la correccion queda en examen_revisiones.corregido_at
  PERFORM set_config('ezpay.examen_llave', 'corregir:'||v_ex.id, true);
  UPDATE public.examenes SET resultados = v_res, archivo_url = v_arch WHERE id = v_ex.id;
  PERFORM set_config('ezpay.examen_llave', '', true);

  -- best-effort (como la 332): la correccion no se pierde si el aviso falla
  IF v_ex.liberado_al_paciente THEN
    BEGIN
      PERFORM private.notificar_resultado_corregido(v_ex.id);
      v_notif := true;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'corregir_resultado_examen: aviso no enviado (examen %): % %', v_ex.id, SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('examen_id', v_ex.id, 'revision', v_rev, 'notificado', v_notif);
END
$function$;
COMMENT ON FUNCTION public.corregir_resultado_examen(integer, text, text, text) IS
  'Mig 335. Correccion con motivo del resultado de un examen COMPLETADO por su laboratorio. Gates: EX023 sesion, 42501 cuenta/empresa (exigir_empresa_activa), EX024 laboratorio dueno (o no existe), EX025 permiso resultados_cargar, EX026 no completado, EX027 motivo, EX029/EX030 archivo nuevo existente, EX034 vacio, EX028 sin cambios. fecha_resultado no cambia (R6). Avisa si estaba liberado.';

-- EXECUTE: la RPC y los helpers de policy a authenticated; el resto solo postgres (los default
-- privileges otorgan X a authenticated y service_role, y la creacion a PUBLIC)
REVOKE ALL ON FUNCTION public.corregir_resultado_examen(integer, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.corregir_resultado_examen(integer, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION private.puede_ver_historial_examen(integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.puede_ver_historial_examen(integer) TO authenticated;
REVOKE ALL ON FUNCTION private.path_resultado_referenciado(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.path_resultado_referenciado(text) TO authenticated;
REVOKE ALL ON FUNCTION private.examenes_resultado_congelado() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.historial_examen_inmutable() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.notificar_resultado_corregido(integer) FROM PUBLIC, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------ triggers
CREATE TRIGGER trg_examenes_resultado_congelado
  BEFORE UPDATE OF resultados, archivo_url, fecha_resultado, estado ON public.examenes
  FOR EACH ROW EXECUTE FUNCTION private.examenes_resultado_congelado();
CREATE TRIGGER trg_examen_rev_inmutable
  BEFORE UPDATE OR DELETE ON public.examen_revisiones
  FOR EACH ROW EXECUTE FUNCTION private.historial_examen_inmutable();
CREATE TRIGGER trg_examen_lib_inmutable
  BEFORE UPDATE OR DELETE ON public.examen_liberacion_eventos
  FOR EACH ROW EXECUTE FUNCTION private.historial_examen_inmutable();

-- ------------------------------------------------- (h) liberar / revertir escriben su evento
-- Cuerpos identicos a los medidos (md5 en las precondiciones) salvo el INSERT del evento. El de
-- liberar_examen_al_paciente pasa de CRLF a LF (el rollback restaura el CRLF, C6).
CREATE OR REPLACE FUNCTION public.liberar_examen_al_paciente(p_examen_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_pid integer;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Examen inexistente' USING ERRCODE='PT002'; END IF;
  -- MIG 301: el COALESCE envuelve la cadena ENTERA. `v.medico_id = auth.uid()` vale NULL cuando el
  -- examen no tiene medico asignado (o cuando el caller es anon), y `NULL OR false` es NULL, que en
  -- un IF no entra al THEN. Mismo arreglo que la mig 300 aplico a actualizar_estado_cita.
  IF NOT COALESCE( v.medico_id = auth.uid()
        OR private.medico_atiende_paciente((v.paciente_id)::bigint)
        OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
        OR private.tiene_rol(ARRAY['super_admin'::text]) , false) THEN
    RAISE EXCEPTION 'No autorizado para liberar este examen' USING ERRCODE='PT002'; END IF;
  IF v.estado::text <> 'completado' THEN
    RAISE EXCEPTION 'El examen aun no tiene resultado cargado' USING ERRCODE='PT002'; END IF;
  IF v.liberado_al_paciente THEN
    RETURN jsonb_build_object('examen', v.id, 'ya_liberado', true); END IF;
  UPDATE public.examenes SET liberado_al_paciente=true, fecha_liberacion=now(), liberado_por=auth.uid()
   WHERE id = v.id;
  -- MIG 335 (D7): evento append-only de la liberacion. En el no-op ya_liberado no hay evento.
  INSERT INTO public.examen_liberacion_eventos (examen_id, evento, via, orden_id, actor)
    VALUES (v.id, 'liberado', 'examen', NULL, auth.uid());
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen disponible',
              'Tu medico libero un resultado de examen. Ya puedes verlo.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
  RETURN jsonb_build_object('examen', v.id, 'liberado', true);
END; $function$;

CREATE OR REPLACE FUNCTION public.liberar_orden_al_paciente(p_orden_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_count integer; v_pac integer; v_nid integer;
BEGIN
  WITH upd AS (
    UPDATE public.examenes e
       SET liberado_al_paciente=true, fecha_liberacion=now(), liberado_por=auth.uid()
     WHERE e.orden_id = p_orden_id
       AND e.estado::text = 'completado'
       AND e.liberado_al_paciente = false
       AND ( e.medico_id = auth.uid()
          OR private.medico_atiende_paciente((e.paciente_id)::bigint)
          OR (e.clinica_id IS NOT NULL AND private.es_admin_clinica(e.clinica_id))
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
     RETURNING e.id, e.paciente_id
  ),
  -- MIG 335 (D7): un evento 'liberado' via 'orden' por cada examen liberado (un CTE que modifica
  -- se ejecuta completo aunque la consulta principal no lo lea)
  ev AS (
    INSERT INTO public.examen_liberacion_eventos (examen_id, evento, via, orden_id, actor)
    SELECT u.id, 'liberado', 'orden', p_orden_id, auth.uid() FROM upd u
  )
  SELECT count(*), max(paciente_id) INTO v_count, v_pac FROM upd;
  IF COALESCE(v_count,0) = 0 THEN RETURN jsonb_build_object('liberados', 0); END IF;
  IF v_pac IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v_pac, 'examen', 'Resultados de examen disponibles',
              'Tu medico libero resultados de examen. Ya puedes verlos.', '/paciente/examenes', false)
      RETURNING id INTO v_nid;
    IF v_nid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_nid::text); END IF;
  END IF;
  RETURN jsonb_build_object('liberados', v_count);
END; $function$;

CREATE OR REPLACE FUNCTION public.revertir_liberacion_examen(p_examen_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Examen inexistente' USING ERRCODE = 'PT002';
  END IF;

  -- El COALESCE envuelve la cadena ENTERA, igual que en liberar_examen_al_paciente desde la mig
  -- 301: `v.medico_id = auth.uid()` vale NULL cuando el examen no tiene medico asignado o el
  -- caller es anon, y `NULL OR false` es NULL, que en un IF NO entra al THEN. Sin el COALESCE
  -- este gate falla ABIERTO. (La hermana liberar_orden_al_paciente no lo necesita porque su gate
  -- vive en un WHERE, donde NULL filtra la fila.)
  --
  -- El laboratorio NO figura a proposito: ver el recon del frente 4. Esta lista es, literal, la
  -- misma de liberar_examen_al_paciente.
  IF NOT COALESCE( v.medico_id = auth.uid()
        OR private.medico_atiende_paciente((v.paciente_id)::bigint)
        OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
        OR private.tiene_rol(ARRAY['super_admin'::text]) , false) THEN
    RAISE EXCEPTION 'No autorizado para revertir la liberacion de este examen'
      USING ERRCODE = 'PE004';
  END IF;

  -- NO-OP, NO ERROR. Simetrico con el `ya_liberado` de liberar_examen_al_paciente, que el front
  -- ya trata como caso normal (src/lib/liberacionExamenes.ts). Dos pantallas que reviertan el
  -- mismo examen a la vez no tienen por que ver un error.
  -- NO gasta PE005: ese numero queda LIBRE para otra cosa. Esto no es un rechazo.
  IF NOT v.liberado_al_paciente THEN
    RETURN jsonb_build_object('examen', v.id, 'ya_no_liberado', true);
  END IF;

  -- Sin tocar fecha_liberacion ni liberado_por: son el rastro de la liberacion que se revierte.
  UPDATE public.examenes
     SET liberado_al_paciente = false,
         revertido_por        = auth.uid(),
         fecha_reversion      = now()
   WHERE id = v.id;

  -- MIG 335 (D7): evento append-only de la reversion. En el no-op ya_no_liberado no hay evento.
  INSERT INTO public.examen_liberacion_eventos (examen_id, evento, via, orden_id, actor)
    VALUES (v.id, 'revertido', 'examen', NULL, auth.uid());

  -- A diferencia de liberar: sin INSERT en notificaciones_pacientes y sin push_notificar.
  RETURN jsonb_build_object('examen', v.id, 'revertido', true);
END;
$function$;

-- --------------------------------------------------------------- (i) paciente_examenes()
-- DROP + CREATE porque cambia el RETURNS TABLE. 0 dependientes (precondicion). corregido = el
-- paciente ya veia el examen cuando se corrigio (revision con liberado_al_corregir) y hoy lo ve.
DROP FUNCTION public.paciente_examenes();
CREATE FUNCTION public.paciente_examenes()
 RETURNS TABLE(id integer, tipo text, descripcion text, fecha_solicitud date, fecha_resultado date, estado text, resultados text, archivo_url text, notas text, created_at timestamp with time zone, medico_nombre text, liberado_al_paciente boolean, en_revision boolean, corregido boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT e.id, e.tipo, e.descripcion, e.fecha_solicitud,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.fecha_resultado END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN 'en_proceso' ELSE e.estado::text END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.resultados END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.archivo_url END,
    CASE WHEN e.estado::text='completado' AND NOT e.liberado_al_paciente THEN NULL ELSE e.notas END,
    e.created_at, p.nombre_completo, e.liberado_al_paciente,
    (e.estado::text='completado' AND NOT e.liberado_al_paciente) AS en_revision,
    (e.liberado_al_paciente AND EXISTS (SELECT 1 FROM public.examen_revisiones r
                                          WHERE r.examen_id = e.id AND r.liberado_al_corregir)) AS corregido
  FROM public.examenes e
  LEFT JOIN public.perfiles p ON p.id = e.medico_id
  WHERE e.paciente_id IN (SELECT pac.id FROM public.pacientes pac WHERE pac.auth_user_id = auth.uid())
  ORDER BY e.fecha_solicitud DESC;
$function$;
-- una funcion nueva nace con EXECUTE a PUBLIC y con los default privileges: ACL = la previa exacta
REVOKE ALL ON FUNCTION public.paciente_examenes() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.paciente_examenes() TO authenticated, service_role;

-- ------------------------------------------------------------------------------ (j) storage
-- Sin UPDATE: un objeto del bucket no se sobrescribe (el front sube con upsert:false desde 22adc27).
DROP POLICY resultados_scoped_update ON storage.objects;
-- DELETE: mismo tenant; y el objeto no puede estar referenciado, tampoco por el historial.
DROP POLICY resultados_scoped_delete ON storage.objects;
CREATE POLICY resultados_scoped_delete ON storage.objects
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
    AND NOT private.path_resultado_referenciado(name)
  );

-- ------------------------------------------------------------------------------- (k) REVOKE
REVOKE MAINTAIN, TRUNCATE, TRIGGER, REFERENCES ON public.examenes FROM authenticated, anon, PUBLIC;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; n int; r record;
BEGIN
  -- (a)(b) tablas: RLS + FORCE, una policy SELECT con el helper, FK RESTRICT, constraints, grants
  FOR r IN SELECT * FROM (VALUES
      ('public.examen_revisiones',         'examen_rev_select'),
      ('public.examen_liberacion_eventos', 'examen_lib_ev_select')) v(tb, pol) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = r.tb::regclass AND relrowsecurity AND relforcerowsecurity) THEN
      bad := bad||r.tb||' sin RLS/FORCE; '; END IF;
    SELECT string_agg(p.policyname||':'||p.cmd||':'||p.roles::text||':'||COALESCE(p.qual,'-')||':'||COALESCE(p.with_check,'-'), ',')
      INTO x FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = split_part(r.tb, '.', 2);
    IF x IS DISTINCT FROM r.pol||':SELECT:{authenticated}:private.puede_ver_historial_examen(examen_id):-' THEN
      bad := bad||'policies '||r.tb||'='||COALESCE(x,'-')||'; '; END IF;
    SELECT string_agg(g, ',' ORDER BY g COLLATE "C") INTO x
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type AS g
              FROM pg_class c, aclexplode(c.relacl) a
             WHERE c.oid = r.tb::regclass AND a.grantee <> c.relowner) z;
    IF x IS DISTINCT FROM 'authenticated:SELECT,service_role:DELETE,service_role:INSERT,service_role:SELECT,service_role:UPDATE' THEN
      bad := bad||'grants '||r.tb||'='||COALESCE(x,'-')||'; '; END IF;
    SELECT count(*) INTO n FROM pg_class c, aclexplode(c.relacl) a
     WHERE c.oid = pg_get_serial_sequence(r.tb, 'id')::regclass
       AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('authenticated','anon'));
    IF n <> 0 THEN bad := bad||'secuencia de '||r.tb||' con grants a authenticated/anon/PUBLIC; '; END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
      ('examen_revisiones_examen_id_fkey',         'public.examen_revisiones'),
      ('examen_liberacion_eventos_examen_id_fkey', 'public.examen_liberacion_eventos')) v(fk, tb) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = r.fk AND conrelid = r.tb::regclass AND contype = 'f'
         AND confrelid = 'public.examenes'::regclass AND confdeltype = 'r') THEN bad := bad||r.fk||' no RESTRICT; '; END IF;
  END LOOP;
  SELECT string_agg(conname||':'||contype::text, ',' ORDER BY conname COLLATE "C") INTO x FROM pg_constraint
   WHERE conrelid = 'public.examen_revisiones'::regclass AND contype IN ('c','u','p');
  IF x IS DISTINCT FROM 'examen_revisiones_examen_revision_key:u,examen_revisiones_motivo_check:c,examen_revisiones_pkey:p' THEN
    bad := bad||'constraints revisiones='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(conname||':'||contype::text, ',' ORDER BY conname COLLATE "C") INTO x FROM pg_constraint
   WHERE conrelid = 'public.examen_liberacion_eventos'::regclass AND contype IN ('c','u','p');
  IF x IS DISTINCT FROM 'examen_liberacion_eventos_evento_check:c,examen_liberacion_eventos_pkey:p,examen_liberacion_eventos_via_check:c' THEN
    bad := bad||'constraints eventos='||COALESCE(x,'-')||'; '; END IF;
  -- triggers: tipo (bits de tgtype), funcion y habilitados; el de identidad de la 332 intacto
  FOR r IN SELECT * FROM (VALUES
      ('trg_examenes_resultado_congelado', 'public.examenes',                  19, 'private.examenes_resultado_congelado()'),
      ('trg_examen_rev_inmutable',         'public.examen_revisiones',         27, 'private.historial_examen_inmutable()'),
      ('trg_examen_lib_inmutable',         'public.examen_liberacion_eventos', 27, 'private.historial_examen_inmutable()'),
      ('trg_examenes_congelar_identidad',  'public.examenes',                  19, 'private.examenes_congelar_identidad()')) v(tg, tb, ty, fn) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = r.tg AND t.tgrelid = r.tb::regclass AND t.tgtype = r.ty
         AND t.tgfoid = to_regprocedure(r.fn) AND t.tgenabled = 'O') THEN bad := bad||'trigger '||r.tg||'; '; END IF;
  END LOOP;
  SELECT pg_get_triggerdef(t.oid) INTO x FROM pg_trigger t WHERE t.tgname = 'trg_examenes_resultado_congelado';
  IF COALESCE(x, '') NOT LIKE '%BEFORE UPDATE OF resultados, archivo_url, fecha_resultado, estado ON public.examenes FOR EACH ROW%' THEN
    bad := bad||'columnas del congelamiento='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(tgname, ',' ORDER BY tgname COLLATE "C") INTO x FROM pg_trigger WHERE tgrelid = 'public.examenes'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_examenes_congelar_identidad,trg_examenes_resultado_congelado' THEN bad := bad||'triggers de examenes='||COALESCE(x,'-')||'; '; END IF;
  -- funciones nuevas: DEFINER, search_path vacio, EXECUTE exacto
  FOR r IN SELECT * FROM (VALUES
      ('public.corregir_resultado_examen(integer,text,text,text)', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.puede_ver_historial_examen(integer)',              '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.path_resultado_referenciado(text)',                '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.examenes_resultado_congelado()',                   '{postgres=X/postgres}'),
      ('private.historial_examen_inmutable()',                     '{postgres=X/postgres}'),
      ('private.notificar_resultado_corregido(integer)',           '{postgres=X/postgres}')) v(f, acl) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND p.prosecdef
         AND p.proconfig = ARRAY['search_path=""'] AND p.proacl::text = r.acl) THEN
      SELECT COALESCE(p.prosecdef::text,'-')||' '||COALESCE(p.proconfig::text,'-')||' '||COALESCE(p.proacl::text,'-') INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
      bad := bad||r.f||' ('||COALESCE(x,'NO EXISTE')||'); '; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc WHERE proname = 'corregir_resultado_examen';
  IF n <> 1 THEN bad := bad||n||' firmas de corregir_resultado_examen; '; END IF;
  -- (h) las 3 funciones modificadas: md5 distinto del previo, escriben el evento, LF, misma ACL/DEFINER
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)', '7c980b20f713d0cf49e7235da30838e1'),
      ('public.liberar_orden_al_paciente(uuid)',     '96a54d314911a439af77e426ebe46611'),
      ('public.revertir_liberacion_examen(integer)', '4a7f4912f3330543d2d7a47b2a06fbc6')) v(f, m_pre) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND md5(p.prosrc) <> r.m_pre
         AND p.prosrc LIKE '%INSERT INTO public.examen_liberacion_eventos%' AND position(E'\r' in p.prosrc) = 0
         AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
         AND p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}') THEN
      bad := bad||r.f||' no quedo con su evento; '; END IF;
  END LOOP;
  -- (i) paciente_examenes: firma unica, columna corregido, ACL exacta (anon y PUBLIC sin EXECUTE)
  SELECT count(*) INTO n FROM pg_proc WHERE proname = 'paciente_examenes';
  IF n <> 1 THEN bad := bad||n||' firmas de paciente_examenes; '; END IF;
  SELECT pg_get_function_result(p.oid)||' | '||p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text,'-')||' '||COALESCE(p.proacl::text,'-')
    INTO x FROM pg_proc p WHERE p.oid = to_regprocedure('public.paciente_examenes()');
  IF x IS DISTINCT FROM 'TABLE(id integer, tipo text, descripcion text, fecha_solicitud date, fecha_resultado date, estado text, resultados text, archivo_url text, notas text, created_at timestamp with time zone, medico_nombre text, liberado_al_paciente boolean, en_revision boolean, corregido boolean) | true s {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'paciente_examenes='||COALESCE(x,'NO EXISTE')||'; '; END IF;
  IF has_function_privilege('anon', 'public.paciente_examenes()', 'EXECUTE') THEN bad := bad||'anon con EXECUTE en paciente_examenes; '; END IF;
  -- funciones que no se tocan
  FOR r IN SELECT * FROM (VALUES
      ('public.notificar_resultado_examen(integer)',                  '33a7a110c39574c5a40f7ca1495d2686'),
      ('public.notificar_orden_lab(uuid)',                            '59fafc8572840548c27ad39a759cba47'),
      ('private.puede_ver_examen(integer)',                           '2b8150875b99dfb5df9fdb3d8af62ae0'),
      ('public.registrar_examen_adjunto(integer,text,text)',          '245fb6669aa3fb22f8e62ca40a8b3467'),
      ('public.contexto_ia_paciente(bigint)',                         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('private.examenes_congelar_identidad()',                       'f0ff903d5c5af6e137ba6b6aed0bad9a'),
      ('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)',    '79a994588ab2b4458135272efb59b867'),
      ('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)', '434d122370e340d895c8540a290379f3'),
      ('private.exigir_empresa_activa()',                             'd62cc5a3c6edf0aaf48488e59a8d1e9b')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- (j) storage: sin UPDATE; la DELETE usa el helper; el resto del bucket igual
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND (policyname LIKE 'resultados%' OR qual LIKE '%resultados-examenes%' OR with_check LIKE '%resultados-examenes%');
  IF x IS DISTINCT FROM 'resultados_scoped_delete:DELETE,resultados_scoped_insert:INSERT,resultados_scoped_select:SELECT' THEN
    bad := bad||'policies del bucket='||COALESCE(x,'-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_delete'
       AND roles::text = '{authenticated}' AND with_check IS NULL
       AND qual = '((bucket_id = ''resultados-examenes''::text) AND ((split_part(name, ''/''::text, 1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY[''super_admin''::text])) AND (NOT private.path_resultado_referenciado(name)))') THEN
    SELECT qual INTO x FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_delete';
    bad := bad||'resultados_scoped_delete='||COALESCE(x,'-')||'; '; END IF;
  -- (k) examenes: authenticated sin MAINTAIN; grants por columna de la 332 iguales
  SELECT relacl::text INTO x FROM pg_class WHERE oid = 'public.examenes'::regclass;
  IF x IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=rd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(p, ',' ORDER BY p) INTO x FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
   WHERE has_table_privilege('anon', 'public.examenes', p);
  IF x IS NOT NULL THEN bad := bad||'anon en examenes='||x||'; '; END IF;
  SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attname) INTO x FROM pg_attribute a
   WHERE a.attrelid = 'public.examenes'::regclass AND a.attacl IS NOT NULL;
  IF x IS DISTINCT FROM 'archivo_url={authenticated=w/postgres},estado={authenticated=w/postgres},fecha_resultado={authenticated=w/postgres},resultados={authenticated=w/postgres}' THEN
    bad := bad||'grants por columna de examenes='||COALESCE(x,'-')||'; '; END IF;
  -- datos: la migracion no crea historia ni cambia ninguna fila de examenes
  SELECT count(*) INTO n FROM public.examen_revisiones;
  IF n <> 0 THEN bad := bad||n||' revision(es) creadas por la migracion; '; END IF;
  SELECT count(*) INTO n FROM public.examen_liberacion_eventos;
  IF n <> 0 THEN bad := bad||n||' evento(s) creados por la migracion; '; END IF;
  SELECT md5(COALESCE(string_agg(to_jsonb(e)::text, '|' ORDER BY e.id), '')) INTO x FROM public.examenes e;
  IF x IS DISTINCT FROM (SELECT s.examenes FROM _snap335 s) THEN bad := bad||'el contenido de examenes cambio; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG335 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
