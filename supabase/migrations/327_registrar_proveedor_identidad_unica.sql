-- ############################################################################################
-- Migracion 327 - registrar_proveedor: identidad unica + email de auth + pais operativo + sin anon
-- ############################################################################################
-- Antes (md5 5272e04eb94a7fe8c861b989cf5003ca, search_path=public, EXECUTE a PUBLIC y anon):
--   * cualquier uid autenticado se daba de alta como admin de una empresa nueva aunque ya tuviera
--     OTRA identidad (paciente, medico, staff, asesor, proveedor). Caso vivo: ecccb4fa (paciente
--     hainibron@ -> admin de 'MedicosPrueba' con email fabienlinea@).
--   * cuentas_proveedor.email salia de p_email, un parametro del cliente: email ajeno arbitrario.
--   * pais_id sin validar: NULL, inexistente o el pais DEMO 'ZZ'.
--   * EXECUTE a PUBLIC y anon (excepcion de producto de la mig 301). El alta real corre con sesion:
--     signUp con autoconfirm devuelve sesion y la RPC se llama como authenticated.
-- Decisiones (Oscar):
--   (a) exclusion total: si el caller ya tiene CUALQUIER identidad -> 42501.
--       Identidades medidas 24-sep (censo de todas las columnas uuid de public contra auth.users):
--       perfiles.id, pacientes.auth_user_id, medicos.id, cuentas_proveedor.id, asesores_perfil.id,
--       usuario_roles.usuario_id. La union cubre el 100% de los uids referenciados en public.
--   (b) el email de la cuenta sale de auth.users.email; p_email se IGNORA (firma intacta por el front).
--   (c) pais_id obligatorio y operativo: existe, activo IS TRUE y codigo <> 'ZZ' -> si no, 22023.
--       ('ZZ' tiene activo=true: el flag solo no alcanza.)
--   (d) REVOKE a PUBLIC y anon; GRANT explicito a authenticated y service_role.
--   Las 2 identidades duales QA existentes (cuentas_proveedor+pacientes) no se tocan.
-- ############################################################################################

BEGIN;

CREATE OR REPLACE FUNCTION public.registrar_proveedor(
  p_nombre_empresa text, p_tipo text, p_ruc_nit text, p_pais_id uuid, p_ciudad text, p_direccion text,
  p_email_contacto text, p_telefono text, p_nombre_completo text, p_email text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_email text;
  v_empresa_id uuid;
BEGIN
  -- (1) sesion
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Usuario no autenticado'; END IF;

  -- (2) identidad unica (mig 327): el caller no puede tener NINGUNA identidad previa.
  IF EXISTS (SELECT 1 FROM public.perfiles          WHERE id = v_user_id)
  OR EXISTS (SELECT 1 FROM public.pacientes         WHERE auth_user_id = v_user_id)
  OR EXISTS (SELECT 1 FROM public.medicos           WHERE id = v_user_id)
  OR EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = v_user_id)
  OR EXISTS (SELECT 1 FROM public.asesores_perfil   WHERE id = v_user_id)
  OR EXISTS (SELECT 1 FROM public.usuario_roles     WHERE usuario_id = v_user_id) THEN
    RAISE EXCEPTION 'La cuenta ya tiene una identidad en la plataforma' USING ERRCODE = '42501';
  END IF;

  -- (3) email de la cuenta = el de auth; p_email se ignora.
  SELECT NULLIF(trim(u.email), '') INTO v_email FROM auth.users u WHERE u.id = v_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'La cuenta no tiene email registrado' USING ERRCODE = '22023';
  END IF;

  -- (4) pais operativo: existe, activo y no es el DEMO 'ZZ'.
  IF p_pais_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.configuracion_pais cp
        WHERE cp.id = p_pais_id AND cp.activo IS TRUE AND cp.codigo <> 'ZZ') THEN
    RAISE EXCEPTION 'País no válido para el registro' USING ERRCODE = '22023';
  END IF;

  -- (5) alta, como antes: empresa pendiente + cuenta admin activa.
  INSERT INTO public.empresas_proveedoras (
    nombre_empresa, tipo, ruc_nit, pais_id, ciudad, direccion, email_contacto, telefono, estado
  ) VALUES (
    p_nombre_empresa, p_tipo, p_ruc_nit, p_pais_id, p_ciudad, p_direccion, p_email_contacto, p_telefono, 'pendiente'
  ) RETURNING id INTO v_empresa_id;

  INSERT INTO public.cuentas_proveedor (id, empresa_id, nombre_completo, email, rol_en_empresa, activo)
  VALUES (v_user_id, v_empresa_id, p_nombre_completo, v_email, 'admin', true);

  RETURN v_empresa_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text) TO authenticated, service_role;

-- AUTOCHEQUEO -------------------------------------------------------------------------------------
DO $ac$
DECLARE v text := ''; f regprocedure := 'public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'::regprocedure;
  r record;
BEGIN
  SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.proconfig, p.prosrc,
         ARRAY(SELECT a::text FROM unnest(p.proacl) a ORDER BY 1) AS acl
    INTO r FROM pg_proc p WHERE p.oid = f;
  IF NOT r.prosecdef THEN v := v||E'\n no es SECURITY DEFINER'; END IF;
  IF r.owner <> 'postgres' THEN v := v||E'\n owner='||r.owner; END IF;
  IF r.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN v := v||E'\n proconfig='||COALESCE(r.proconfig::text,'NULL'); END IF;
  IF r.acl IS DISTINCT FROM ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres'] THEN
    v := v||E'\n proacl='||r.acl::text; END IF;
  IF has_function_privilege('anon', f, 'EXECUTE') THEN v := v||E'\n anon conserva EXECUTE'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = f AND a.grantee = 0) THEN
    v := v||E'\n PUBLIC conserva EXECUTE'; END IF;
  IF r.prosrc NOT ILIKE '%ya tiene una identidad en la plataforma%'
     OR r.prosrc NOT ILIKE '%public.perfiles%' OR r.prosrc NOT ILIKE '%public.pacientes%'
     OR r.prosrc NOT ILIKE '%public.medicos%' OR r.prosrc NOT ILIKE '%public.cuentas_proveedor%'
     OR r.prosrc NOT ILIKE '%public.asesores_perfil%' OR r.prosrc NOT ILIKE '%public.usuario_roles%' THEN
    v := v||E'\n falta el chequeo de identidad (6 tablas)'; END IF;
  IF r.prosrc NOT ILIKE '%País no válido para el registro%' OR r.prosrc NOT ILIKE '%activo IS TRUE%'
     OR r.prosrc NOT ILIKE '%codigo <> ''ZZ''%' THEN
    v := v||E'\n falta el chequeo de pais operativo'; END IF;
  IF r.prosrc NOT ILIKE '%FROM auth.users%' OR r.prosrc ILIKE '%p_email)%' THEN
    v := v||E'\n el email no sale de auth.users'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'MIG327 AUTOCHEQUEO FALLA:%', v; END IF;
END $ac$;

COMMIT;
