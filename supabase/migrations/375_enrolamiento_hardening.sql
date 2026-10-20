-- ############################################################################################
-- 375 - Hardening del enrolamiento de medicos (lab enrolador y prioridad de visitas)
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\mig375\: vivo_*.sql = pg_get_functiondef de las 4 funciones,
--   recon1-5.sql/.json). Estado vivo medido:
--   - md5(prosrc): enrolar_medico 58387ef76ce0b9589a8a3d3d66fbad23, prioridad_activa 8cf68b2cccbdca78a2515e1c4b4265dc,
--     trg_gate_head_start_lab 835096c89cb6828048ac40bc04975b37, trg_medicos_lab_enrolador_inmutable
--     a8c115d820012b413d82950b70f4817a, administrar_visita 666800e7be6ccee444632f933d5146c0. Las 4 primeras con
--     search_path = public; las 2 de trigger INVOKER; ACL de las 4 {postgres, authenticated, service_role}.
--   - Triggers: trigger_medicos_lab_enrolador_inmutable BEFORE UPDATE ON medicos (solo miraba que lab_enrolador_id no
--     cambie una vez puesto); trigger_gate_head_start_lab BEFORE INSERT ON visitas_agendadas.
--   - medicos: 13 filas, 16 columnas, sin attacl (authenticated SELECT/INSERT/UPDATE/DELETE de tabla); 1 sola enrolada
--     (medico.qa 09d243d5-b222-482a-9762-94a582e9e752, lab 411d6f8c-a405-49d6-9ed6-fbeb0db05133 laboratorio_farmaceutico
--     activa) y con lab_enrolador_fecha NULL.
--   - Lectores de medicos con sesion de usuario: ninguna funcion INVOKER, ninguna vista, ninguna policy de otra tabla;
--     el front y las edges nombran columnas (sin select('*') ni embeds con *); nadie lee lab_enrolador_* ni llama a
--     prioridad_activa (solo trg_gate_head_start_lab).
--   - Escritores de visitas_agendadas: solo administrar_visita('reprogramar') pone fecha_visita en el SET, y lo hace con
--     COALESCE(p_nueva_fecha, fecha_visita); ninguno pone medico_id.
--
-- Que cierra:
--   (a) authenticated tenia UPDATE de tabla en medicos: el medico (medicos_update_propio) y el admin de clinica/pais se
--       podian poner o sacar lab_enrolador_id/fecha a mano (el trigger viejo solo frenaba el CAMBIO de un id ya puesto) y
--       fabricarse o anularse una prioridad. Ahora solo enrolar_medico escribe el par (GUC app.enrolamiento_rpc, que pone
--       y limpia la RPC en su transaccion; PostgREST no expone set_config, asi que el cliente no lo puede encender).
--   (b) enrolar_medico no miraba el tipo de empresa ni el rol: cualquier cuenta de proveedor con la capacidad podia
--       enrolar. Ahora PV016 (no es laboratorio_farmaceutico) y PV017 (rol fuera de admin/supervisor/visitador_medico).
--   (c) prioridad_activa se podia llamar por API (quien enrolo a cada medico y cuantas visitas lleva): solo service_role;
--       el trigger del head-start pasa a DEFINER para seguir llamandola desde un INSERT de authenticated.
--   (d) el head-start solo se miraba al crear la visita: reprogramar a una fecha dentro de la ventana lo esquivaba. Ahora
--       el trigger tambien corre en UPDATE OF fecha_visita, medico_id, y solo si alguno de los dos CAMBIA de valor (un
--       cambio de solo hora por 'reprogramar' deja fecha_visita igual y no se re-evalua).
--   (e) lab_enrolador_id/fecha dejan de ser legibles por authenticated (grants por columna; los lee la RPC, que es DEFINER).
--   (f) search_path = '' en las 4 funciones (regla 13 para las 3 DEFINER; el guard tambien, por consistencia).
--
-- Dato: medico.qa pasa a tener lab_enrolador_fecha = now() (la del apply). Efecto: su ventana de prioridad (8 visitas /
--   18 meses) arranca en el apply. Antes, con fecha NULL, prioridad_activa devolvia activa = NULL y el trigger igual
--   aplicaba el head-start (IF NOT NULL no entra): para los demas labs no cambia nada.
--
-- Numeros: mig 375; errcodes PV015 (guard del enrolamiento), PV016 (tipo de empresa), PV017 (rol); PV001-PV002 y
--   PV010-PV014 en uso, PV015-PV017 sin uso en prod ni en el repo (medido el 20-oct-2026). Probes P1041+.
--
-- Privilegios: ACL de funciones 027e10a7b66101b4f5bb85c475c34045/392 -> 9c59aecab498bbcb54ebe799b2fb6a3d/392 (salen
--   prioridad_activa y trg_gate_head_start_lab de authenticated); ACL de relaciones de public d065decf.../2394 ->
--   1889d1d89630994fe0d8faa1c52c4fd8/2393 (sale el SELECT de tabla de authenticated en medicos); las dos CALCULADAS
--   con un SELECT sobre el estado vivo (recon5.sql), a confirmar en el dry-run. Policies 8a8dc5cf.../309 sin cambio.
--   SELECT por columna en las 14 columnas restantes de medicos (P800 regla (b): authenticated sigue con privilegio).
--
-- Front: PV015-PV017 no estan mapeados (no hay mapeo de PV en src/). enrolar_medico no tiene llamadores en el front hoy.
--
-- Rollback: 375_rollback.sql. Orden global: 375_rollback -> 374_rollback -> 373_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones (estado post-374)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- cuerpos vivos
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.enrolar_medico(uuid)'));
  IF v IS DISTINCT FROM '58387ef76ce0b9589a8a3d3d66fbad23' THEN bad := bad||'enrolar_medico md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.prioridad_activa(uuid)'));
  IF v IS DISTINCT FROM '8cf68b2cccbdca78a2515e1c4b4265dc' THEN bad := bad||'prioridad_activa md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.trg_gate_head_start_lab()'));
  IF v IS DISTINCT FROM '835096c89cb6828048ac40bc04975b37' THEN bad := bad||'trg_gate_head_start_lab md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.trg_medicos_lab_enrolador_inmutable()'));
  IF v IS DISTINCT FROM 'a8c115d820012b413d82950b70f4817a' THEN bad := bad||'trg_medicos_lab_enrolador_inmutable md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  -- administrar_visita: su UPDATE de 'reprogramar' es el unico que dispara el trigger nuevo en UPDATE (recon4)
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF v IS DISTINCT FROM '666800e7be6ccee444632f933d5146c0' THEN bad := bad||'administrar_visita md5 '||COALESCE(v, 'no existe')||'; '; END IF;

  -- triggers vivos (tgtype: 1 ROW, 2 BEFORE, 4 INSERT, 16 UPDATE)
  v := (SELECT t.tgtype::text||'|'||t.tgattr::text||'|'||t.tgfoid::regproc::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.medicos'::regclass AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable');
  IF v IS DISTINCT FROM '19||trg_medicos_lab_enrolador_inmutable|O' THEN bad := bad||'trigger de medicos '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT t.tgtype::text||'|'||t.tgattr::text||'|'||t.tgfoid::regproc::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND t.tgname = 'trigger_gate_head_start_lab');
  IF v IS DISTINCT FROM '7||trg_gate_head_start_lab|O' THEN bad := bad||'trigger del head-start '||COALESCE(v, 'no existe')||'; '; END IF;

  -- medicos: 13 filas, las 16 columnas conocidas, sin grants por columna, sin el CHECK, y la unica incoherente es medico.qa
  IF (SELECT count(*) FROM public.medicos) <> 13 THEN bad := bad||'count(medicos) '||(SELECT count(*) FROM public.medicos)||'; '; END IF;
  v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'id,clinica_id,nombre_completo,especialidad,telefono,email,cedula_profesional,horario_atencion,activo,created_at,updated_at,pais_id,foto_url,especialidad_id,lab_enrolador_id,lab_enrolador_fecha' THEN
    bad := bad||'columnas de medicos ['||COALESCE(v, '-')||']; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL) THEN
    bad := bad||'medicos ya tiene grants por columna; ';
  END IF;
  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos '||COALESCE(v, 'NULL')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.medicos'::regclass AND c.conname = 'medicos_enrolador_coherente') THEN
    bad := bad||'medicos_enrolador_coherente ya existe; ';
  END IF;
  v := (SELECT string_agg(m.id::text, ',' ORDER BY m.id) FROM public.medicos m
         WHERE (m.lab_enrolador_id IS NULL) <> (m.lab_enrolador_fecha IS NULL));
  IF v IS DISTINCT FROM '09d243d5-b222-482a-9762-94a582e9e752' THEN bad := bad||'filas incoherentes ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- errcodes libres
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.prosrc ~ 'PV01[5-7]');
  IF v IS NOT NULL THEN bad := bad||'PV015-PV017 ya aparecen en: '||v||'; '; END IF;

  -- huellas post-374
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '027e10a7b66101b4f5bb85c475c34045 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG375_PRE FALLA:%', bad; END IF;

  -- huella de TODAS las funciones de public/private salvo las 4 que toca esta migracion (cuerpo, DEFINER, config, ACL):
  -- el autochequeo exige que quede igual (ningun efecto colateral sobre otra funcion)
  CREATE TEMP TABLE mig375_huella ON COMMIT DROP AS
    SELECT md5(string_agg(p.oid::regprocedure::text||'|'||md5(p.prosrc)||'|'||p.prosecdef::text||'|'||
                          COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-'), E'\n'
                          ORDER BY p.oid::regprocedure::text COLLATE "C")) AS h,
           count(*) AS n
      FROM pg_proc p
     WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
       AND p.oid NOT IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                         'public.trg_gate_head_start_lab()'::regprocedure, 'public.trg_medicos_lab_enrolador_inmutable()'::regprocedure);
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: dato (ANTES del guard nuevo)
DO $dato$
DECLARE n int;
BEGIN
  UPDATE public.medicos SET lab_enrolador_fecha = now()
   WHERE lab_enrolador_id IS NOT NULL AND lab_enrolador_fecha IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'MIG375 DATO: se esperaba 1 fila (medico.qa), se actualizaron %', n; END IF;
