-- ############################################################################################
-- 311 — revertir_liberacion_examen: deshacer la liberacion de un resultado al paciente
-- ############################################################################################
-- Frente 4 de la cola de Fase 4. Diseno cerrado por Oscar el 20-sep sobre el recon del mismo dia.
--
-- POR QUE. `liberar_examen_al_paciente` es de una sola direccion: una vez que el resultado sale,
-- no hay forma de volver atras si se libero el examen equivocado o antes de hablarlo con el
-- paciente. La unica salida era un UPDATE a mano.
--
-- QUIEN PUEDE. EXACTAMENTE los mismos cuatro que pueden liberar, verificado contra el cuerpo vivo
-- de liberar_examen_al_paciente: el medico que ordeno (`medico_id = auth.uid()`), un medico que
-- atiende al paciente, el admin de la clinica del examen, y super_admin.
--
-- EL LABORATORIO NO ENTRA, y es deliberado. El lab VE el examen (policy examenes_laboratorio_all,
-- cmd=ALL) y desde la mig 310 puede adjuntarle archivos, pero nunca pudo liberar. Revertir es la
-- contracara de liberar, asi que alcanza al mismo conjunto: ve y escribe, pero no decide que ve el
-- paciente. La probe P792 lo fija: el lab ve el examen Y recibe PE004.
--
-- AUDITORIA: `fecha_liberacion` y `liberado_por` NO se tocan. Quedan como rastro de que el examen
-- ESTUVO liberado y de quien lo libero; la reversion se registra aparte en las dos columnas nuevas.
-- Borrarlas hubiera dejado la reversion indistinguible de "nunca se libero".
--
-- SIN NOTIFICACION. liberar_examen_al_paciente inserta en notificaciones_pacientes y dispara push.
-- Revertir no: avisarle al paciente "ya no podes ver esto" no tiene valor para el y expone una
-- decision clinica que todavia se esta tomando.
--
-- ERRCODES: PT002 para "examen inexistente" (es el que ya usa toda esta familia para no encontrado;
-- estrenar uno nuevo solo para eso habria roto el patron) y PE004, NUEVO, para sin autoridad.
-- Proximo PE libre despues de esta: PE005.
-- ############################################################################################


-- ============================================================================================
-- 1) Las dos columnas de auditoria de la reversion
-- ============================================================================================
-- Nullable y sin default: un NULL significa "este examen nunca fue revertido", que es el estado
-- de las 11 filas de hoy. Sin FK sobre revertido_por, igual que `liberado_por`, que tampoco la
-- tiene (medido: las unicas FK de examenes son clinica_id, laboratorio_id, medico_id, orden_id y
-- paciente_id). Ponersela solo a la nueva dejaria las dos columnas gemelas con reglas distintas.
ALTER TABLE public.examenes
  ADD COLUMN IF NOT EXISTS revertido_por   uuid,
  ADD COLUMN IF NOT EXISTS fecha_reversion timestamptz;

COMMENT ON COLUMN public.examenes.revertido_por IS
  'Quien revirtio la ultima liberacion (mig 311). NULL = nunca se revirtio. No borra liberado_por.';
COMMENT ON COLUMN public.examenes.fecha_reversion IS
  'Cuando se revirtio la ultima liberacion (mig 311). NULL = nunca se revirtio.';


