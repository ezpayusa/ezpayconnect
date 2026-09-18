-- ############################################################################################
-- 299 — buscar_medicos_paciente / listar_especialidades_activas: exigir perfiles.rol = 'medico'
-- ############################################################################################
-- LA FUGA ESTA VIVA EN PROD, MEDIDA EL 18-sep, NO ES TEORICA. Impersonando a un paciente REAL de
-- Guatemala (0dd0c68c-026c-4ebc-9475-e6791cc54933), `buscar_medicos_paciente()` devolvio 5
-- "medicos" y UNO de ellos es un `admin_clinica`. O sea que el buscador de medicos del portal del
-- paciente (AgendarCitaModal) hoy ofrece agendar cita con personal administrativo.
--
-- POR QUE PASA: `medico_clinicas.medico_id` tiene FK a `medicos`, asi que crear-staff-clinica
-- inserta una fila en `medicos` para CUALQUIER staff —secretaria, enfermeria, gerente,
-- admin_clinica— porque sin esa fila la asociacion a la clinica falla. El rol REAL vive en
-- `perfiles.rol`. La RPC (mig 184) filtraba por activo + pais_id + especialidad y nunca miro el rol.
--
-- ESTADO DE `medicos` AL 18-sep: 13 filas, las 13 activas. Solo 4 son medicos de verdad; las otras
-- 9 son 4 asistente_medico, 2 secretaria, 1 admin_clinica, 1 enfermeria, 1 gerente.
--
-- HAY DOS CAMINOS A LA FUGA Y ESTA MIGRACION CIERRA LOS DOS:
--   (1) El que ya esta activo: un staff con `pais_id` que coincide con el del paciente. Hoy hay 1
--       fila asi, y es la que aparece en la medicion de arriba.
--   (2) El latente y peor: el WHERE dice `(v_pais IS NULL OR m.pais_id = v_pais)`. Si el paciente
--       no tiene pais_id, la condicion se vuelve universal y expone TODO `medicos` activo de TODOS
--       los paises. Hoy no hay ningun paciente con pais_id NULL (medido: 0 de los que tienen
--       cuenta), asi que este camino no esta activado — pero esta a un solo registro de estarlo, y
--       no depende de arreglar la edge.
--
-- EL CAMBIO ES QUIRURGICO. Las dos funciones se recrean con el texto VIVO exacto (traido de
-- pg_get_functiondef, no del repo) mas UNA condicion en cada una. Firma, RETURNS, volatilidad,
-- search_path, UNION, ORDER BY y comentarios internos quedan identicos. La Fuente 2 de
-- buscar_medicos_paciente —la que ya lee de `perfiles` con rol='medico'— no se toca: ya exigia el
-- rol por construccion.
--
-- NO SE TOCA EL `search_path TO 'public'` de ninguna de las dos. Es mas flojo que el `''` que
-- venimos poniendo en las migs 296/299, pero cambiarlo obliga a calificar cada tabla del cuerpo y
-- eso deja de ser un cambio quirurgico. Queda anotado como frente aparte.
--
-- FUERA DE ALCANCE, por decision de Oscar: el backfill de `pais_id` en las filas de staff que ya
-- existen en `medicos`. Esta migracion las vuelve invisibles para el paciente igual, porque el
-- filtro nuevo es por ROL y no por pais.
-- ############################################################################################

