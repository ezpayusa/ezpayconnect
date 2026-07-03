-- ============================================================================
-- Migración 222 (pieza 8b): acotar por país 4 RPCs — notificaciones de empresa/pago/campaña +
--                aprobación de campaña. Todas con call-site real en el front.
-- ============================================================================
-- GAP QUE CIERRA: 4 RPCs con gate solo super_admin (una con vestigio de roles inexistentes).
-- Con admin_pais (migs 216-221) pasan a admitirlo acotado a SU país; super_admin conserva su
-- comportamiento EXACTO. El único cambio en cada función es la condición del gate.
--
-- VESTIGIO INTACTO: notificar_empresa_estado / _pago_resultado / _campana_resultado gatean con
-- tiene_rol(['ezpay_admin','super_admin','admin_finanzas']). 'ezpay_admin' y 'admin_finanzas' NO
-- existen en roles_catalogo → en la práctica ese array solo deja pasar super_admin. NO se limpia ni
-- se toca ese array (es un cambio aparte); solo se le AGREGA una rama OR para admin_pais.
--
-- HELPER nuevo: private.pais_de_pago_proveedor(uuid) via pagos_proveedor.empresa_id ->
-- empresas_proveedoras.pais_id (mismo estilo que los helpers de pieza 8a). Para campañas el país es
-- directo (solicitudes_campana.pais_id NOT NULL) → chequeo inline, sin helper. Para empresa se reusa
-- private.admin_puede_gestionar_empresa (pieza 7), que ya resuelve "la empresa es de mi país".
-- ============================================================================

BEGIN;

-- ========================= 1a) HELPER pais_de_pago_proveedor =========================
CREATE OR REPLACE FUNCTION private.pais_de_pago_proveedor(p_pago_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.pais_id
  FROM public.pagos_proveedor pg JOIN public.empresas_proveedoras e ON e.id = pg.empresa_id
  WHERE pg.id = p_pago_id;
$$;
REVOKE ALL ON FUNCTION private.pais_de_pago_proveedor(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.pais_de_pago_proveedor(uuid) TO authenticated, service_role;


-- ========================= 1b) notificar_empresa_estado (search_path='') =========================
CREATE OR REPLACE FUNCTION public.notificar_empresa_estado(p_empresa_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_estado text; v_titulo text; v_msg text; rec record;
BEGIN
  -- Vestigio de roles NO se toca (ezpay_admin/admin_finanzas no existen → solo super_admin pasa por ahí).
  -- Se AGREGA la rama admin_pais: empresa de su país (helper de pieza 7).
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND private.admin_puede_gestionar_empresa(p_empresa_id))
  ) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado INTO v_estado FROM public.empresas_proveedoras WHERE id = p_empresa_id;
  IF NOT FOUND OR v_estado IS NULL THEN RETURN; END IF;
  v_titulo := CASE WHEN v_estado = 'activa' THEN 'Empresa aprobada' ELSE 'Estado de tu empresa actualizado' END;
  v_msg := CASE WHEN v_estado = 'activa' THEN 'Tu empresa fue aprobada. Ya puedes operar en EzPayConnect.'
                ELSE 'El estado de tu empresa cambió a: ' || v_estado || '.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(p_empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'empresa', v_titulo, v_msg, '/proveedor/dashboard');
  END LOOP;
END;
$function$;


-- ========================= 1c) notificar_pago_resultado (search_path='') =========================
CREATE OR REPLACE FUNCTION public.notificar_pago_resultado(p_pago_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND private.pais_de_pago_proveedor(p_pago_id) = public.get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, empresa_id INTO v FROM public.pagos_proveedor WHERE id = p_pago_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('verificado','rechazado') THEN RETURN; END IF;  -- estado notificable
  v_titulo := CASE WHEN v.estado = 'verificado' THEN 'Pago verificado' ELSE 'Pago rechazado' END;
  v_msg := CASE WHEN v.estado = 'verificado' THEN 'Tu pago fue verificado y el servicio quedó activo.'
                ELSE 'Tu pago fue rechazado. Revisa el comprobante o contacta a EzPayConnect.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'pago', v_titulo, v_msg, '/proveedor/pagos');
  END LOOP;
END;
$function$;


-- ========================= 1d) notificar_campana_resultado (search_path='') =========================
CREATE OR REPLACE FUNCTION public.notificar_campana_resultado(p_solicitud_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND EXISTS (
          SELECT 1 FROM public.solicitudes_campana WHERE id = p_solicitud_id AND pais_id = public.get_auth_user_pais_id()
        ))
  ) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, titulo, empresa_id, notas_admin INTO v FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('publicada','rechazada') THEN RETURN; END IF;  -- estado notificable
  IF v.estado = 'publicada' THEN
    v_titulo := 'Campaña aprobada';
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue aprobada y publicada.';
  ELSE
    v_titulo := 'Campaña rechazada';
    -- notas_admin PERSISTIDO en el ref (no param del caller) → se incluye si existe
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue rechazada.' || COALESCE(' Motivo: ' || NULLIF(v.notas_admin,''), '');
  END IF;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'campana', v_titulo, v_msg, '/proveedor/publicidad/campanas');
  END LOOP;
END;
$function$;


-- ========================= 1e) aprobar_solicitud_campana (search_path='') =========================
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_s RECORD; v_campana_id integer;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND EXISTS (
          SELECT 1 FROM public.solicitudes_campana WHERE id = p_solicitud_id AND pais_id = public.get_auth_user_pais_id()
        ))
  ) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada'; END IF;
  -- validación existente (que la empresa realmente opere en el país de la campaña): NO se toca.
  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el país de la campaña';
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
    SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
    WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$;

COMMIT;
