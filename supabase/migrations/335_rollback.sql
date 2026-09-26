-- ############################################################################################
-- 335 ROLLBACK - vuelve examenes / storage resultados-examenes / funciones de liberacion al pre-335
-- ############################################################################################
-- Quita: la RPC corregir_resultado_examen, las tablas examen_revisiones y examen_liberacion_eventos
-- (con sus triggers y policies), los helpers private.puede_ver_historial_examen,
-- private.path_resultado_referenciado, private.historial_examen_inmutable,
-- private.notificar_resultado_corregido y private.examenes_resultado_congelado, y el trigger
-- trg_examenes_resultado_congelado.
-- Restaura: liberar_examen_al_paciente, liberar_orden_al_paciente, revertir_liberacion_examen y
-- paciente_examenes() con su cuerpo previo EXACTO (pg_get_functiondef medido el 26-sep, verificado
-- por md5); resultados_scoped_update y resultados_scoped_delete con su texto original; MAINTAIN de
-- authenticated en examenes.
--
-- C6: el prosrc previo de liberar_examen_al_paciente es CRLF (27 \r, 27 \n). El archivo se queda en
-- LF: el cuerpo va en LF como literal $body$ y se restaura con replace(E'\n', E'\r\n'). Precondicion
-- md5 del cuerpo LF = 51d4bbfd... (si alguien edita el literal, aborta antes de tocar nada) y
-- autochequeo md5(prosrc) = 7c980b20... exacto.
--
-- NO RESTAURA (costo de volver atras): las revisiones y los eventos acumulados se pierden con el DROP
-- de las tablas, y los resultados corregidos quedan con su ultima version. Exportarlos ANTES.
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE bad text := ''; x text;
BEGIN
  -- se deshace una 335 aplicada: sus objetos tienen que estar
  IF to_regclass('public.examen_revisiones') IS NULL THEN bad := bad||'examen_revisiones no existe; '; END IF;
  IF to_regclass('public.examen_liberacion_eventos') IS NULL THEN bad := bad||'examen_liberacion_eventos no existe; '; END IF;
  IF to_regprocedure('public.corregir_resultado_examen(integer,text,text,text)') IS NULL THEN bad := bad||'corregir_resultado_examen no existe; '; END IF;
  SELECT pg_get_function_result(oid) INTO x FROM pg_proc WHERE oid = to_regprocedure('public.paciente_examenes()');
  IF COALESCE(x, '') NOT LIKE '%corregido boolean)' THEN bad := bad||'paciente_examenes sin corregido; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK335 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- ------------------------------------------------------------------------------ storage
DROP POLICY resultados_scoped_delete ON storage.objects;
CREATE POLICY resultados_scoped_delete ON storage.objects
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
    AND NOT EXISTS (
      SELECT 1 FROM public.examen_adjuntos a
       WHERE a.storage_path = storage.objects.name)
    AND NOT EXISTS (
      SELECT 1 FROM public.examenes e
       WHERE COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/', 2), ''), e.archivo_url) = storage.objects.name)
  );
CREATE POLICY resultados_scoped_update ON storage.objects
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
  )
  WITH CHECK (
    bucket_id = 'resultados-examenes'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
  );

-- -------------------------------------------------------------------- triggers y la RPC
DROP TRIGGER trg_examenes_resultado_congelado ON public.examenes;
DROP FUNCTION public.corregir_resultado_examen(integer, text, text, text);

-- ------------------------------------------------------- funciones previas, cuerpo exacto
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
     RETURNING e.paciente_id
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

  -- A diferencia de liberar: sin INSERT en notificaciones_pacientes y sin push_notificar.
  RETURN jsonb_build_object('examen', v.id, 'revertido', true);
END;
$function$;

-- C6: liberar_examen_al_paciente vuelve con su prosrc CRLF exacto
DO $restaura$
DECLARE v_body text;
BEGIN
  v_body := $body$
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
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen disponible',
              'Tu medico libero un resultado de examen. Ya puedes verlo.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
  RETURN jsonb_build_object('examen', v.id, 'liberado', true);