-- 1 -----------------------------------------------------------------------------------------
-- Fuente 1 (tabla `medicos`) pasa a exigir que el id tenga perfil con rol='medico'.
CREATE OR REPLACE FUNCTION public.buscar_medicos_paciente(p_especialidad_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, nombre_completo text, especialidad text, especialidad_id uuid, foto_url text, activo boolean, pais_id uuid, proximo_turno timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid;
  v_pais uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT p.pais_id INTO v_pais FROM pacientes p WHERE p.auth_user_id = v_uid;

  RETURN QUERY
  WITH base AS (
    -- Fuente 1: tabla medicos (invitados por clínicas)
    SELECT m.id, m.nombre_completo, m.especialidad, m.especialidad_id, m.foto_url, m.activo, m.pais_id
    FROM medicos m
    WHERE m.activo = true
      -- MIG 299: una fila en `medicos` NO significa "es medico". crear-staff-clinica crea una para
      -- cualquier staff porque medico_clinicas.medico_id tiene FK a esta tabla. El rol real esta en
      -- `perfiles`, y sin este EXISTS el paciente veia secretarias y gerentes como medicos.
      AND EXISTS (SELECT 1 FROM perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')
      AND (v_pais IS NULL OR m.pais_id = v_pais)   -- aislamiento estricto: sin "OR pais_id IS NULL"
      AND (p_especialidad_id IS NULL OR m.especialidad_id = p_especialidad_id)
    UNION ALL
    -- Fuente 2: perfiles rol='medico' registro directo, no presentes en medicos
    SELECT pf.id, pf.nombre_completo, NULL::text, NULL::uuid, pf.avatar_url, pf.activo, pf.pais_id
    FROM perfiles pf
    WHERE pf.rol = 'medico' AND pf.activo = true
      AND (v_pais IS NULL OR pf.pais_id = v_pais)   -- aislamiento estricto
      AND p_especialidad_id IS NULL   -- perfiles no tiene especialidad_id; si se filtra por especialidad, no aplican
      AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = pf.id)
  ),
  con_turno AS (
    SELECT b.*, public.proximo_turno_disponible(b.id) AS proximo_turno
    FROM base b
  )
  SELECT ct.id, ct.nombre_completo, ct.especialidad, ct.especialidad_id,
         ct.foto_url, ct.activo, ct.pais_id, ct.proximo_turno
  FROM con_turno ct
  ORDER BY ct.proximo_turno ASC NULLS LAST, ct.nombre_completo;
END;
$function$;

-- 2 -----------------------------------------------------------------------------------------
-- Misma correccion en el EXISTS del catalogo de especialidades: sin esto, el <select> del modal
-- seguiria ofreciendo una especialidad que solo "tiene" una secretaria, y el paciente la elegiria
-- para despues ver una lista vacia.
CREATE OR REPLACE FUNCTION public.listar_especialidades_activas()
 RETURNS TABLE(id uuid, nombre text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid;
  v_pais uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT p.pais_id INTO v_pais FROM pacientes p WHERE p.auth_user_id = v_uid;

  RETURN QUERY
  SELECT e.id, e.nombre
  FROM especialidades e
  WHERE e.activo = true
    AND EXISTS (
      SELECT 1
      FROM medicos m
      WHERE m.especialidad_id = e.id      -- garantiza especialidad_id IS NOT NULL
        AND m.activo  = true
        -- MIG 299: mismo criterio que buscar_medicos_paciente. Ver el comentario de alla.
        AND EXISTS (SELECT 1 FROM perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')
        AND m.pais_id = v_pais            -- aislamiento estricto (v_pais NULL ⇒ sin match ⇒ [])
    )
  ORDER BY e.nombre;
END;
$function$;

-- 3 -----------------------------------------------------------------------------------------
-- AUTOCHEQUEO. Siembra un staff REAL (auth.users + perfiles rol='secretaria' + medicos activo con
-- pais_id) y un paciente de prueba, y verifica que la RPC no lo devuelva en NINGUNO de los dos
-- escenarios: paciente con pais_id que coincide, y paciente con pais_id NULL (la rama universal).
-- Todo dentro de UN SOLO bloque DO, que es una sola sentencia: si algo revienta, la siembra se va
-- con el rollback y no queda basura en prod. La limpieza explicita del final cubre el camino feliz.
--
-- EL CONTROL POSITIVO NO ES OPCIONAL: "el staff no aparece" tambien lo cumpliria una funcion que
-- no devuelve nada. Por eso se verifica en el mismo aliento que un medico REAL si aparece.
DO $$
DECLARE
  v_gt        constant uuid := 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909';
  v_staff     uuid := gen_random_uuid();
  v_pac_uid   uuid := gen_random_uuid();
  v_esp       uuid;
  v_med_real  uuid;
  v_mal       text := '';
  n           bigint;
BEGIN
  -- El trigger on_auth_user_created_paciente solo actua si raw_user_meta_data->>'tipo' = 'paciente';
  -- sin ese meta no crea nada, asi que la siembra queda bajo control total.
  INSERT INTO auth.users (id) VALUES (v_staff), (v_pac_uid);

  INSERT INTO especialidades (nombre, activo) VALUES ('M299 Especialidad de prueba', true)
  RETURNING id INTO v_esp;

  INSERT INTO perfiles (id, email, nombre_completo, rol, activo, pais_id)
  VALUES (v_staff, 'm299_staff@ejemplo.invalid', 'M299 Staff Secretaria', 'secretaria', true, v_gt);

  INSERT INTO medicos (id, nombre_completo, activo, pais_id, especialidad_id)
  VALUES (v_staff, 'M299 Staff Secretaria', true, v_gt, v_esp);

  INSERT INTO pacientes (auth_user_id, nombre, apellido, activo, pais_id)
  VALUES (v_pac_uid, 'M299', 'Paciente Prueba', true, v_gt);

  SELECT m.id INTO v_med_real FROM medicos m
   WHERE m.activo AND m.pais_id = v_gt
     AND EXISTS (SELECT 1 FROM perfiles p WHERE p.id = m.id AND p.rol = 'medico')
   ORDER BY m.id LIMIT 1;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_pac_uid, 'role', 'authenticated')::text, true);

  -- (a) paciente CON pais_id que coincide: el staff no puede estar.
  SELECT count(*) INTO n FROM public.buscar_medicos_paciente() b WHERE b.id = v_staff;
  IF n <> 0 THEN v_mal := v_mal || 'el staff aparece con pais_id coincidente; '; END IF;

  -- (b) CONTROL POSITIVO: un medico real del mismo pais SI tiene que aparecer.
  IF v_med_real IS NOT NULL THEN
    SELECT count(*) INTO n FROM public.buscar_medicos_paciente() b WHERE b.id = v_med_real;
    IF n <> 1 THEN v_mal := v_mal || 'un medico REAL dejo de aparecer: la RPC quedo rota; '; END IF;
  ELSE
    v_mal := v_mal || 'no hay ningun medico real en GT para el control positivo; ';
  END IF;

  -- (c) la especialidad que SOLO tiene al staff no puede salir en el catalogo.
  SELECT count(*) INTO n FROM public.listar_especialidades_activas() e WHERE e.id = v_esp;
  IF n <> 0 THEN v_mal := v_mal || 'la especialidad del staff aparece en el catalogo; '; END IF;

  -- (d) LA RAMA UNIVERSAL: paciente SIN pais_id. Antes de la 299 esto exponia TODO medicos activo.
  UPDATE pacientes SET pais_id = NULL WHERE auth_user_id = v_pac_uid;
  SELECT count(*) INTO n FROM public.buscar_medicos_paciente() b WHERE b.id = v_staff;
  IF n <> 0 THEN v_mal := v_mal || 'el staff aparece con el paciente SIN pais_id (rama universal); '; END IF;

  SELECT count(*) INTO n FROM public.buscar_medicos_paciente() b
   WHERE NOT EXISTS (SELECT 1 FROM perfiles p WHERE p.id = b.id AND p.rol = 'medico');
  IF n <> 0 THEN
    v_mal := v_mal || format('con el paciente sin pais_id la RPC devuelve %s no-medico(s); ', n);
  END IF;

  -- Limpieza del camino feliz. El de error lo cubre el rollback del bloque.
  DELETE FROM pacientes WHERE auth_user_id = v_pac_uid;
  DELETE FROM medicos   WHERE id = v_staff;
  DELETE FROM perfiles  WHERE id = v_staff;
  DELETE FROM especialidades WHERE id = v_esp;
  DELETE FROM auth.users WHERE id IN (v_staff, v_pac_uid);

  IF v_mal <> '' THEN RAISE EXCEPTION '299: %', v_mal; END IF;
END $$;

-- Cinturon y tiradores: si el bloque de arriba se hubiera interrumpido de una forma que dejara la
-- siembra viva, esto la borra. Con el camino feliz no toca nada (0 filas).
DELETE FROM public.medicos       WHERE nombre_completo = 'M299 Staff Secretaria';
DELETE FROM public.perfiles      WHERE email = 'm299_staff@ejemplo.invalid';
DELETE FROM public.especialidades WHERE nombre = 'M299 Especialidad de prueba';
DELETE FROM public.pacientes     WHERE nombre = 'M299' AND apellido = 'Paciente Prueba';
