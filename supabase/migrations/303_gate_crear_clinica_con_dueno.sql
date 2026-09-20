-- ============================================================================================
-- 303 — gate de autorizacion en crear_clinica_con_dueno, separando el camino interno
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F4 (hallazgo #2, alto).
-- Ya venia marcado como M3 en AUDITORIA-PROFUNDA-2026-07-05.md:81 y nunca se cerro.
--
-- QUE PASABA. `public.crear_clinica_con_dueno` es SECURITY DEFINER, la ejecuta `authenticated`, y
-- no tenia gate de ninguna clase: insertaba en `clinicas` con `doctor_id = p_doctor_id` y en
-- `medico_clinicas` con `medico_id = p_doctor_id`, a nombre de CUALQUIER medico que le pasaran. El
-- unico caller del front (src/hooks/useClinicas.ts:78) pasa `user.id`, pero la funcion no lo exigia.
--
-- Las policies de la tabla SI tenian el control que a la RPC le faltaba:
--   clinicas · "Doctores pueden crear clinicas"   INSERT a authenticated   WITH CHECK doctor_id = auth.uid()
--   clinicas · "Admin ve clinicas de su pais"     ALL     a public         super_admin, o admin_pais de ese pais
-- La RPC, por ser SECDEF, las saltaba. El gate de abajo reproduce EXACTAMENTE esas dos policies:
-- ni un permiso mas. No se exige que `p_doctor_id` tenga rol='medico' a proposito — las 2 clinicas
-- vivas en prod tienen de dueno a un `super_admin` que ni siquiera esta en `medicos`, y esa
-- condicion las habria vuelto irreproducibles.
--
-- POR QUE SE SEPARA EL CAMINO INTERNO EN VEZ DE PONER UN ESCAPE HATCH.
-- `registrar_medico_desde_invitacion` (mig 190, "Ruta B": invitacion de admin EzPay sin clinica)
-- llama a esta RPC para crear el consultorio del medico recien registrado. La invoca la edge
-- `registrar-medico-invitacion` con **service_role**, ANTES de que exista sesion. Medido contra
-- prod, con una sonda SECDEF de la misma forma que la funcion real:
--
--   medico crea la SUYA            -> auth.uid()=5f638655-... | GATE=true
--   medico crea la de OTRO         -> auth.uid()=5f638655-... | GATE=false
--   paciente a nombre de un medico -> auth.uid()=0dd0c68c-... | GATE=false
--   super_admin a nombre de medico -> auth.uid()=41904e2c-... | GATE=true   (puede_admin_pais)
--   RUTA B (edge, service_role)    -> auth.uid()=NULL         | GATE=NULL   <-- el problema
--
-- En Ruta B `auth.uid()` es NULL, asi que `NULL = p_doctor_id` da NULL y `NULL OR false` da NULL.
-- Con `IF NOT (gate) THEN RAISE`, `NOT NULL` es NULL y el IF NO ENTRA: la Ruta B seguiria andando
-- por FAIL-OPEN TRIVALUADO, el mismo patron que cerraron las migs 265-271 y la 300. Y en cuanto
-- alguien aplicara el estandar del proyecto y lo envolviera en COALESCE, se romperia el alta de
-- medicos. Medido, directo y anidado dentro de otra SECDEF:
--
--   RUTA B directa  -> auth.uid()=NULL | GATE_CON_COALESCE=false
--   RUTA B ANIDADA  -> auth.uid()=NULL | GATE_CON_COALESCE=false
--
-- Un escape hatch (`OR current_setting('role',true) = 'service_role'`) tambien funcionaria —el GUC
-- sobrevive dentro de la SECDEF y el cliente no lo puede forjar— pero deja la puerta de servicio
-- dentro de la funcion publica y hay que volver a razonarla cada vez que alguien la lea. Se separa:
-- el cuerpo baja a `private`, la publica queda como gate + delegacion, y la Ruta B llama al privado
-- directo. La funcion publica queda fail-closed PURA, sin excepciones por sesion nula.
--
-- La privada NO recibe GRANT a anon ni a authenticated: solo la llaman otras SECDEF de dueno
-- `postgres`, que corren con los privilegios del DEFINER y por eso no necesitan el EXECUTE. Mismo
-- patron que la mig 265 documento para los helpers de `private`.
--
-- RESIDUO ANOTADO, no cerrado aca: la RPC tambien escribe en `medico_clinicas`, cuya unica policy
-- de escritura es `Service role all medico_clinicas`. O sea que `authenticated` no puede crear
-- membresias por PostgREST; con este gate solo podra crear la suya (o las de su pais si es admin),
-- que es lo correcto, pero esa segunda insercion es parte de lo que la RPC concede y conviene
-- tenerlo presente. Tampoco se toca el `SET search_path TO 'public'` de
-- `registrar_medico_desde_invitacion`: su propio header (mig 190) lo dejo anotado como hardening
-- aparte, y meterlo aca mezclaria dos cambios.
--
-- Probes: P750-P754 en tests/rls/probes_escritura.sql.
-- ============================================================================================

-- --------------------------------------------------------------------------------------------
-- 1) El cuerpo, tal cual estaba, movido a `private`. Sin gate: es el camino interno.
--    search_path = '' obliga a calificar todo, asi que no hay nombre que se pueda secuestrar.
-- --------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.crear_clinica_con_dueno_interno(
  p_doctor_id uuid,
  p_nombre    text,
  p_pais_id   uuid,
  p_direccion text DEFAULT NULL,
  p_telefono  text DEFAULT NULL,
  p_email     text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_clinica_id   uuid;
  v_es_principal boolean;
BEGIN
  -- el medico ya tiene una clinica principal? Si no, esta es su principal.
  v_es_principal := NOT EXISTS (
    SELECT 1 FROM public.medico_clinicas
    WHERE medico_id = p_doctor_id AND es_principal = true
  );

  -- a) clinica con el medico como dueno
  INSERT INTO public.clinicas (doctor_id, nombre, pais_id, direccion, telefono, email, activa)
  VALUES (p_doctor_id, p_nombre, p_pais_id, p_direccion, p_telefono, p_email, true)
  RETURNING id INTO v_clinica_id;

  -- b) membresia del dueno en su propia clinica
  INSERT INTO public.medico_clinicas (medico_id, clinica_id, es_principal)
  VALUES (p_doctor_id, v_clinica_id, v_es_principal);

  RETURN v_clinica_id;
  -- Cualquier fallo en a) o b) revierte toda la transaccion de la funcion (atomicidad).
