-- ############################################################################################
-- 272 — RPCs de ESCRITURA del modulo comercial (prospectos, contactos, fichas de asesor)
-- ############################################################################################
-- CONTEXTO. Las tres tablas del modulo (asesores_perfil, prospectos, prospecto_contactos)
-- llegan de la 264 con RLS habilitada, UNA policy de SELECT cada una y CERO policies de
-- escritura, y con `authenticated` reducido a SELECT por privilegio directo (verificado contra
-- la base antes de escribir esto, no supuesto). O sea: hoy nadie escribe salvo el owner.
--
-- CONSECUENCIA QUE ORDENA TODA LA MIGRACION: cada una de estas 7 funciones es SECURITY DEFINER
-- y no hay ninguna policy detras que la respalde. La RPC ES el control de acceso completo. No
-- hay segunda linea de defensa que perdone un gate flojo.
--
-- LA REGLA, HEREDADA DE PA-FAILOPEN: *el parametro no es scope*. El pais NO se recibe por
-- parametro en 6 de las 7; se DERIVA de una fila (la ficha del asesor, o el prospecto que se
-- toca) y recien esa derivacion se compara contra el llamante. La unica que recibe pais es
-- guardar_asesor_perfil, porque en un INSERT no hay fila de donde derivarlo — y ahi el gate
-- exige autoridad sobre los DOS paises cuando la ficha se mueve.
--
-- ERRORES: 42501 'no_autorizado' para AUTORIZACION (estandar del proyecto, ya mapeado en el
-- front). PA0xx para REGLAS DE NEGOCIO, que el usuario corrige cambiando el dato. PA001-PA007
-- ya estan tomados por los guards de la 264; esta migracion usa PA008-PA014.
--
-- REPARTO CON LOS GUARDS DE LA 264 — lo que el guard ya valida, la RPC NO lo revalida:
--   PA001/002/003/004  jerarquia de supervisor    -> asignar_supervisor lo DELEGA entero
--   PA005              supervisor no cuelga       -> delegado
--   PA006              pais prospecto = pais ficha-> crear_prospecto y reasignar_prospecto lo DELEGAN
--   PA007              no mover pais con equipo   -> guardar_asesor_perfil lo DELEGA
--   CHECK no_autosupervision / nombre no vacio    -> delegados
--   FK de catalogos                               -> delegada la EXISTENCIA; la RPC valida `activo`
--   UNIQUE (pais_id, nombre_norm) y (pais_id, codigo_asesor) -> delegados
--   nombre_norm  es GENERATED ALWAYS: la RPC NO lo setea (no puede). El anti-duplicado ya anda solo.
--   updated_at   NO tiene trigger: eso si lo setea cada RPC.
-- ############################################################################################

-- ============================================================================================
-- PREDICADOS. Dos, no uno, porque D1 separa dos permisos distintos sobre el mismo prospecto:
--   editar DATOS   -> admin del pais, o el asesor ASIGNADO. El supervisor NO.
--   gestionar      -> admin del pais, o quien tenga al asesor en su CARTERA (incluye supervisor).
-- El "quien manda sobre quien" sale SIEMPRE del chokepoint private.asesores_a_cargo(), nunca
-- escrito a mano: si hubiera dos formas de decirlo, la proxima regla se aplicaria en una sola.
-- El termino de pais va CONJUNTIVO, igual que en las policies de la 264 (doble candado), y todo
-- el gate va dentro de un COALESCE: sin el, un NULL de auth.uid() abriria la puerta.
-- ============================================================================================

