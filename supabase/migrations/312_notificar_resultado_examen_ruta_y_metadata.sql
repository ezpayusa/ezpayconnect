-- ############################################################################################
-- 312 — notificar_resultado_examen: llevar al medico AL PACIENTE, y dejar el examen en metadata
-- ############################################################################################
-- Frente 5 (backend) de la cola de Fase 4. Diseno cerrado por Oscar el 20-sep.
--
-- QUE ESTABA MAL. Cuando el laboratorio carga un resultado, el medico recibia una notificacion con
-- `accion_url = '/medico/citas'` hardcodeado: una lista de citas que no tiene nada que ver con el
-- examen. Y la fila salia con `metadata` en el default `'{}'`, asi que ni el front ni un frente
-- futuro podian saber DE QUE examen hablaba la notificacion. Medido: las 6 filas de tipo
-- `examen_resultado` que hay en prod tienen las dos cosas — accion_url a /medico/citas y metadata
-- vacia.
--
-- A DONDE APUNTA AHORA. `/medico/pacientes/<paciente_id>/detalle`, que YA EXISTE
-- (src/App.tsx:413, dentro de MedicoPrivateRoute) y cuyo `:id` se usa literal como `paciente_id`
-- contra la tabla `examenes` (src/pages/PacienteDetallePage.tsx:106). Esa pantalla ya muestra el
-- resultado, el archivo y el boton de liberar.
--   LIMITE CONOCIDO, para que nadie lo descubra en produccion: la pantalla abre siempre en la
--   pestania "Info" y NO lee nada de la URL mas alla del :id — no hay deep-link a un examen. El
--   medico cae en el paciente correcto y da un clic mas hasta "Examenes". Llevarlo directo al
--   examen es front (leer query params y elegir la pestania) y es otro frente.
--
-- EL CASO WALK-IN. `examenes.paciente_id` es NULLABLE: el laboratorio puede cargar un examen con
-- `paciente_nombre`/`paciente_documento` sueltos y sin paciente registrado. Ahi no hay ficha a la
-- que llevar, asi que la URL cae al `/medico/citas` de siempre. No es un fallback decorativo: es
-- la mitad de los casos que esta funcion tiene que cubrir, y P797 lo mide.
--
-- METADATA. `{"examen_id": N, "paciente_id": M}`, el mismo patron que ya usan 34 notificaciones
-- del medico (`{"cita_id": 65, "paciente_id": 23}`). Por eso NO se agrega una columna `examen_id`
-- a `notificaciones`: el molde existe y es jsonb.
--
-- LO QUE NO CAMBIA, y el autochequeo lo verifica porque esto es un CREATE OR REPLACE completo:
-- el gate (`laboratorio_id = mi_empresa_proveedor()` con COALESCE, error PT002), el INSERT en
-- `notificaciones`, y el `push_notificar` condicionado a que haya medico. No se gasta errcode.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE v public.examenes%ROWTYPE; v_mid uuid; v_url text;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;

  -- Gate sin cambios: solo el laboratorio DUENIO del examen notifica. El COALESCE ya estaba y se
  -- conserva: `v.laboratorio_id = public.mi_empresa_proveedor()` vale NULL para un examen sin
  -- laboratorio o un caller sin empresa, y NULL en un IF NOT no entra al THEN.
  IF NOT COALESCE(v.laboratorio_id = public.mi_empresa_proveedor(), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002';
  END IF;

  -- La ruta a la ficha del paciente. Sin paciente registrado (walk-in) no hay ficha: cae al
  -- destino historico.
  v_url := CASE WHEN v.paciente_id IS NOT NULL
                THEN '/medico/pacientes/' || v.paciente_id::text || '/detalle'
                ELSE '/medico/citas' END;

  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
              'Un paciente tiene un resultado de examen nuevo para revisar.', v_url,
              jsonb_build_object('examen_id', v.id, 'paciente_id', v.paciente_id))
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;
  END IF;

  RETURN jsonb_build_object('medico', v.medico_id);
END;
$fn$;


