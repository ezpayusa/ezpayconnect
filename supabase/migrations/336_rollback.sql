-- ############################################################################################
-- 336 ROLLBACK - vuelve liberar_examen_al_paciente, revertir_liberacion_examen y
--                corregir_resultado_examen a sus cuerpos EXACTOS de la 335
-- ############################################################################################
-- Los tres cuerpos de abajo se copiaron por programa desde 335_examen_revisiones.sql (no se
-- reescribieron): el autochequeo exige los md5 post-335 (b701e61c / b42cb2b6 / 9da28d88).
-- La precondicion exige los md5 post-336: si alguien cambio las funciones despues de la 336, aborta
-- antes de tocar nada. liberar_orden_al_paciente no la toco la 336 y no se toca aca.
-- CREATE OR REPLACE conserva la ACL; el autochequeo la compara contra la capturada.
--
-- Costo de volver atras: reaparecen los dos hallazgos del /code-review del PR #9 (eventos y avisos
-- duplicados por liberacion/reversion concurrente; EX028 que no ve espacios del valor guardado).
-- Las filas de historial que se hayan escrito mientras tanto no se tocan (son append-only).
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE bad text := ''; x text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)',               'd1321b5fd0d994da4605b959249ba3b7'),
      ('public.revertir_liberacion_examen(integer)',               '8884c3445e9f29fa8850beab66a07775'),
      ('public.corregir_resultado_examen(integer,text,text,text)', '9a2a4b5b33e6b6f0bc0ddd454906f848'),
      ('public.liberar_orden_al_paciente(uuid)',                   '10a82b4176a65a58cb46ec5f2dca0447')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK336 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

CREATE TEMP TABLE _acl336r ON COMMIT DROP AS
SELECT p.oid::regprocedure::text AS f, p.proacl::text AS acl
  FROM pg_proc p
 WHERE p.oid IN (to_regprocedure('public.liberar_examen_al_paciente(integer)'),
                 to_regprocedure('public.revertir_liberacion_examen(integer)'),
                 to_regprocedure('public.corregir_resultado_examen(integer,text,text,text)'));

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

CREATE OR REPLACE FUNCTION public.corregir_resultado_examen(
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

DO $chk$
DECLARE bad text := ''; x text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)',               'b701e61cd3f05a3b1f1b382d495a9afb'),
      ('public.revertir_liberacion_examen(integer)',               'b42cb2b6386b348efb351048974ce3af'),
      ('public.corregir_resultado_examen(integer,text,text,text)', '9da28d88037efd9a304efe167a2c098d')) v(f, m) LOOP
    SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text,'-')
      INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m||' true {"search_path=\"\""}' THEN bad := bad||r.f||' ('||COALESCE(x,'NO EXISTE')||'); '; END IF;
    SELECT p.proacl::text INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM (SELECT a.acl FROM _acl336r a WHERE a.f = to_regprocedure(r.f)::text) THEN
      bad := bad||r.f||' ACL '||COALESCE(x,'-')||' distinta de la previa; '; END IF;
    IF has_function_privilege('anon', to_regprocedure(r.f), 'EXECUTE') THEN bad := bad||r.f||' con EXECUTE para anon; '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM _acl336r) <> 3 THEN bad := bad||'ACL previa capturada incompleta; '; END IF;
  SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure('public.liberar_orden_al_paciente(uuid)');
  IF x IS DISTINCT FROM '10a82b4176a65a58cb46ec5f2dca0447' THEN bad := bad||'liberar_orden_al_paciente md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK336 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