CREATE OR REPLACE FUNCTION private.puede_editar_datos_prospecto(p_prospecto_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE((
    SELECT COALESCE(private.puede_admin_pais(pr.pais_id), false)
        OR ( pr.pais_id = private.mi_pais() AND pr.asesor_id = auth.uid() )
      FROM public.prospectos pr
     WHERE pr.id = p_prospecto_id
  ), false);
$function$;

CREATE OR REPLACE FUNCTION private.puede_gestionar_prospecto(p_prospecto_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE((
    SELECT COALESCE(private.puede_admin_pais(pr.pais_id), false)
        OR ( pr.pais_id = private.mi_pais()
             AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = pr.asesor_id) )
      FROM public.prospectos pr
     WHERE pr.id = p_prospecto_id
  ), false);
$function$;

COMMENT ON FUNCTION private.puede_editar_datos_prospecto(uuid) IS
'D1: editar DATOS del prospecto es del admin de pais y del asesor ASIGNADO. El supervisor queda
afuera a proposito — ve la cartera y le mueve el estado, pero no le cambia los datos.
Devuelve false si el prospecto no existe: quien llama no puede distinguir "no existe" de "no podes".';

COMMENT ON FUNCTION private.puede_gestionar_prospecto(uuid) IS
'D1: cambiar estado y cargar contactos es del admin de pais y de quien tenga al asesor en su
CARTERA segun private.asesores_a_cargo() — lo que incluye al asesor sobre si mismo y al supervisor
sobre su equipo. La pertenencia NO se escribe a mano: sale del chokepoint, que es la unica fuente
de verdad de "quien manda sobre quien" en el modulo.';

-- ============================================================================================
-- 1. crear_prospecto — SOLO admin_pais (su pais) y super_admin. Regla fija: el asesor no carga.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.crear_prospecto(
  p_nombre text,
  p_tipo text,
  p_asesor_id uuid,
  p_direccion text DEFAULT NULL,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_notas text DEFAULT NULL,
  p_empresa_proveedora_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_activo boolean; v_rol text; v_id uuid;
BEGIN
  -- LA LINEA QUE ATA EL PARAMETRO AL LLAMANTE: el pais no se recibe, se deriva de la ficha del
  -- asesor. Un admin_pais solo puede crear para asesores de SU pais porque cualquier otro
  -- p_asesor_id produce un v_pais que su propio gate rechaza. Ficha inexistente -> v_pais NULL
  -- -> puede_admin_pais rechaza (fail-closed), asi que el gate corre ANTES que toda regla de
  -- negocio y "no existe" no se distingue de "no podes".
  SELECT ap.pais_id, ap.activo INTO v_pais, v_activo
    FROM public.asesores_perfil ap WHERE ap.id = p_asesor_id;

  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(v_activo, false) THEN
    RAISE EXCEPTION 'PA008: el asesor % tiene la ficha inactiva en asesores_perfil', p_asesor_id
      USING ERRCODE = 'PA008';
  END IF;

  SELECT p.rol INTO v_rol FROM public.perfiles p WHERE p.id = p_asesor_id;
  IF v_rol IS DISTINCT FROM 'asesor_comercial' AND v_rol IS DISTINCT FROM 'supervisor_comercial' THEN
    RAISE EXCEPTION 'PA009: % tiene rol % y no puede llevar prospectos (hace falta asesor_comercial o supervisor_comercial)',
      p_asesor_id, COALESCE(v_rol, '(perfil inexistente)') USING ERRCODE = 'PA009';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_prospecto_tipo c WHERE c.codigo = p_tipo AND c.activo) THEN
    RAISE EXCEPTION 'PA010: el tipo % no existe o esta inactivo en catalogo_prospecto_tipo', COALESCE(p_tipo,'(nulo)')
      USING ERRCODE = 'PA010';
  END IF;

  -- pais_id = v_pais (derivado). guard_pais_prospecto/PA006 lo vuelve a comprobar contra la
  -- ficha: es redundante A PROPOSITO, porque el guard protege tambien al owner.
  -- nombre_norm NO se lista: es GENERATED ALWAYS.
  INSERT INTO public.prospectos
    (nombre, tipo, pais_id, asesor_id, creado_por, estado_pipeline,
     direccion, lat, lng, notas, empresa_proveedora_id)
  VALUES
    (btrim(p_nombre), p_tipo, v_pais, p_asesor_id, auth.uid(), 'nuevo',
     p_direccion, p_lat, p_lng, p_notas, p_empresa_proveedora_id)
  RETURNING id INTO v_id;

  RETURN v_id;
END
$function$;

-- ============================================================================================
-- 2. actualizar_prospecto — admin del pais + asesor ASIGNADO. Supervisor NO (D1).
--    Semantica de VALOR COMPLETO (read-modify-write), no "NULL = no cambiar": con esa otra
--    semantica no hay forma de BORRAR un campo y el front termina inventando centinelas.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.actualizar_prospecto(
  p_prospecto_id uuid,
  p_nombre text,
  p_tipo text,
  p_direccion text DEFAULT NULL,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_notas text DEFAULT NULL,
  p_empresa_proveedora_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  -- LA LINEA QUE ATA: p_prospecto_id es una CLAVE, no un scope. El scope lo dice la fila a la
  -- que apunta, y eso vive en el predicado. Si el prospecto no existe el predicado da false y
  -- sale el mismo 42501: existir-y-no-poder y no-existir son indistinguibles desde afuera.
  IF NOT COALESCE(private.puede_editar_datos_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_prospecto_tipo c WHERE c.codigo = p_tipo AND c.activo) THEN
    RAISE EXCEPTION 'PA010: el tipo % no existe o esta inactivo en catalogo_prospecto_tipo', COALESCE(p_tipo,'(nulo)')
      USING ERRCODE = 'PA010';
  END IF;

  -- NO se tocan asesor_id (eso es reasignar_prospecto) ni pais_id (se deriva del asesor).
  UPDATE public.prospectos SET
    nombre = btrim(p_nombre), tipo = p_tipo, direccion = p_direccion,
    lat = p_lat, lng = p_lng, notas = p_notas,
    empresa_proveedora_id = p_empresa_proveedora_id,
    updated_at = now()
  WHERE id = p_prospecto_id;
END
$function$;

-- ============================================================================================
-- 3. cambiar_estado_prospecto — admin del pais + CARTERA (asesor y supervisor, D1).
--    D1 y D3 son DOS condiciones distintas en esta misma funcion: el supervisor entra al cambio
--    de estado (D1) y NO entra a la reapertura de un terminal (D3).
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.cambiar_estado_prospecto(
  p_prospecto_id uuid,
  p_estado text,
  p_motivo_perdida text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_estado_actual text; v_era_terminal boolean;
BEGIN
  -- LA LINEA QUE ATA: el predicado deriva pais y asesor de la fila y resuelve la pertenencia
  -- por el chokepoint. Ninguna regla de cartera escrita a mano aca adentro.
  IF NOT COALESCE(private.puede_gestionar_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT pr.pais_id, pr.estado_pipeline INTO v_pais, v_estado_actual
    FROM public.prospectos pr WHERE pr.id = p_prospecto_id;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_pipeline_estado c WHERE c.codigo = p_estado AND c.activo) THEN
    RAISE EXCEPTION 'PA010: el estado % no existe o esta inactivo en catalogo_pipeline_estado', COALESCE(p_estado,'(nulo)')
      USING ERRCODE = 'PA010';
  END IF;

  -- D3: reabrir un terminal es del admin de pais / super_admin. El supervisor llego hasta aca
  -- por D1 y se corta justo en este punto — dos condiciones, no una.
  SELECT COALESCE(c.es_terminal, false) INTO v_era_terminal
    FROM public.catalogo_pipeline_estado c WHERE c.codigo = v_estado_actual;
  IF COALESCE(v_era_terminal, false)
     AND p_estado IS DISTINCT FROM v_estado_actual
     AND NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'PA012: el prospecto esta en % (terminal); reabrirlo es del admin de pais', v_estado_actual
      USING ERRCODE = 'PA012';
  END IF;

  IF p_estado = 'perdido' AND COALESCE(btrim(p_motivo_perdida), '') = '' THEN
    RAISE EXCEPTION 'PA011: para marcar un prospecto como perdido hace falta motivo_perdida'
      USING ERRCODE = 'PA011';
  END IF;

  -- al salir de 'perdido' se limpia el motivo: si no, queda un motivo mintiendo sobre un
  -- prospecto que volvio a estar activo.
  UPDATE public.prospectos SET
    estado_pipeline = p_estado,
    motivo_perdida = CASE WHEN p_estado = 'perdido' THEN btrim(p_motivo_perdida) ELSE NULL END,
    updated_at = now()
  WHERE id = p_prospecto_id;
END
$function$;

-- ============================================================================================
-- 4. reasignar_prospecto — SOLO admin_pais y super_admin. Ni supervisor ni asesor (D1/D2).
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.reasignar_prospecto(
  p_prospecto_id uuid,
  p_asesor_nuevo_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_activo boolean; v_rol text;
BEGIN
  -- LA LINEA QUE ATA: el pais sale del PROSPECTO, no del asesor nuevo. Al reves, un admin del
  -- pais B se llevaria prospectos del pais A simplemente pasando un asesor suyo.
  SELECT pr.pais_id INTO v_pais FROM public.prospectos pr WHERE pr.id = p_prospecto_id;

  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT ap.activo INTO v_activo FROM public.asesores_perfil ap WHERE ap.id = p_asesor_nuevo_id;
  IF NOT COALESCE(v_activo, false) THEN
    RAISE EXCEPTION 'PA008: el asesor % no tiene ficha activa en asesores_perfil', p_asesor_nuevo_id
      USING ERRCODE = 'PA008';
  END IF;

  SELECT p.rol INTO v_rol FROM public.perfiles p WHERE p.id = p_asesor_nuevo_id;
  IF v_rol IS DISTINCT FROM 'asesor_comercial' AND v_rol IS DISTINCT FROM 'supervisor_comercial' THEN
    RAISE EXCEPTION 'PA009: % tiene rol % y no puede llevar prospectos', p_asesor_nuevo_id,
      COALESCE(v_rol,'(perfil inexistente)') USING ERRCODE = 'PA009';
  END IF;

  -- Que el asesor nuevo sea del MISMO pais NO se valida aca: lo hace guard_pais_prospecto /
  -- PA006, que dispara en este mismo UPDATE (esta declarado ON UPDATE OF pais_id, asesor_id).
  -- Repetirlo seria una segunda fuente de verdad del mismo invariante.
  UPDATE public.prospectos SET asesor_id = p_asesor_nuevo_id, updated_at = now()
   WHERE id = p_prospecto_id;
END
$function$;

-- ============================================================================================
-- 5. upsert_contacto_prospecto — admin del pais + CARTERA (D1).
--    prospecto_contactos NO tiene trigger NI columna de pais: aca la RPC es el 100% del control.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.upsert_contacto_prospecto(
  p_prospecto_id uuid,
  p_nombre text,
  p_id uuid DEFAULT NULL,
  p_puesto text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_celular text DEFAULT NULL,
  p_es_decisor boolean DEFAULT false,
  p_notas text DEFAULT NULL,
  p_activo boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_padre uuid; v_id uuid;
BEGIN
  IF NOT COALESCE(private.puede_gestionar_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- LA TRAMPA PROPIA DE ESTA RPC: tiene DOS claves y el llamante controla el emparejamiento.
  -- Con p_id de un contacto ajeno y p_prospecto_id de un prospecto propio, el gate de arriba
  -- pasa y se editaria un contacto invisible. El par se RE-DERIVA de la base, no se acepta.
  IF p_id IS NOT NULL THEN
    SELECT c.prospecto_id INTO v_padre FROM public.prospecto_contactos c WHERE c.id = p_id;
    IF v_padre IS DISTINCT FROM p_prospecto_id THEN
      RAISE EXCEPTION 'PA013: el contacto % no pertenece al prospecto %', p_id, p_prospecto_id
        USING ERRCODE = 'PA013';
    END IF;

    UPDATE public.prospecto_contactos SET
      nombre = btrim(p_nombre), puesto = p_puesto, email = p_email,
      telefono = p_telefono, celular = p_celular, es_decisor = COALESCE(p_es_decisor, false),
      notas = p_notas, activo = COALESCE(p_activo, true), updated_at = now()
     WHERE id = p_id
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.prospecto_contactos
    (prospecto_id, nombre, puesto, email, telefono, celular, es_decisor, notas, activo)
  VALUES
    (p_prospecto_id, btrim(p_nombre), p_puesto, p_email, p_telefono, p_celular,
     COALESCE(p_es_decisor, false), p_notas, COALESCE(p_activo, true))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- ============================================================================================
-- 6. guardar_asesor_perfil — admin_pais y super_admin. La UNICA con pais por parametro.
--    NO toca supervisor_id: eso es asignar_supervisor. Sin solapamiento.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.guardar_asesor_perfil(
  p_asesor_id uuid,
  p_codigo_asesor text,
  p_pais_id uuid,
  p_cargo text DEFAULT NULL,
  p_territorio text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_celular text DEFAULT NULL,
  p_fecha_ingreso date DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_activo boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais_actual uuid; v_existe boolean; v_ok_viejo boolean; v_ok_nuevo boolean; v_rol text;
BEGIN
  SELECT ap.pais_id, true INTO v_pais_actual, v_existe
    FROM public.asesores_perfil ap WHERE ap.id = p_asesor_id;

  -- LA LINEA QUE ATA, EN DOS MITADES. En un INSERT no hay fila de donde derivar el pais, asi
  -- que aca p_pais_id es inevitable — es exactamente la forma de la mig 222 que fallaba ABIERTA,
  -- y es correcta SOLO porque puede_admin_pais rechaza NULL y pais ajeno dentro del COALESCE.
  -- En un UPDATE que MUEVE la ficha hacen falta las dos autoridades: con solo la nueva, un admin
  -- se roba fichas del pais vecino; con solo la vieja, las exporta.
  v_ok_nuevo := COALESCE(private.puede_admin_pais(p_pais_id), false);
  v_ok_viejo := CASE WHEN COALESCE(v_existe, false)
                     THEN COALESCE(private.puede_admin_pais(v_pais_actual), false)
                     ELSE v_ok_nuevo END;

  IF NOT (v_ok_viejo OR v_ok_nuevo) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT (v_ok_viejo AND v_ok_nuevo) THEN
    -- solo alcanzable si hay movimiento de pais y el llamante manda sobre UNO de los dos
    RAISE EXCEPTION 'PA014: mover la ficha de % del pais % al pais % exige autoridad sobre los DOS paises',
      p_asesor_id, COALESCE(v_pais_actual::text,'(nuevo)'), COALESCE(p_pais_id::text,'(nulo)')
      USING ERRCODE = 'PA014';
  END IF;

  SELECT p.rol INTO v_rol FROM public.perfiles p WHERE p.id = p_asesor_id;
  IF v_rol IS DISTINCT FROM 'asesor_comercial' AND v_rol IS DISTINCT FROM 'supervisor_comercial' THEN
    RAISE EXCEPTION 'PA009: % tiene rol % y no puede tener ficha comercial', p_asesor_id,
      COALESCE(v_rol,'(perfil inexistente)') USING ERRCODE = 'PA009';
  END IF;

  -- PA007 (no mover de pais una ficha con subordinados) lo pone el guard de la 264 sobre este
  -- mismo UPDATE. No se revalida.
  INSERT INTO public.asesores_perfil
    (id, codigo_asesor, pais_id, cargo, territorio, telefono, celular, fecha_ingreso, bio, activo)
  VALUES
    (p_asesor_id, btrim(p_codigo_asesor), p_pais_id, p_cargo, p_territorio, p_telefono,
     p_celular, p_fecha_ingreso, p_bio, COALESCE(p_activo, true))
  ON CONFLICT (id) DO UPDATE SET
    codigo_asesor = EXCLUDED.codigo_asesor, pais_id = EXCLUDED.pais_id, cargo = EXCLUDED.cargo,
    territorio = EXCLUDED.territorio, telefono = EXCLUDED.telefono, celular = EXCLUDED.celular,
    fecha_ingreso = EXCLUDED.fecha_ingreso, bio = EXCLUDED.bio, activo = EXCLUDED.activo,
    updated_at = now();
END
$function$;

-- ============================================================================================
-- 7. asignar_supervisor — admin_pais del pais de la FICHA y super_admin.
--    La mas corta de las siete a proposito: todo el invariante de jerarquia ya vive en el guard.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.asignar_supervisor(
  p_asesor_id uuid,
  p_supervisor_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_existe boolean;
BEGIN
  -- LA LINEA QUE ATA: el pais sale de la ficha del asesor, nunca del supervisor propuesto.
  SELECT ap.pais_id, true INTO v_pais, v_existe
    FROM public.asesores_perfil ap WHERE ap.id = p_asesor_id;

  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(v_existe, false) THEN
    RAISE EXCEPTION 'PA008: % no tiene ficha en asesores_perfil', p_asesor_id USING ERRCODE = 'PA008';
  END IF;

  -- p_supervisor_id NULL desasigna: asesor sin supervisor es valido (regla fija de Oscar).
  -- Rol del supervisor (PA001), ficha y activo (PA002), mismo pais (PA003), 2 niveles (PA004),
  -- autosupervision (CHECK): TODO delegado al guard de la 264. Esta RPC no revalida ninguno.
  UPDATE public.asesores_perfil
     SET supervisor_id = p_supervisor_id, updated_at = now()
   WHERE id = p_asesor_id;
END
$function$;

-- ============================================================================================
-- PRIVILEGIOS. REVOKE primero y solo, GRANT despues. El REVOKE se re-verifica al final de la
-- migracion: en Supabase toda funcion nace con EXECUTE para PUBLIC, asi que el orden importa.
-- ============================================================================================
REVOKE ALL ON FUNCTION private.puede_editar_datos_prospecto(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.puede_gestionar_prospecto(uuid)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crear_prospecto(text,text,uuid,text,numeric,numeric,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cambiar_estado_prospecto(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reasignar_prospecto(uuid,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.upsert_contacto_prospecto(uuid,text,uuid,text,text,text,text,boolean,text,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guardar_asesor_perfil(uuid,text,uuid,text,text,text,text,date,text,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.asignar_supervisor(uuid,uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION private.puede_editar_datos_prospecto(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.puede_gestionar_prospecto(uuid)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.crear_prospecto(text,text,uuid,text,numeric,numeric,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cambiar_estado_prospecto(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reasignar_prospecto(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_contacto_prospecto(uuid,text,uuid,text,text,text,text,boolean,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guardar_asesor_perfil(uuid,text,uuid,text,text,text,text,date,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.asignar_supervisor(uuid,uuid) TO authenticated;

COMMENT ON FUNCTION public.crear_prospecto(text,text,uuid,text,numeric,numeric,text,uuid) IS
'Alta de prospecto. SOLO admin_pais (su pais) y super_admin — regla fija: el asesor no carga.
El pais NO se recibe: se deriva de la ficha de p_asesor_id y ESE es el pais que se gatea.';

COMMENT ON FUNCTION public.reasignar_prospecto(uuid,uuid) IS
'Reasignacion de cartera. SOLO admin_pais y super_admin: ni el supervisor ni el asesor duenio.
El pais se toma del PROSPECTO, no del asesor nuevo. Que el asesor nuevo sea del mismo pais lo
valida guard_pais_prospecto (PA006) sobre este mismo UPDATE.';

COMMENT ON FUNCTION public.asignar_supervisor(uuid,uuid) IS
'Asigna o desasigna (NULL) supervisor. admin_pais del pais de la ficha y super_admin. Toda la
validacion de la jerarquia esta delegada a private.guard_supervisor_asesor (PA001-PA005) y al
CHECK de autosupervision de la 264; esta funcion no la revalida.';

-- re-verificacion del REVOKE: si anon quedo con EXECUTE en cualquiera de las 9, aborta.
DO $$
DECLARE v_malas text;
BEGIN
  SELECT string_agg(f, ', ') INTO v_malas FROM (
    SELECT p.oid::regprocedure::text AS f
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname, p.proname) IN
           (('public','crear_prospecto'), ('public','actualizar_prospecto'),
            ('public','cambiar_estado_prospecto'), ('public','reasignar_prospecto'),
            ('public','upsert_contacto_prospecto'), ('public','guardar_asesor_perfil'),
            ('public','asignar_supervisor'),
            ('private','puede_editar_datos_prospecto'), ('private','puede_gestionar_prospecto'))
       AND (has_function_privilege('anon', p.oid, 'EXECUTE')
            OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  ) s;
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'privilegios mal en: %', v_malas;
  END IF;
END $$;
