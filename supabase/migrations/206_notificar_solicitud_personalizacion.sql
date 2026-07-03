-- 206 Push a super_admin para solicitudes de personalización (patrón evt5 notificar_cita_solicitada).
-- Wrapper INTERNAL-ONLY (sin GRANT): solo lo invoca solicitar_personalizacion (DEFINER, mismo owner).
-- Deriva todo de p_solicitud_id (anti-spoof). Anti re-spam (solo 'pendiente'). Contenido sin logo/colores crudos.
-- Muro ético: no toca agenda de paciente.

CREATE OR REPLACE FUNCTION public.notificar_solicitud_personalizacion(p_solicitud_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_s RECORD; v_tenant_nombre text; v_solicitante text; v_tipo_label text; v_nid uuid; rec RECORD;
BEGIN
  SELECT sp.tenant_tipo, sp.tenant_id, sp.solicitado_por, sp.estado
    INTO v_s
  FROM public.solicitudes_personalizacion sp
  WHERE sp.id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_s.estado <> 'pendiente' THEN RETURN; END IF;   -- anti re-spam (espejo de evt5)

  IF v_s.tenant_tipo = 'clinica' THEN
    v_tipo_label := 'Clínica';
    SELECT nombre         INTO v_tenant_nombre FROM public.clinicas             WHERE id = v_s.tenant_id;
  ELSE
    v_tipo_label := 'Proveedor';
    SELECT nombre_empresa INTO v_tenant_nombre FROM public.empresas_proveedoras WHERE id = v_s.tenant_id;
  END IF;
  v_tenant_nombre := COALESCE(v_tenant_nombre, 'Sin nombre');
  -- El solicitante puede ser staff clínico (perfiles) o proveedor (cuentas_proveedor). Coalesce + fallback
  -- garantiza no-NULL (si no, el concat de 'mensaje' daría NULL y violaría el NOT NULL de notificaciones).
  SELECT COALESCE(
    (SELECT nombre_completo FROM public.perfiles          WHERE id = v_s.solicitado_por),
    (SELECT nombre_completo FROM public.cuentas_proveedor WHERE id = v_s.solicitado_por),
    'Alguien'
  ) INTO v_solicitante;

  -- Destinatarios: TODOS los super_admin activos (enumeración inline; no hay helper). Un INSERT + push por c/u.
  FOR rec IN SELECT id FROM public.perfiles WHERE rol = 'super_admin' AND COALESCE(activo, true) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
    VALUES (
      rec.id,
      'personalizacion_pendiente',
      'Nueva solicitud de personalización',
      v_tipo_label || ' "' || v_tenant_nombre || '" solicitó cambios de tema (por ' || v_solicitante || '). Revisá en la bandeja.',
      '/admin-ezpay/solicitudes-personalizacion',
      jsonb_build_object('solicitud_id', p_solicitud_id, 'tenant_tipo', v_s.tenant_tipo)  -- deep-link; SIN logo/colores
    )
    RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.notificar_solicitud_personalizacion(uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- solicitar_personalizacion: reproduce la def viva + dispara el push como efecto post-inserción.
-- Firma intacta; grants preservados por CREATE OR REPLACE.
-- ============================================================
CREATE OR REPLACE FUNCTION public.solicitar_personalizacion(
  p_logo_url text, p_color_primario text, p_color_secundario text, p_color_fondo text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_empresa uuid; v_clinica uuid; v_tipo text; v_tenant uuid; v_id uuid;
BEGIN
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NOT NULL THEN
    IF public.mi_rol_proveedor() <> 'admin' THEN RAISE EXCEPTION 'rol_insuficiente' USING ERRCODE='PT003'; END IF;
    v_tipo := 'empresa_proveedora'; v_tenant := v_empresa;
  ELSE
    IF NOT COALESCE(private.tiene_rol(ARRAY['admin_clinica','gerente']), false) THEN
      RAISE EXCEPTION 'rol_insuficiente' USING ERRCODE='PT003'; END IF;
    SELECT s.clinica_id INTO v_clinica
    FROM (SELECT private.clinicas_de(auth.uid()) AS clinica_id) s
    ORDER BY (EXISTS (SELECT 1 FROM public.medico_clinicas mc
                      WHERE mc.medico_id=auth.uid() AND mc.clinica_id=s.clinica_id AND mc.es_principal)) DESC
    LIMIT 1;
    IF v_clinica IS NULL THEN RAISE EXCEPTION 'sin_tenant' USING ERRCODE='PT006'; END IF;
    v_tipo := 'clinica'; v_tenant := v_clinica;
  END IF;

  INSERT INTO public.solicitudes_personalizacion
    (tenant_tipo, tenant_id, logo_url, color_primario, color_secundario, color_fondo, solicitado_por)
  VALUES (v_tipo, v_tenant, p_logo_url, p_color_primario, p_color_secundario, p_color_fondo, auth.uid())
  RETURNING id INTO v_id;

  -- Push a super_admin (post-inserción). Resiliente: si la notificación falla o no hay destinatarios,
  -- la solicitud sobrevive igual (no abortamos el flujo).
  BEGIN
    PERFORM public.notificar_solicitud_personalizacion(v_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notificar_solicitud_personalizacion falló para %: %', v_id, SQLERRM;
  END;

  RETURN v_id;
END;
$function$;