END; $body$;
  IF md5(v_body) IS DISTINCT FROM '51d4bbfdef169a16271a49ea0d218cc2' THEN
    RAISE EXCEPTION 'ROLLBACK335: cuerpo LF de liberar_examen_al_paciente alterado (md5 %)', md5(v_body);
  END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public.liberar_examen_al_paciente(p_examen_id integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO %L AS %L',
                 '', replace(v_body, E'\n', E'\r\n'));
END $restaura$;

DROP FUNCTION public.paciente_examenes();
CREATE OR REPLACE FUNCTION public.paciente_examenes()
 RETURNS TABLE(id integer, tipo text, descripcion text, fecha_solicitud date, fecha_resultado date, estado text, resultados text, archivo_url text, notas text, created_at timestamp with time zone, medico_nombre text, liberado_al_paciente boolean, en_revision boolean)
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
    (e.estado::text='completado' AND NOT e.liberado_al_paciente) AS en_revision
  FROM public.examenes e
  LEFT JOIN public.perfiles p ON p.id = e.medico_id
  WHERE e.paciente_id IN (SELECT pac.id FROM public.pacientes pac WHERE pac.auth_user_id = auth.uid())
  ORDER BY e.fecha_solicitud DESC;
$function$;
REVOKE ALL ON FUNCTION public.paciente_examenes() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.paciente_examenes() TO authenticated, service_role;

-- ------------------------------------------------------------- tablas y helpers de la 335
DROP TABLE public.examen_liberacion_eventos;
DROP TABLE public.examen_revisiones;
DROP FUNCTION private.puede_ver_historial_examen(integer);
DROP FUNCTION private.path_resultado_referenciado(text);
DROP FUNCTION private.historial_examen_inmutable();
DROP FUNCTION private.notificar_resultado_corregido(integer);
DROP FUNCTION private.examenes_resultado_congelado();