END;
$function$;

REVOKE ALL ON FUNCTION private.crear_clinica_con_dueno_interno(uuid, text, uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;

-- --------------------------------------------------------------------------------------------
-- 2) La publica conserva la MISMA firma (no se toca el caller de useClinicas.ts) y pasa a ser
--    gate + delegacion. El COALESCE es obligatorio: sin el, un llamante sin sesion daria NULL y
--    el IF no entraria. Aca ya no hay llamante sin sesion legitimo, y si apareciera uno tiene que
--    ser rechazado, no dejado pasar.
-- --------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_clinica_con_dueno(
  p_doctor_id uuid,
  p_nombre    text,
  p_pais_id   uuid,
  p_direccion text DEFAULT NULL,
  p_telefono  text DEFAULT NULL,
  p_email     text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF NOT COALESCE(auth.uid() = p_doctor_id
               OR private.puede_admin_pais(p_pais_id), false) THEN
    RAISE EXCEPTION 'No autorizado para crear clinica a nombre de otro medico'
      USING ERRCODE = '42501';
  END IF;

  RETURN private.crear_clinica_con_dueno_interno(
    p_doctor_id, p_nombre, p_pais_id, p_direccion, p_telefono, p_email);
END;
$function$;

REVOKE ALL     ON FUNCTION public.crear_clinica_con_dueno(uuid, text, uuid, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_clinica_con_dueno(uuid, text, uuid, text, text, text) TO authenticated;

-- --------------------------------------------------------------------------------------------
-- 3) La Ruta B pasa a llamar al privado. Unico cambio respecto del cuerpo vivo: la linea del
--    PERFORM. Todo lo demas se reproduce identico (incluido el SET search_path TO 'public').
-- --------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_medico_desde_invitacion(
  p_token uuid, p_user_id uuid, p_email text, p_nombre_completo text,
  p_telefono text DEFAULT NULL, p_especialidad text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_invitacion RECORD; v_pais_id UUID; v_clinica_id UUID;
BEGIN
  SELECT * INTO v_invitacion FROM invitaciones_medico
  WHERE token = p_token AND estado = 'pendiente' AND expires_at > NOW() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitacion no valida o expirada'; END IF;
  v_pais_id := v_invitacion.pais_id; v_clinica_id := v_invitacion.clinica_id;
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN RAISE EXCEPTION 'El email no coincide con la invitacion'; END IF;
  IF EXISTS (SELECT 1 FROM medicos WHERE id = p_user_id) THEN RAISE EXCEPTION 'Este usuario ya esta registrado como medico'; END IF;

  -- Crear medico. NO se setea clinica_id (se elimina; requiere medicos.clinica_id nullable = FASE 4).
  INSERT INTO medicos (id, nombre_completo, email, telefono, especialidad, especialidad_id, pais_id)
  VALUES (p_user_id, p_nombre_completo, p_email,
          COALESCE(p_telefono, v_invitacion.telefono),
          COALESCE(p_especialidad, v_invitacion.especialidad),  -- texto legacy en paralelo (intacto)
          v_invitacion.especialidad_id,                          -- NULL si "sin especialidad" -> no falla
          v_pais_id);

  UPDATE perfiles SET rol = 'medico', pais_id = v_pais_id, nombre_completo = p_nombre_completo WHERE id = p_user_id;

  IF v_clinica_id IS NOT NULL THEN
    -- Ruta A: la clinica invito al medico -> membresia en ESA clinica (comportamiento actual).
    INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
    VALUES (p_user_id, v_clinica_id, true) ON CONFLICT DO NOTHING;
  ELSE
    -- Ruta B: invitacion de admin EzPay sin clinica -> el medico crea su propia clinica.
    -- Va DIRECTO al privado: aca auth.uid() es NULL (la edge llama con service_role antes de que
    -- exista sesion) y el gate de la publica, que es fail-closed, la rechazaria con 42501.
    PERFORM private.crear_clinica_con_dueno_interno(
      p_user_id,
      'Consultorio ' || p_nombre_completo,
      v_pais_id
    );
  END IF;

  UPDATE invitaciones_medico SET estado = 'usada', used_at = NOW() WHERE id = v_invitacion.id;
  RETURN p_user_id;
END; $function$;

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita los 5 caminos REALES contra la
-- base, escribiendo de verdad; cada prueba vive en una SUBTRANSACCION de plpgsql que se revierte
-- con un RAISE propio. Esta migracion se aplica FUERA de una transaccion explicita: un INSERT
-- suelto quedaria en prod.
-- ============================================================================================
DO $$
DECLARE
  v_mal    text := '';
  v_pais   uuid;
  v_med    uuid;
  v_med2   uuid;
  v_sa     uuid;
  v_pac    constant uuid := '0dd0c68c-026c-4ebc-9475-e6791cc54933';  -- paciente real, sin rol
  v_sint   uuid;      -- actor sintetico para la Ruta B: tiene perfil pero NO esta en medicos
  v_id     uuid;
  v_n      bigint;
  v_cli0   bigint;
  v_mc0    bigint;
  v_tok    uuid;
  v_ok1    text := 'no se ejecuto';
  v_ok4    text := 'no se ejecuto';
  v_ok5    text := 'no se ejecuto';
BEGIN
  SELECT count(*) INTO v_cli0 FROM public.clinicas;
  SELECT count(*) INTO v_mc0  FROM public.medico_clinicas;

  SELECT id INTO v_pais FROM public.configuracion_pais WHERE activo LIMIT 1;
  SELECT id INTO v_sa   FROM public.perfiles WHERE rol = 'super_admin' AND activo LIMIT 1;
  -- medicos REALES (con fila en `medicos`): medico_clinicas.medico_id tiene FK a medicos, asi que
  -- un p_doctor_id que no este ahi falla por FK y no por el gate — mediria otra cosa.
  SELECT m.id INTO v_med  FROM public.medicos m ORDER BY m.id LIMIT 1;
  SELECT m.id INTO v_med2 FROM public.medicos m WHERE m.id <> v_med ORDER BY m.id LIMIT 1;
  SELECT pf.id INTO v_sint FROM public.perfiles pf
   WHERE NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = pf.id)
     AND pf.id <> v_pac AND coalesce(pf.rol,'') <> 'super_admin'
   ORDER BY pf.id LIMIT 1;

  IF v_pais IS NULL OR v_med IS NULL OR v_sa IS NULL THEN
    RAISE EXCEPTION '303: faltan actores para el autochequeo (pais=% medico=% super_admin=%)', v_pais, v_med, v_sa;
  END IF;

  -- ---------------------------------------------------------------- (1) el medico crea la SUYA
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_med, 'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    v_id := public.crear_clinica_con_dueno(v_med, 'AUTOCHEQUEO 303 propia', v_pais);
    PERFORM set_config('role','none', true);
    IF v_id IS NULL THEN
      v_ok1 := 'devolvio NULL';
    ELSIF NOT EXISTS (SELECT 1 FROM public.medico_clinicas mc WHERE mc.clinica_id = v_id AND mc.medico_id = v_med) THEN
      v_ok1 := 'creo la clinica pero NO la membresia';
    ELSE
      v_ok1 := 'OK';
    END IF;
    RAISE EXCEPTION 'M303_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M303_RB' THEN v_ok1 := format('fallo (%s %s)', SQLSTATE, SQLERRM); END IF;
  END;
  IF v_ok1 <> 'OK' THEN
    v_mal := v_mal || format('(1) el medico NO pudo crear su propia clinica: %s; ', v_ok1);
  END IF;

  -- ---------------------------------------------------------------- (2) el medico, a nombre de OTRO
  IF v_med2 IS NOT NULL THEN
    BEGIN
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_med, 'role','authenticated')::text, true);
      PERFORM set_config('role','authenticated', true);
      PERFORM public.crear_clinica_con_dueno(v_med2, 'AUTOCHEQUEO 303 ajena', v_pais);
      PERFORM set_config('role','none', true);
      v_mal := v_mal || '(2) un medico creo una clinica a nombre de OTRO medico; ';
      RAISE EXCEPTION 'M303_RB';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role','none', true);
      IF SQLSTATE NOT IN ('42501','P0001') THEN
        v_mal := v_mal || format('(2) corto con %s, se esperaba 42501; ', SQLSTATE);
      END IF;
    END;
  END IF;

  -- ---------------------------------------------------------------- (3) un paciente, a nombre de un medico
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac, 'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.crear_clinica_con_dueno(v_med, 'AUTOCHEQUEO 303 paciente', v_pais);
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(3) un paciente creo una clinica a nombre de un medico; ';
    RAISE EXCEPTION 'M303_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLSTATE NOT IN ('42501','P0001') THEN
      v_mal := v_mal || format('(3) corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;

  -- ---------------------------------------------------------------- (4) super_admin a nombre de un medico
  -- CONTROL POSITIVO del brazo puede_admin_pais. Sin esto, un gate que solo mirara auth.uid()
  -- tambien daria verde en (1)(2)(3) y le romperia el alta administrativa a los admins.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    v_id := public.crear_clinica_con_dueno(v_med, 'AUTOCHEQUEO 303 admin', v_pais);
    PERFORM set_config('role','none', true);
    v_ok4 := CASE WHEN v_id IS NULL THEN 'devolvio NULL' ELSE 'OK' END;
    RAISE EXCEPTION 'M303_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M303_RB' THEN v_ok4 := format('fallo (%s %s)', SQLSTATE, SQLERRM); END IF;
  END;
  IF v_ok4 <> 'OK' THEN
    v_mal := v_mal || format('(4) el super_admin NO pudo crear a nombre de un medico: %s; ', v_ok4);
  END IF;

  -- ---------------------------------------------------------------- (5) RUTA B, de punta a punta
  -- Se ejercita `registrar_medico_desde_invitacion` COMPLETA (no el privado a mano): siembra la
  -- invitacion, la corre como service_role con auth.uid() NULL, y verifica que el consultorio
  -- quedo creado CON su membresia. Es la unica forma de ver lo que rompe un gate mal puesto.
  IF v_sint IS NOT NULL THEN
    BEGIN
      v_tok := gen_random_uuid();
      INSERT INTO public.invitaciones_medico
        (id, token, pais_id, email, nombre_completo, clinica_id, estado, expires_at)
      VALUES (gen_random_uuid(), v_tok, v_pais, 'autochequeo303@ezpay.test',
              'Autochequeo 303', NULL, 'pendiente', now() + interval '1 day');

      PERFORM set_config('request.jwt.claims','{"role":"service_role"}', true);
      PERFORM set_config('role','service_role', true);
      PERFORM public.registrar_medico_desde_invitacion(
        v_tok, v_sint, 'autochequeo303@ezpay.test', 'Autochequeo 303');
      PERFORM set_config('role','none', true);

      SELECT count(*) INTO v_n
        FROM public.clinicas c
        JOIN public.medico_clinicas mc ON mc.clinica_id = c.id AND mc.medico_id = v_sint
       WHERE c.doctor_id = v_sint AND c.nombre = 'Consultorio Autochequeo 303';
      v_ok5 := CASE WHEN v_n = 1 THEN 'OK' ELSE format('la Ruta B no dejo el consultorio (%s)', v_n) END;
      RAISE EXCEPTION 'M303_RB';
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role','none', true);
      PERFORM set_config('request.jwt.claims','', true);
      IF SQLERRM <> 'M303_RB' THEN v_ok5 := format('fallo (%s %s)', SQLSTATE, SQLERRM); END IF;
    END;
    IF v_ok5 <> 'OK' THEN
      v_mal := v_mal || format('(5) la RUTA B se rompio: %s; ', v_ok5);
    END IF;
  END IF;
  PERFORM set_config('request.jwt.claims','', true);

  -- ---------------------------------------------------------------- (6) la privada no es alcanzable
  IF has_function_privilege('anon',
       'private.crear_clinica_con_dueno_interno(uuid,text,uuid,text,text,text)','EXECUTE') THEN
    v_mal := v_mal || '(6) anon puede ejecutar la funcion interna; ';
  END IF;
  IF has_function_privilege('authenticated',
       'private.crear_clinica_con_dueno_interno(uuid,text,uuid,text,text,text)','EXECUTE') THEN
    v_mal := v_mal || '(6) authenticated puede ejecutar la funcion interna; ';
  END IF;
  IF NOT has_function_privilege('authenticated',
       'public.crear_clinica_con_dueno(uuid,text,uuid,text,text,text)','EXECUTE') THEN
    v_mal := v_mal || '(6) authenticated PERDIO el EXECUTE de la publica: se rompe useClinicas; ';
  END IF;
  IF has_function_privilege('anon',
       'public.crear_clinica_con_dueno(uuid,text,uuid,text,text,text)','EXECUTE') THEN
    v_mal := v_mal || '(6) anon gano EXECUTE sobre la publica; ';
  END IF;

  -- ---------------------------------------------------------------- (7) nada se escribio en prod
  SELECT count(*) INTO v_n FROM public.clinicas;
  IF v_n <> v_cli0 THEN
    v_mal := v_mal || format('(7) clinicas paso de %s a %s: el autochequeo escribio en prod; ', v_cli0, v_n);
  END IF;
  SELECT count(*) INTO v_n FROM public.medico_clinicas;
  IF v_n <> v_mc0 THEN
    v_mal := v_mal || format('(7) medico_clinicas paso de %s a %s; ', v_mc0, v_n);
  END IF;
  SELECT count(*) INTO v_n FROM public.clinicas WHERE nombre LIKE 'AUTOCHEQUEO 303%' OR nombre = 'Consultorio Autochequeo 303';
  IF v_n <> 0 THEN
    v_mal := v_mal || format('(7) quedaron %s clinicas de prueba escritas; ', v_n);
  END IF;
  SELECT count(*) INTO v_n FROM public.invitaciones_medico WHERE email = 'autochequeo303@ezpay.test';
  IF v_n <> 0 THEN
    v_mal := v_mal || format('(7) quedaron %s invitaciones de prueba escritas; ', v_n);
  END IF;

  IF v_mal <> '' THEN
    RAISE EXCEPTION '303: %', v_mal;
  END IF;
END $$;