-- ============================================================================================
-- AUTOCHEQUEO 1 — los dos caminos, ejercitados de verdad
-- ============================================================================================
-- Se siembran DOS examenes, uno con paciente y uno sin, se llama a la funcion con el rol del
-- laboratorio duenio, y se lee la notificacion que quedo. No alcanza con leer el cuerpo de la
-- funcion: el `||` sobre un integer y el CASE se comportan, o no, contra datos.
--
-- Todo en una subtransaccion que SIEMPRE aborta. `push_notificar` usa net.http_post, que ENCOLA
-- en una tabla dentro de la misma transaccion, asi que el abort se lleva el encolado. Y aun si
-- alguna version de pg_net lo dejara salir, la edge recibiria un notification_id de una fila que
-- ya no existe y devolveria 404 sin enviarle nada a nadie.
DO $ac1$
DECLARE
  v_emp uuid; v_lab uuid; v_med uuid; v_pac int;
  v_ex_con int; v_ex_sin int;
  u_con text; u_sin text; m_con jsonb; m_sin jsonb;
  t_con text; t_sin text;
BEGIN
  BEGIN
    SELECT cp.empresa_id, cp.id INTO v_emp, v_lab
      FROM public.cuentas_proveedor cp WHERE cp.activo ORDER BY cp.id LIMIT 1;
    SELECT p.id INTO v_pac FROM public.pacientes p ORDER BY p.id LIMIT 1;
    IF v_emp IS NULL OR v_pac IS NULL THEN RAISE EXCEPTION 'M312_NOFIX'; END IF;

    -- medico destinatario: notificaciones.usuario_id tiene FK a auth.users, asi que hace falta
    -- la fila en auth.users ademas del perfil.
    v_med := gen_random_uuid();
    INSERT INTO auth.users (id) VALUES (v_med);
    INSERT INTO public.perfiles (id, email, nombre_completo, rol, activo)
      VALUES (v_med, 'm312.medico@example.invalid', 'QA 312 medico', 'medico', true);

    INSERT INTO public.examenes (tipo, paciente_id, medico_id, laboratorio_id, estado)
         VALUES ('QA 312 con paciente', v_pac, v_med, v_emp, 'completado'::public.examen_estado)
    RETURNING id INTO v_ex_con;
    INSERT INTO public.examenes (tipo, paciente_id, medico_id, laboratorio_id, estado)
         VALUES ('QA 312 walk-in', NULL, v_med, v_emp, 'completado'::public.examen_estado)
    RETURNING id INTO v_ex_sin;

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_lab, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    PERFORM public.notificar_resultado_examen(v_ex_con);
    PERFORM public.notificar_resultado_examen(v_ex_sin);
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);

    SELECT n.accion_url, n.metadata, n.tipo INTO u_con, m_con, t_con
      FROM public.notificaciones n
     WHERE n.usuario_id = v_med AND n.metadata->>'examen_id' = v_ex_con::text
     ORDER BY n.created_at DESC LIMIT 1;
    SELECT n.accion_url, n.metadata, n.tipo INTO u_sin, m_sin, t_sin
      FROM public.notificaciones n
     WHERE n.usuario_id = v_med AND n.metadata->>'examen_id' = v_ex_sin::text
     ORDER BY n.created_at DESC LIMIT 1;

    RAISE EXCEPTION 'M312_ROLLBACK_FIXTURE';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
    IF SQLERRM = 'M312_NOFIX' THEN
      RAISE EXCEPTION '312 AC1: no hay cuenta de proveedor activa o paciente para sembrar';
    ELSIF SQLERRM <> 'M312_ROLLBACK_FIXTURE' THEN
      RAISE EXCEPTION '312 AC1: fallo midiendo (% %)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- (a) con paciente: la ruta a la ficha
  IF u_con IS NULL THEN
    RAISE EXCEPTION '312 AC1: no se creo notificacion para el examen CON paciente';
  END IF;
  IF u_con <> '/medico/pacientes/' || v_pac::text || '/detalle' THEN
    RAISE EXCEPTION '312 AC1: accion_url con paciente es "%", se esperaba "/medico/pacientes/%/detalle"', u_con, v_pac;
  END IF;
  IF m_con->>'examen_id' <> v_ex_con::text OR m_con->>'paciente_id' <> v_pac::text THEN
    RAISE EXCEPTION '312 AC1: metadata con paciente es %, se esperaba examen_id=% paciente_id=%', m_con, v_ex_con, v_pac;
  END IF;

  -- (b) walk-in: el fallback
  IF u_sin IS NULL THEN
    RAISE EXCEPTION '312 AC1: no se creo notificacion para el examen SIN paciente';
  END IF;
  IF u_sin <> '/medico/citas' THEN
    RAISE EXCEPTION '312 AC1: accion_url sin paciente es "%", se esperaba "/medico/citas"', u_sin;
  END IF;
  IF m_sin->>'examen_id' <> v_ex_sin::text THEN
    RAISE EXCEPTION '312 AC1: metadata sin paciente no trae el examen_id: %', m_sin;
  END IF;
  -- paciente_id tiene que estar PRESENTE y en null, no ausente: un front que lea la clave
  -- distingue "walk-in" de "notificacion vieja sin metadata".
  IF NOT (m_sin ? 'paciente_id') OR m_sin->>'paciente_id' IS NOT NULL THEN
    RAISE EXCEPTION '312 AC1: metadata sin paciente deberia traer paciente_id en null, trae %', m_sin;
  END IF;

  IF t_con <> 'examen_resultado' OR t_sin <> 'examen_resultado' THEN
    RAISE EXCEPTION '312 AC1: el tipo cambio (% / %), se esperaba examen_resultado en los dos', t_con, t_sin;
  END IF;

  PERFORM set_config('m312.ac1', format(
    'OK (con paciente -> %s + %s ; walk-in -> %s + %s)', u_con, m_con::text, u_sin, m_sin::text), true);