-- ============================================================================================
-- 2) public.revertir_liberacion_examen(integer)
-- ============================================================================================
-- Calcada en estructura de liberar_examen_al_paciente: mismo SELECT ... INTO, mismo gate, mismo
-- estilo de retorno jsonb. Las diferencias son las que pide el caso y estan comentadas una por una.
CREATE OR REPLACE FUNCTION public.revertir_liberacion_examen(p_examen_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
$fn$;

REVOKE ALL ON FUNCTION public.revertir_liberacion_examen(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revertir_liberacion_examen(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.revertir_liberacion_examen(integer) TO authenticated;


-- ============================================================================================
-- AUTOCHEQUEO 1 — el paciente pierde el examen Y sus adjuntos, medido ANTES y DESPUES
-- ============================================================================================
-- No alcanza con mirar el estado final: si el paciente ya no veia el examen ANTES de revertir, un
-- "no lo ve" despues no prueba nada. Por eso se mide de los dos lados y el chequeo ABORTA si el
-- "antes" no es visible — un control positivo que falla es un chequeo que no mide.
--
-- El adjunto se SIEMBRA: examen_adjuntos esta vacia en prod (la mig 310 esta aplicada pero el
-- front todavia no la usa), asi que este escenario no existe en los datos reales.
--
-- Todo ocurre en una subtransaccion que SIEMPRE aborta, asi que ni el adjunto ni la reversion
-- quedan. Las variables de plpgsql sobreviven al abort; los GUC no, y eso es lo que se quiere.
DO $ac1$
DECLARE
  v_ex int; v_pac uuid; v_med uuid;
  b_ver boolean; b_adj bigint; a_ver boolean; a_adj bigint;
  b_flib timestamptz; b_lpor uuid; a_flib timestamptz; a_lpor uuid;
  a_rpor uuid; a_frev timestamptz; v_res jsonb;
BEGIN
  BEGIN
    SELECT e.id, e.medico_id, p.auth_user_id, e.fecha_liberacion, e.liberado_por
      INTO v_ex, v_med, v_pac, b_flib, b_lpor
      FROM public.examenes e
      JOIN public.pacientes p ON p.id = e.paciente_id
     WHERE e.liberado_al_paciente
       AND p.auth_user_id IS NOT NULL
       AND e.medico_id IS NOT NULL
     ORDER BY e.id LIMIT 1;
    IF v_ex IS NULL THEN RAISE EXCEPTION 'M311_NOFIX'; END IF;

    INSERT INTO public.examen_adjuntos (examen_id, storage_path, mime_type, subido_por)
      VALUES (v_ex, 'm311-ac1/fixture.pdf', 'application/pdf', v_med);

    -- ANTES, con los ojos del paciente
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    b_ver := private.puede_ver_examen(v_ex);
    SELECT count(*) INTO b_adj FROM public.examen_adjuntos a WHERE a.examen_id = v_ex;
    PERFORM set_config('role', 'none', true);

    -- revertir, con los ojos del medico que ordeno
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    v_res := public.revertir_liberacion_examen(v_ex);
    PERFORM set_config('role', 'none', true);

    -- DESPUES, con los ojos del paciente
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    a_ver := private.puede_ver_examen(v_ex);
    SELECT count(*) INTO a_adj FROM public.examen_adjuntos a WHERE a.examen_id = v_ex;
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);

    SELECT e.fecha_liberacion, e.liberado_por, e.revertido_por, e.fecha_reversion
      INTO a_flib, a_lpor, a_rpor, a_frev
      FROM public.examenes e WHERE e.id = v_ex;

    RAISE EXCEPTION 'M311_ROLLBACK_FIXTURE';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM = 'M311_NOFIX' THEN
      RAISE EXCEPTION '311 AC1: no hay examen liberado con paciente con auth_user_id y medico asignado';
    ELSIF SQLERRM <> 'M311_ROLLBACK_FIXTURE' THEN
      RAISE EXCEPTION '311 AC1: fallo midiendo (% %)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- Controles positivos primero: sin ellos, el "despues" no significa nada.
  IF NOT COALESCE(b_ver, false) THEN
    RAISE EXCEPTION '311 AC1: el paciente NO veia el examen ANTES de revertir (b_ver=%) — el chequeo no mide nada',
      COALESCE(b_ver::text, 'NULL');
  END IF;
  IF COALESCE(b_adj, 0) < 1 THEN
    RAISE EXCEPTION '311 AC1: el paciente NO veia el adjunto ANTES de revertir (b_adj=%)', COALESCE(b_adj, -1);
  END IF;
  IF COALESCE(v_res->>'revertido', '') <> 'true' THEN
    RAISE EXCEPTION '311 AC1: la RPC no devolvio {revertido:true}, devolvio %', COALESCE(v_res::text, 'NULL');
  END IF;

  IF COALESCE(a_ver, true) THEN
    RAISE EXCEPTION '311 AC1: el paciente SIGUE viendo el examen despues de revertir';
  END IF;
  IF COALESCE(a_adj, -1) <> 0 THEN
    RAISE EXCEPTION '311 AC1: el paciente SIGUE viendo % adjunto(s) despues de revertir', COALESCE(a_adj, -1);
  END IF;

  -- La auditoria de la liberacion queda intacta y la de la reversion se llena.
  IF a_flib IS DISTINCT FROM b_flib OR a_lpor IS DISTINCT FROM b_lpor THEN
    RAISE EXCEPTION '311 AC1: revertir toco fecha_liberacion/liberado_por (antes % / %, despues % / %)',
      b_flib, b_lpor, a_flib, a_lpor;
  END IF;
  IF a_rpor IS NULL OR a_frev IS NULL THEN
    RAISE EXCEPTION '311 AC1: revertido_por o fecha_reversion quedaron NULL despues de revertir';
  END IF;

  PERFORM set_config('m311.ac1', format(
    'OK (examen %s: el paciente veia examen=%s adjuntos=%s ANTES, y examen=%s adjuntos=%s DESPUES; '
    || 'fecha_liberacion y liberado_por intactas, revertido_por y fecha_reversion llenas)',
    v_ex, b_ver, b_adj, a_ver, a_adj), true);
END $ac1$;


-- ============================================================================================
-- AUTOCHEQUEO 2 — estructura: columnas, firma, ACL
-- ============================================================================================
DO $ac2$
DECLARE v_n int; v_tipos text;
BEGIN
  SELECT string_agg(c.column_name || ' ' || c.data_type || ' null=' || c.is_nullable
                    || ' def=' || COALESCE(c.column_default, 'NINGUNO'), ' | ' ORDER BY c.column_name)
    INTO v_tipos
    FROM information_schema.columns c
   WHERE c.table_schema='public' AND c.table_name='examenes'
     AND c.column_name IN ('revertido_por', 'fecha_reversion');
  IF v_tipos IS NULL OR v_tipos NOT LIKE '%fecha_reversion timestamp with time zone null=YES def=NINGUNO%'
     OR v_tipos NOT LIKE '%revertido_por uuid null=YES def=NINGUNO%' THEN
    RAISE EXCEPTION '311 AC2: las columnas nuevas no quedaron nullable y sin default: %', COALESCE(v_tipos, '(no existen)');
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='revertir_liberacion_examen'
     AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg IN ('search_path=""', 'search_path='));
  IF v_n <> 1 THEN
    RAISE EXCEPTION '311 AC2: revertir_liberacion_examen no quedo SECURITY DEFINER con search_path vacio';
  END IF;

  IF has_function_privilege('anon', 'public.revertir_liberacion_examen(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '311 AC2: anon puede ejecutar revertir_liberacion_examen';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.revertir_liberacion_examen(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '311 AC2: authenticated NO puede ejecutar revertir_liberacion_examen';
  END IF;

  -- El gate tiene que ser LITERALMENTE el mismo conjunto que el de liberar, y sin laboratorio.
  --
  -- SE MIRA EL CUERPO SIN COMENTARIOS. `prosrc` los incluye, y los de esta funcion nombran a
  -- proposito lo que la funcion NO hace ("sin INSERT en notificaciones_pacientes y sin
  -- push_notificar", "el laboratorio NO figura"). La primera version de este chequeo grepeaba
  -- prosrc crudo y abortaba la migracion por sus propios comentarios. Un chequeo que un
  -- comentario puede romper no mide el codigo: mide la prosa.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         LATERAL (SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') AS cuerpo) c
   WHERE n.nspname='public' AND p.proname='revertir_liberacion_examen'
     AND c.cuerpo LIKE '%medico_atiende_paciente%'
     AND c.cuerpo LIKE '%es_admin_clinica%'
     AND c.cuerpo LIKE '%super_admin%'
     AND c.cuerpo LIKE '%COALESCE%'
     AND c.cuerpo LIKE '%revertido_por%'
     AND c.cuerpo LIKE '%fecha_reversion%'
     AND c.cuerpo NOT LIKE '%mi_empresa_proveedor%'
     AND c.cuerpo NOT LIKE '%laboratorio_id%'
     AND c.cuerpo NOT LIKE '%notificaciones_pacientes%'
     AND c.cuerpo NOT LIKE '%push_notificar%'
     AND c.cuerpo NOT LIKE '%fecha_liberacion%'
     AND c.cuerpo NOT LIKE '%liberado_por%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '311 AC2: el cuerpo no cumple la forma esperada (gate con COALESCE, sin laboratorio, sin notificacion, sin tocar fecha_liberacion/liberado_por)';
  END IF;

  PERFORM set_config('m311.ac2',
    'OK (2 columnas nullable sin default; RPC DEFINER sp='''' , anon=false auth=true; cuerpo sin comentarios: gate con COALESCE, sin laboratorio, sin notificacion, sin escribir fecha_liberacion/liberado_por)', true);
END $ac2$;


DO $fin$
BEGIN
  PERFORM set_config('m311.auto',
    'AC1 ' || COALESCE(current_setting('m311.ac1', true), 'FALTA') ||
    ' || AC2 ' || COALESCE(current_setting('m311.ac2', true), 'FALTA'), true);
  RAISE NOTICE '311 OK';
END $fin$;
