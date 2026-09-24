-- ROLLBACK mig 326 — restaura los cuerpos previos de autorizar_invitacion_staff y exigir_empresa_activa.
CREATE OR REPLACE FUNCTION public.autorizar_invitacion_staff(p_rol text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_caller uuid := auth.uid(); v_emp uuid; v_tipo text;
BEGIN
  PERFORM private.exigir_empresa_activa();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id INTO v_emp FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  SELECT e.tipo INTO v_tipo FROM public.empresas_proveedoras e WHERE e.id = v_emp;
  IF NOT EXISTS (SELECT 1 FROM public.roles_empresa_catalogo c WHERE c.tipo_empresa = v_tipo AND c.rol = p_rol) THEN
    RAISE EXCEPTION 'Rol % no concedible para tipo %', p_rol, COALESCE(v_tipo,'(desconocido)') USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('empresa_id', v_emp, 'tipo', v_tipo);
END $function$;

CREATE OR REPLACE FUNCTION private.exigir_empresa_activa()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_estado text;
BEGIN
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

-- Autochequeo: md5 restaurado == md5 vivo capturado en la fase 1 (2026-09-24).
DO $rb$
DECLARE v text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='autorizar_invitacion_staff' AND md5(p.prosrc)='c19122de15eb939d9b1199af7d4272b0') THEN v:=v||' autorizar_invitacion_staff'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='exigir_empresa_activa' AND md5(p.prosrc)='14dafe11fe1b8cbe3e3acec938970b63') THEN v:=v||' exigir_empresa_activa'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK326: md5 no coincide:%', v; END IF;
END $rb$;