END $dato$;

-- ---------------------------------------------------------------------------- 2: CHECK de coherencia
ALTER TABLE public.medicos ADD CONSTRAINT medicos_enrolador_coherente
  CHECK ((lab_enrolador_id IS NULL) = (lab_enrolador_fecha IS NULL));

-- ---------------------------------------------------------------------------- 3: guard del enrolamiento
CREATE OR REPLACE FUNCTION public.trg_medicos_lab_enrolador_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  -- Lo enciende y lo apaga enrolar_medico alrededor de su UPDATE (set_config local a la transaccion).
  v_rpc boolean := current_setting('app.enrolamiento_rpc', true) IS NOT DISTINCT FROM 'on';
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF (NEW.lab_enrolador_id IS NOT NULL OR NEW.lab_enrolador_fecha IS NOT NULL) AND NOT v_rpc THEN
      RAISE EXCEPTION 'No puedes crear un médico ya enrolado: el enrolamiento solo se hace desde el portal del laboratorio.'
        USING ERRCODE = 'PV015';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: una vez puesto, el laboratorio enrolador no cambia ni se quita, ni siquiera desde la RPC.
  IF OLD.lab_enrolador_id IS NOT NULL AND NEW.lab_enrolador_id IS DISTINCT FROM OLD.lab_enrolador_id THEN
    RAISE EXCEPTION 'Este médico ya tiene laboratorio enrolador y no puedes cambiarlo ni quitarlo.'
      USING ERRCODE = 'PV015';
  END IF;

  -- UPDATE: el par (laboratorio, fecha) solo lo escribe enrolar_medico.
  IF (NEW.lab_enrolador_id, NEW.lab_enrolador_fecha) IS DISTINCT FROM (OLD.lab_enrolador_id, OLD.lab_enrolador_fecha)
     AND NOT v_rpc THEN
    RAISE EXCEPTION 'No puedes modificar el enrolamiento de un médico directamente: usa la opción de enrolar del portal del laboratorio.'
      USING ERRCODE = 'PV015';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER trigger_medicos_lab_enrolador_inmutable ON public.medicos;