-- ---------------------------------------------------------------------------------- grants
GRANT MAINTAIN ON public.examenes TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; r record; n int;
BEGIN
  -- objetos de la 335, ausentes
  IF to_regclass('public.examen_revisiones') IS NOT NULL THEN bad := bad||'examen_revisiones sigue; '; END IF;
  IF to_regclass('public.examen_liberacion_eventos') IS NOT NULL THEN bad := bad||'examen_liberacion_eventos sigue; '; END IF;
  SELECT string_agg(p.oid::regprocedure::text, ',') INTO x FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname = 'public' AND p.proname = 'corregir_resultado_examen')
      OR (ns.nspname = 'private' AND p.proname IN ('puede_ver_historial_examen','examenes_resultado_congelado','path_resultado_referenciado',
                                                    'historial_examen_inmutable','notificar_resultado_corregido'));
  IF x IS NOT NULL THEN bad := bad||'funciones siguen: '||x||'; '; END IF;
  SELECT string_agg(tgname, ',' ORDER BY tgname COLLATE "C") INTO x FROM pg_trigger WHERE tgrelid = 'public.examenes'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_examenes_congelar_identidad' THEN bad := bad||'triggers de examenes='||COALESCE(x,'-')||'; '; END IF;
  -- las 4 funciones restauradas: md5 exacto y cabecera igual al snapshot PRE
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)', '7c980b20f713d0cf49e7235da30838e1', 'v', '27/27'),
      ('public.liberar_orden_al_paciente(uuid)',     '96a54d314911a439af77e426ebe46611', 'v', '0/25'),
      ('public.revertir_liberacion_examen(integer)', '4a7f4912f3330543d2d7a47b2a06fbc6', 'v', '0/42'),
      ('public.paciente_examenes()',                 'a14ea485045b28883d81a0dd9fe7cd83', 's', '0/13')) v(f, m, vol, crlf) LOOP
    SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text,'-')||' '||COALESCE(p.proacl::text,'-')||' '||
           (length(p.prosrc) - length(replace(p.prosrc, E'\r', '')))::text||'/'||(length(p.prosrc) - length(replace(p.prosrc, E'\n', '')))::text
      INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m||' true '||r.vol||' {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} '||r.crlf THEN
      bad := bad||r.f||' ('||COALESCE(x,'NO EXISTE')||'); '; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc WHERE proname = 'paciente_examenes';
  IF n <> 1 THEN bad := bad||n||' firmas de paciente_examenes; '; END IF;
  SELECT pg_get_function_result(oid) INTO x FROM pg_proc WHERE oid = to_regprocedure('public.paciente_examenes()');
  IF x IS DISTINCT FROM 'TABLE(id integer, tipo text, descripcion text, fecha_solicitud date, fecha_resultado date, estado text, resultados text, archivo_url text, notas text, created_at timestamp with time zone, medico_nombre text, liberado_al_paciente boolean, en_revision boolean)' THEN
    bad := bad||'RETURNS de paciente_examenes='||COALESCE(x,'-')||'; '; END IF;
  -- las que la 335 no toca
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
  -- storage: las 4 policies del bucket y las dos restauradas con su texto PRE exacto
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND (policyname LIKE 'resultados%' OR qual LIKE '%resultados-examenes%' OR with_check LIKE '%resultados-examenes%');
  IF x IS DISTINCT FROM 'resultados_scoped_delete:DELETE,resultados_scoped_insert:INSERT,resultados_scoped_select:SELECT,resultados_scoped_update:UPDATE' THEN
    bad := bad||'policies del bucket='||COALESCE(x,'-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_update'
       AND cmd = 'UPDATE' AND permissive = 'PERMISSIVE' AND roles::text = '{authenticated}'
       AND qual = '((bucket_id = ''resultados-examenes''::text) AND ((split_part(name, ''/''::text, 1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY[''super_admin''::text])))'
       AND with_check = qual) THEN
    bad := bad||'resultados_scoped_update distinta de la PRE; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_delete'
       AND cmd = 'DELETE' AND permissive = 'PERMISSIVE' AND roles::text = '{authenticated}' AND with_check IS NULL
       AND qual = '((bucket_id = ''resultados-examenes''::text) AND ((split_part(name, ''/''::text, 1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY[''super_admin''::text])) AND (NOT (EXISTS ( SELECT 1'||E'\n'||'   FROM examen_adjuntos a'||E'\n'||'  WHERE (a.storage_path = objects.name)))) AND (NOT (EXISTS ( SELECT 1'||E'\n'||'   FROM examenes e'||E'\n'||'  WHERE (COALESCE(NULLIF(split_part(e.archivo_url, ''/resultados-examenes/''::text, 2), ''''::text), e.archivo_url) = objects.name)))))') THEN
    SELECT qual INTO x FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_delete';
    bad := bad||'resultados_scoped_delete distinta de la PRE ('||COALESCE(x,'-')||'); '; END IF;
  -- examenes: la ACL PRE exacta y los grants por columna de la 332
  SELECT relacl::text INTO x FROM pg_class WHERE oid = 'public.examenes'::regclass;
  IF x IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=rdm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attname) INTO x FROM pg_attribute a
   WHERE a.attrelid = 'public.examenes'::regclass AND a.attacl IS NOT NULL;
  IF x IS DISTINCT FROM 'archivo_url={authenticated=w/postgres},estado={authenticated=w/postgres},fecha_resultado={authenticated=w/postgres},resultados={authenticated=w/postgres}' THEN
    bad := bad||'grants por columna de examenes='||COALESCE(x,'-')||'; '; END IF;
  IF has_function_privilege('anon', 'public.paciente_examenes()', 'EXECUTE') THEN bad := bad||'anon con EXECUTE en paciente_examenes; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK335 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
