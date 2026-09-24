-- ############################################################################################
-- Migracion 326 - M5 (jerarquia en autorizar_invitacion_staff) + M4 (cuenta proveedora inactiva)
-- ############################################################################################
-- M5: public.autorizar_invitacion_staff no comparaba niveles -> un rol NO-admin con permiso
--     usuarios_roles (gerente/gerente_farmacia, nivel 80) podia conceder rol 'admin' (nivel 100),
--     via vincular_membresia_proveedor y el edge invitar-staff-proveedor. Medido en la fase 1.
--     Se agrega la MISMA regla de alta_miembro_farmacia (copiada del cuerpo vivo): un caller que
--     no es es_admin solo concede roles de nivel ESTRICTAMENTE menor al suyo.
-- M4: private.exigir_empresa_activa solo miraba cuentas activas -> una cuenta con activo=false
--     devolvia NULL y no frenaba, dejando actuar a un admin desactivado. Se agrega: si auth.uid()
--     tiene cuenta con activo IS NOT TRUE -> 42501 'Cuenta proveedora inactiva'.
-- Sin cambios de ACL: CREATE OR REPLACE preserva grants/owner/secdef/search_path.
-- ############################################################################################

BEGIN;

-- 0) snapshot de metadata previa (para el autochequeo)
CREATE TEMP TABLE _snap326 (name text, secdef bool, owner text, cfg text, acl text) ON COMMIT DROP;
INSERT INTO _snap326
SELECT p.proname, p.prosecdef, pg_get_userbyid(p.proowner), COALESCE(array_to_string(p.proconfig,','),''),
       COALESCE(array_to_string(p.proacl::text[],'|'),'')
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname='autorizar_invitacion_staff')
   OR (n.nspname='private' AND p.proname='exigir_empresa_activa');

-- 1) M5 -----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.autorizar_invitacion_staff(p_rol text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_emp uuid; v_tipo text; v_caller_rol text;
  v_nuevo_nivel integer; v_asig_nivel integer; v_asig_admin boolean;
BEGIN
  PERFORM private.exigir_empresa_activa();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id, cp.rol_en_empresa INTO v_emp, v_caller_rol
    FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  SELECT e.tipo INTO v_tipo FROM public.empresas_proveedoras e WHERE e.id = v_emp;
  IF NOT EXISTS (SELECT 1 FROM public.roles_empresa_catalogo c WHERE c.tipo_empresa = v_tipo AND c.rol = p_rol) THEN
    RAISE EXCEPTION 'Rol % no concedible para tipo %', p_rol, COALESCE(v_tipo,'(desconocido)') USING ERRCODE = '22023';
  END IF;

  -- JERARQUIA (mig 326): misma regla que alta_miembro_farmacia. Un caller que NO es es_admin solo
  -- puede conceder roles de nivel ESTRICTAMENTE menor al suyo.
  SELECT nivel INTO v_nuevo_nivel FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_rol;
  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_caller_rol;
  IF NOT COALESCE(v_asig_admin, false) THEN
    -- fail-closed trivaluado: cualquier nivel NULL -> rechaza (aunque hoy nivel es NOT NULL).
    IF v_nuevo_nivel IS NULL OR v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes conceder roles de nivel inferior al tuyo' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN jsonb_build_object('empresa_id', v_emp, 'tipo', v_tipo);
END $function$;

-- 2) M4 -----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.exigir_empresa_activa()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_estado text; v_inactiva boolean;
BEGIN
  -- M4 (mig 326): una cuenta proveedora INACTIVA no puede actuar (antes devolvia NULL -> no frenaba).
  SELECT true INTO v_inactiva FROM public.cuentas_proveedor cp
   WHERE cp.id = auth.uid() AND cp.activo IS NOT TRUE LIMIT 1;
  IF v_inactiva THEN
    RAISE EXCEPTION 'Cuenta proveedora inactiva' USING ERRCODE = '42501';
  END IF;

  SELECT e.estado INTO v_estado
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo = true
   LIMIT 1;
  -- Fail-closed acotado: solo bloquea a un PROVEEDOR (cuenta activa) cuya empresa no esta 'activa'.
  -- Si el llamante no es proveedor -> v_estado NULL -> no hace nada.
  IF v_estado IS NOT NULL AND v_estado <> 'activa' THEN
    RAISE EXCEPTION 'Empresa proveedora no activa (estado=%): accion no permitida', v_estado
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- 3) AUTOCHEQUEO -------------------------------------------------------------------------------
DO $ac$
DECLARE v text := ''; r record;
BEGIN
  -- metadata (secdef/owner/cfg/acl) sin cambios vs snapshot
  FOR r IN SELECT * FROM _snap326 LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE p.proname=r.name AND p.prosecdef=r.secdef AND pg_get_userbyid(p.proowner)=r.owner
          AND COALESCE(array_to_string(p.proconfig,','),'')=r.cfg
          AND COALESCE(array_to_string(p.proacl::text[],'|'),'')=r.acl) THEN
      v := v || E'\n(meta) cambio inesperado en '||r.name; END IF;
  END LOOP;
  -- predicados nuevos presentes
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='autorizar_invitacion_staff'
        AND p.prosrc ILIKE '%nivel inferior al tuyo%' AND p.prosrc ILIKE '%v_nuevo_nivel IS NULL%') THEN
    v := v || E'\n(M5) falta la regla de jerarquia fail-closed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='private' AND p.proname='exigir_empresa_activa' AND p.prosrc ILIKE '%Cuenta proveedora inactiva%'
        AND p.prosrc ILIKE '%activo IS NOT TRUE%') THEN
    v := v || E'\n(M4) falta el filtro de cuenta inactiva'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'MIG326 AUTOCHEQUEO FALLA:%', v; END IF;
END $ac$;

COMMIT;