CREATE TRIGGER trigger_medicos_lab_enrolador_inmutable
  BEFORE INSERT OR UPDATE ON public.medicos
  FOR EACH ROW EXECUTE FUNCTION public.trg_medicos_lab_enrolador_inmutable();

-- ---------------------------------------------------------------------------- 4: enrolar_medico
CREATE OR REPLACE FUNCTION public.enrolar_medico(p_medico_id uuid)
 RETURNS TABLE(estado text, lab_enrolador_id uuid, lab_enrolador_fecha timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_empresa uuid;
  v_tipo    text;
  v_rol     text;
  v_actual  uuid;
BEGIN
  -- 1) Debe ser un visitador activo (empresa derivada de la sesión).
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  -- 2) Solo un laboratorio farmacéutico enrola médicos (la prioridad de visitas es de ese tipo de empresa).
  SELECT ep.tipo::text INTO v_tipo FROM public.empresas_proveedoras ep WHERE ep.id = v_empresa;
  IF v_tipo IS DISTINCT FROM 'laboratorio_farmaceutico' THEN
    RAISE EXCEPTION 'Solo un laboratorio farmacéutico puede enrolar médicos.' USING ERRCODE = 'PV016';
  END IF;

  -- 3) Rol en la empresa. mi_rol_proveedor() da NULL si la cuenta o la empresa no están activas → PV017 (fail-closed).
  v_rol := public.mi_rol_proveedor();
  IF v_rol IS NULL OR v_rol NOT IN ('admin', 'supervisor', 'visitador_medico') THEN
    RAISE EXCEPTION 'Tu rol en la empresa no te permite enrolar médicos.' USING ERRCODE = 'PV017';
  END IF;

  -- 4) Gate de CAPACIDAD: la empresa debe tener el módulo 'enrolamiento' activo/vigente.
  --    Va antes del plan/país porque es la pregunta más fundamental ("¿tu empresa contrató esto?").
  IF NOT private.empresa_tiene_capacidad(v_empresa, 'enrolamiento') THEN
    RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de enrolamiento. Contactá a soporte para activarlo.' USING ERRCODE = 'PV014';
  END IF;

  -- 5) Puerta comercial: MISMA que ver disponibilidad/agendar (plan activo que cubre el país del médico).
  IF NOT private.visitador_ve_medico(p_medico_id) THEN
    RAISE EXCEPTION 'No tienes un plan activo que cubra a este médico en su país.' USING ERRCODE = 'PV011';
  END IF;

  -- 6) El médico debe existir. Lock de la fila → serializa enrolamientos concurrentes del mismo médico.
  SELECT m.lab_enrolador_id INTO v_actual
  FROM public.medicos m
  WHERE m.id = p_medico_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Médico no encontrado.' USING ERRCODE = 'PV012';
  END IF;

  -- 7) Enrolamiento según estado previo.
  IF v_actual IS NULL THEN
    -- Libre → enrolar con este lab. El guard de medicos (PV015) solo deja escribir el par con el GUC encendido.
    PERFORM set_config('app.enrolamiento_rpc', 'on', true);
    UPDATE public.medicos m
      SET lab_enrolador_id = v_empresa, lab_enrolador_fecha = now()
      WHERE m.id = p_medico_id;
    PERFORM set_config('app.enrolamiento_rpc', '', true);
    RETURN QUERY
      SELECT 'enrolado'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSIF v_actual = v_empresa THEN
    -- Ya enrolado por ESTE lab → no-op idempotente (no error).
    RETURN QUERY
      SELECT 'ya_enrolado_por_ti'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSE
    -- Otro lab → mensaje de negocio claro (defensa en profundidad; el guard de medicos bloquearía el UPDATE de todas
    -- formas con PV015).
    RAISE EXCEPTION 'Este médico ya fue enrolado por otro laboratorio.' USING ERRCODE = 'PV013';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.enrolar_medico(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enrolar_medico(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 5: prioridad_activa
CREATE OR REPLACE FUNCTION public.prioridad_activa(p_medico_id uuid)
 RETURNS TABLE(activa boolean, lab_prioritario_id uuid, visitas_completadas integer, visitas_limite integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_lab    uuid;
  v_fecha  timestamptz;
  v_count  int;
  v_limite int;
BEGIN
  SELECT m.lab_enrolador_id, m.lab_enrolador_fecha
    INTO v_lab, v_fecha
  FROM public.medicos m
  WHERE m.id = p_medico_id;

  -- Médico inexistente, sin enrolador o sin fecha → sin prioridad. La fecha NULL con enrolador no debería existir
  -- (CHECK medicos_enrolador_coherente, mig 375); si aparece, no hay prioridad (antes daba activa = NULL).
  IF v_lab IS NULL OR v_fecha IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 0, 0;
    RETURN;
  END IF;

  -- Visitas CUMPLIDAS reales del lab enrolador desde el enrolamiento (checkout, no fecha agendada).
  SELECT count(*)::int INTO v_count
  FROM public.visitas_agendadas va
  WHERE va.medico_id      = p_medico_id
    AND va.empresa_id     = v_lab
    AND va.estado         = 'completada'
    AND va.checkout_fecha IS NOT NULL
    AND va.checkout_fecha >= v_fecha;

  -- Límite del lab enrolador; default global 8 si la columna es NULL (o el lab no existiera).
  SELECT COALESCE(ep.ventana_prioridad_visitas, 8) INTO v_limite
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_lab;
  v_limite := COALESCE(v_limite, 8);

  RETURN QUERY SELECT
    ( v_count < v_limite
      AND now() < v_fecha + INTERVAL '18 months' ),   -- techo anti-gaming (hardcodeado por ahora)
    v_lab,
    v_count,
    v_limite;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.prioridad_activa(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prioridad_activa(uuid) TO service_role;

-- ---------------------------------------------------------------------------- 6: head-start (DEFINER, tambien en UPDATE)
CREATE OR REPLACE FUNCTION public.trg_gate_head_start_lab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_prio      record;
  v_ventaja   int;
  v_fecha_min date;
BEGIN
  -- UPDATE: la regla se evalúa igual que en INSERT, con NEW, pero solo si cambia la fecha o el médico.
  -- administrar_visita('reprogramar') pone fecha_visita = COALESCE(p_nueva_fecha, fecha_visita): un cambio de solo
  -- hora deja la fecha igual y no se re-evalúa (si no, una visita ya agendada no se podría ni mover de hora).
  IF TG_OP = 'UPDATE'
     AND NEW.fecha_visita IS NOT DISTINCT FROM OLD.fecha_visita
     AND NEW.medico_id IS NOT DISTINCT FROM OLD.medico_id THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_prio FROM public.prioridad_activa(NEW.medico_id);

  -- Sin prioridad activa (no enrolado o ventana expirada): cualquier lab reserva libre.
  IF NOT v_prio.activa THEN
    RETURN NEW;
  END IF;

  -- El propio lab prioritario reserva cualquier fecha.
  IF NEW.empresa_id = v_prio.lab_prioritario_id THEN
    RETURN NEW;
  END IF;

  -- Otro lab: head-start por fecha del lab prioritario (default global 5 días).
  SELECT COALESCE(ep.dias_ventaja_reserva, 5) INTO v_ventaja
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_prio.lab_prioritario_id;
  v_ventaja := COALESCE(v_ventaja, 5);

  v_fecha_min := CURRENT_DATE + v_ventaja;   -- date + int = date

  IF NEW.fecha_visita < v_fecha_min THEN
    RAISE EXCEPTION 'Esta fecha está reservada para el laboratorio con prioridad hasta el %. Puedes agendar a partir de esa fecha.', to_char(v_fecha_min, 'YYYY-MM-DD')
      USING ERRCODE = 'PV002';   -- head-start (país=P0001, bolsa=PV001, head-start=PV002) → front lo captura por SQLSTATE
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.trg_gate_head_start_lab() FROM PUBLIC, anon, authenticated;

DROP TRIGGER trigger_gate_head_start_lab ON public.visitas_agendadas;
CREATE TRIGGER trigger_gate_head_start_lab
  BEFORE INSERT OR UPDATE OF fecha_visita, medico_id ON public.visitas_agendadas
  FOR EACH ROW EXECUTE FUNCTION public.trg_gate_head_start_lab();

-- ---------------------------------------------------------------------------- 7: grants por columna en medicos
-- authenticated deja de leer lab_enrolador_id / lab_enrolador_fecha; INSERT/UPDATE/DELETE de tabla sin cambio
-- (la escritura del par la cierra el guard del paso 3).
REVOKE SELECT ON public.medicos FROM authenticated;
GRANT SELECT (id, clinica_id, nombre_completo, especialidad, telefono, email, cedula_profesional, horario_atencion,
              activo, created_at, updated_at, pais_id, foto_url, especialidad_id)
  ON public.medicos TO authenticated;

-- ---------------------------------------------------------------------------- 8: autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; p record; c text; h record;
BEGIN
  -- (a) las 4 funciones: search_path, DEFINER, cuerpo
  FOR p IN SELECT f.oid::regprocedure::text AS sig, f.prosecdef, f.proconfig::text AS cfg, md5(f.prosrc) AS m, f.proacl::text AS acl
             FROM pg_proc f
            WHERE f.oid IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                            'public.trg_gate_head_start_lab()'::regprocedure, 'public.trg_medicos_lab_enrolador_inmutable()'::regprocedure)
  LOOP
    IF p.cfg IS DISTINCT FROM '{"search_path=\"\""}' THEN bad := bad||p.sig||' proconfig '||COALESCE(p.cfg, '-')||'; '; END IF;
    IF p.sig = 'enrolar_medico(uuid)' THEN
      IF NOT p.prosecdef THEN bad := bad||'enrolar_medico no es DEFINER; '; END IF;
      IF p.m IS DISTINCT FROM '26824150ab1e1cba92ed2a9bbe676306' THEN bad := bad||'enrolar_medico md5 '||p.m||'; '; END IF;
      IF p.acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'enrolar_medico proacl '||COALESCE(p.acl, 'NULL')||'; '; END IF;
    ELSIF p.sig = 'prioridad_activa(uuid)' THEN
      IF NOT p.prosecdef THEN bad := bad||'prioridad_activa no es DEFINER; '; END IF;
      IF p.m IS DISTINCT FROM '07c6a62ffa594ebd093eeca1efbea0d8' THEN bad := bad||'prioridad_activa md5 '||p.m||'; '; END IF;
      IF p.acl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN bad := bad||'prioridad_activa proacl '||COALESCE(p.acl, 'NULL')||'; '; END IF;
    ELSIF p.sig = 'trg_gate_head_start_lab()' THEN
      IF NOT p.prosecdef THEN bad := bad||'trg_gate_head_start_lab no es DEFINER; '; END IF;
      IF p.m IS DISTINCT FROM 'ba09b4fca04e22fe4c3ec0607691805e' THEN bad := bad||'trg_gate_head_start_lab md5 '||p.m||'; '; END IF;
      IF p.acl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN bad := bad||'trg_gate_head_start_lab proacl '||COALESCE(p.acl, 'NULL')||'; '; END IF;
    ELSE
      IF p.prosecdef THEN bad := bad||'el guard de medicos quedo DEFINER; '; END IF;
      IF p.m IS DISTINCT FROM '2af30509d27efef4ed649c5785883381' THEN bad := bad||'guard de medicos md5 '||p.m||'; '; END IF;
      IF p.acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'guard de medicos proacl '||COALESCE(p.acl, 'NULL')||'; '; END IF;
    END IF;
  END LOOP;

  -- (b) EXECUTE efectivo
  IF has_function_privilege('anon', 'public.enrolar_medico(uuid)', 'EXECUTE') THEN bad := bad||'anon ejecuta enrolar_medico; '; END IF;
  IF NOT has_function_privilege('authenticated', 'public.enrolar_medico(uuid)', 'EXECUTE') THEN bad := bad||'authenticated no ejecuta enrolar_medico; '; END IF;
  IF has_function_privilege('authenticated', 'public.prioridad_activa(uuid)', 'EXECUTE') THEN bad := bad||'authenticated ejecuta prioridad_activa; '; END IF;
  IF has_function_privilege('anon', 'public.prioridad_activa(uuid)', 'EXECUTE') THEN bad := bad||'anon ejecuta prioridad_activa; '; END IF;
  IF has_function_privilege('authenticated', 'public.trg_gate_head_start_lab()', 'EXECUTE') THEN bad := bad||'authenticated ejecuta trg_gate_head_start_lab; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
              WHERE f.oid IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                              'public.trg_gate_head_start_lab()'::regprocedure)
                AND a.grantee = 0) THEN
    bad := bad||'PUBLIC con EXECUTE en alguna de las 3; ';
  END IF;

  -- (c) triggers (tgtype 23 = ROW | BEFORE | INSERT | UPDATE)
  v := (SELECT t.tgtype::text||'|'||t.tgattr::text||'|'||t.tgfoid::regprocedure::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.medicos'::regclass AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable');
  IF v IS DISTINCT FROM '23||trg_medicos_lab_enrolador_inmutable()|O' THEN bad := bad||'trigger de medicos '||COALESCE(v, 'no existe')||'; '; END IF;
  c := (SELECT string_agg(a.attnum::text, ' ' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.visitas_agendadas'::regclass AND a.attname IN ('fecha_visita', 'medico_id'));
  v := (SELECT t.tgtype::text||'|'||COALESCE((SELECT string_agg(x::text, ' ' ORDER BY x) FROM unnest(t.tgattr::int2[]) x), '')||'|'||
               t.tgfoid::regprocedure::text||'|'||t.tgenabled::text FROM pg_trigger t
         WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND t.tgname = 'trigger_gate_head_start_lab');
  IF v IS DISTINCT FROM '23|'||c||'|trg_gate_head_start_lab()|O' THEN bad := bad||'trigger del head-start '||COALESCE(v, 'no existe')||' (columnas '||COALESCE(c, '-')||'); '; END IF;

  -- (d) CHECK presente, validado y con la definicion esperada
  SELECT cn.convalidated, pg_get_constraintdef(cn.oid) AS def INTO p
    FROM pg_constraint cn WHERE cn.conrelid = 'public.medicos'::regclass AND cn.conname = 'medicos_enrolador_coherente';
  IF NOT FOUND THEN
    bad := bad||'falta medicos_enrolador_coherente; ';
  ELSE
    IF NOT p.convalidated THEN bad := bad||'medicos_enrolador_coherente sin validar; '; END IF;
    IF p.def IS DISTINCT FROM 'CHECK (((lab_enrolador_id IS NULL) = (lab_enrolador_fecha IS NULL)))' THEN
      bad := bad||'medicos_enrolador_coherente con otra definicion: '||p.def||'; ';
    END IF;
  END IF;

  -- (e) privilegios de authenticated en medicos
  FOR p IN SELECT a.attname,
                  has_column_privilege('authenticated', 'public.medicos', a.attname, 'SELECT') AS lee
             FROM pg_attribute a WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped
  LOOP
    IF p.attname IN ('lab_enrolador_id', 'lab_enrolador_fecha') AND p.lee THEN bad := bad||'authenticated lee '||p.attname||'; '; END IF;
    IF p.attname NOT IN ('lab_enrolador_id', 'lab_enrolador_fecha') AND NOT p.lee THEN bad := bad||'authenticated no lee '||p.attname||'; '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped) <> 16 THEN
    bad := bad||'medicos no tiene 16 columnas; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.medicos', 'SELECT') THEN bad := bad||'authenticated con SELECT de tabla; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.medicos', 'INSERT') THEN bad := bad||'authenticated perdio INSERT; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.medicos', 'UPDATE') THEN bad := bad||'authenticated perdio UPDATE; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.medicos', 'DELETE') THEN bad := bad||'authenticated perdio DELETE; '; END IF;
  IF has_column_privilege('anon', 'public.medicos', 'lab_enrolador_id', 'SELECT') THEN bad := bad||'anon lee lab_enrolador_id; '; END IF;

  -- (f) datos
  IF (SELECT count(*) FROM public.medicos) <> 13 THEN bad := bad||'count(medicos) '||(SELECT count(*) FROM public.medicos)||'; '; END IF;
  IF EXISTS (SELECT 1 FROM public.medicos m WHERE (m.lab_enrolador_id IS NULL) <> (m.lab_enrolador_fecha IS NULL)) THEN
    bad := bad||'quedan filas incoherentes; ';
  END IF;

  -- (g) PV015-PV017 solo donde corresponde
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc LIKE '%PV015%');
  IF v IS DISTINCT FROM 'trg_medicos_lab_enrolador_inmutable()' THEN bad := bad||'PV015 en ['||COALESCE(v, 'ninguna')||']; '; END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc ~ 'PV01[67]');
  IF v IS DISTINCT FROM 'enrolar_medico(uuid)' THEN bad := bad||'PV016/PV017 en ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- (h) resto de las funciones intacto (huella del paso 0)
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO p
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid NOT IN ('public.enrolar_medico(uuid)'::regprocedure, 'public.prioridad_activa(uuid)'::regprocedure,
                       'public.trg_gate_head_start_lab()'::regprocedure, 'public.trg_medicos_lab_enrolador_inmutable()'::regprocedure);
  SELECT t.h, t.n INTO h FROM pg_temp.mig375_huella t;
  IF p.h IS DISTINCT FROM h.h OR p.n IS DISTINCT FROM h.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(p.h, '-')||'/'||COALESCE(p.n::text, '-')||' vs '||COALESCE(h.h, '-')||'/'||COALESCE(h.n::text, '-')||'; ';
  END IF;

  -- (i) huellas globales
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG375_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