END $ac1$;


-- ============================================================================================
-- AUTOCHEQUEO 2 — la forma del resto de la funcion, que este CREATE OR REPLACE no debia tocar
-- ============================================================================================
-- SE MIRA EL CUERPO SIN COMENTARIOS. Es la leccion de la mig 311: `prosrc` incluye los
-- comentarios, y los de esta funcion nombran a proposito cosas como '/medico/citas' y el caso
-- walk-in. Un chequeo sobre prosrc crudo mide la prosa, no el codigo.
DO $ac2$
DECLARE v_n int; v_cuerpo text;
BEGIN
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_cuerpo
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='notificar_resultado_examen';
  IF v_cuerpo IS NULL THEN
    RAISE EXCEPTION '312 AC2: notificar_resultado_examen no existe';
  END IF;

  -- lo que TIENE que seguir estando
  IF v_cuerpo NOT LIKE '%mi_empresa_proveedor%' OR v_cuerpo NOT LIKE '%laboratorio_id%' THEN
    RAISE EXCEPTION '312 AC2: se perdio el gate del laboratorio duenio';
  END IF;
  IF v_cuerpo NOT LIKE '%COALESCE%' THEN
    RAISE EXCEPTION '312 AC2: el gate quedo sin COALESCE (fail-open trivaluado)';
  END IF;
  IF v_cuerpo NOT LIKE '%PT002%' THEN
    RAISE EXCEPTION '312 AC2: se perdio el errcode PT002 del rechazo';
  END IF;
  IF v_cuerpo NOT LIKE '%INSERT INTO public.notificaciones%' THEN
    RAISE EXCEPTION '312 AC2: se perdio el INSERT en notificaciones';
  END IF;
  IF v_cuerpo NOT LIKE '%medico_id IS NOT NULL%' THEN
    RAISE EXCEPTION '312 AC2: el INSERT dejo de estar condicionado a que haya medico';
  END IF;
  IF v_cuerpo NOT LIKE '%push_notificar%' THEN
    RAISE EXCEPTION '312 AC2: se perdio el push_notificar';
  END IF;
  -- lo que ESTE cambio agrega
  IF v_cuerpo NOT LIKE '%/medico/pacientes/%' OR v_cuerpo NOT LIKE '%/medico/citas%' THEN
    RAISE EXCEPTION '312 AC2: falta alguno de los dos destinos de accion_url';
  END IF;
  IF v_cuerpo NOT LIKE '%jsonb_build_object(''examen_id''%' THEN
    RAISE EXCEPTION '312 AC2: el INSERT no arma la metadata con examen_id';
  END IF;

  -- y la firma no cambio
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='notificar_resultado_examen'
     AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg IN ('search_path=""', 'search_path='))
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_examen_id integer';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '312 AC2: la firma o las propiedades cambiaron (DEFINER / search_path / args)';
  END IF;
  IF has_function_privilege('anon', 'public.notificar_resultado_examen(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '312 AC2: anon puede ejecutar notificar_resultado_examen';
  END IF;

  PERFORM set_config('m312.ac2',
    'OK (cuerpo sin comentarios: gate+COALESCE+PT002, INSERT condicionado a medico, push_notificar, los 2 destinos y la metadata; firma DEFINER sp='''' sin anon)', true);
END $ac2$;


DO $fin$
BEGIN
  PERFORM set_config('m312.auto',
    'AC1 ' || COALESCE(current_setting('m312.ac1', true), 'FALTA') ||
    ' || AC2 ' || COALESCE(current_setting('m312.ac2', true), 'FALTA'), true);
  RAISE NOTICE '312 OK';
END $fin$;
