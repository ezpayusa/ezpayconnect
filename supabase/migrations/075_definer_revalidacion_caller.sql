-- ============================================================
-- Pasada agrupada — funciones SECURITY DEFINER sin revalidar al caller
-- ------------------------------------------------------------
-- Las 4 eran ejecutables por anon+authenticated y NO revalidaban quién llama →
-- cualquiera (incluido anon) disparaba broadcasts/notificaciones/gestión de
-- visitas ajenas. Patrón de las RPC de citas: SECURITY DEFINER + search_path=''
-- + revalidación interna del caller + REVOKE de anon/public.
--
-- Callers legítimos verificados (frontend + edge functions):
--   enviar_notificacion_promocion → NINGUNO (código muerto) → solo super_admin.
--   notificar_paciente → médico (useRecetas/useMedicoCitas/ConsultaPage) y staff
--     de clínica (useClinicaCitas) avisando a SU paciente.
--   notificar_laboratorio → médico al ordenar examen a ese lab (ConsultaPage).
--   administrar_visita → NINGUNO (la UI AdminVisitas solo LEE) → parte de la visita.
-- ============================================================

-- 1. enviar_notificacion_promocion — broadcast a TODOS los pacientes (marketing)
--    Antes: anon-ejecutable, sin chequeo → spam masivo. Ahora: solo super_admin.
CREATE OR REPLACE FUNCTION public.enviar_notificacion_promocion(
  p_titulo text, p_mensaje text, p_tipo text DEFAULT 'promocion'::text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NOT private.tiene_rol(ARRAY['super_admin']) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin puede enviar promociones masivas';
  END IF;
  INSERT INTO public.notificaciones_pacientes (paciente_id, titulo, mensaje, tipo, leida)
  SELECT id, p_titulo, p_mensaje, p_tipo, false
  FROM public.pacientes;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.enviar_notificacion_promocion(text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.enviar_notificacion_promocion(text,text,text) TO authenticated, service_role;

-- 2. notificar_paciente — 1 notificación a la campanita del paciente
--    Revalida: super_admin / médico que lo atiende / staff de clínica con cita del paciente.
CREATE OR REPLACE FUNCTION public.notificar_paciente(
  p_paciente_id integer, p_tipo text, p_titulo text,
  p_mensaje text DEFAULT NULL::text, p_accion_url text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_id INTEGER;
BEGIN
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR private.medico_atiende_paciente(p_paciente_id::bigint)
    OR EXISTS (SELECT 1 FROM public.citas c
               WHERE c.paciente_id = p_paciente_id
                 AND c.clinica_id IN (SELECT private.clinicas_del_usuario()))
  ) THEN
    RAISE EXCEPTION 'No autorizado para notificar a este paciente';
  END IF;
  INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
  VALUES (p_paciente_id, p_tipo, p_titulo, p_mensaje, p_accion_url, false)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_paciente(integer,text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_paciente(integer,text,text,text,text) TO authenticated, service_role;

-- 3. notificar_laboratorio — notifica a las cuentas activas del laboratorio
--    Revalida: super_admin / miembro del propio lab / médico que ordenó a ese lab.
CREATE OR REPLACE FUNCTION public.notificar_laboratorio(
  p_laboratorio_id uuid, p_tipo text, p_titulo text,
  p_mensaje text DEFAULT NULL::text, p_accion_url text DEFAULT NULL::text)
RETURNS uuid[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_ids UUID[];
BEGIN
  -- COALESCE: mi_empresa_proveedor() es NULL para no-proveedores; sin envolver,
  -- 'false OR NULL OR false' = NULL y 'IF NOT NULL' se salta el RAISE (fail-open).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(public.mi_empresa_proveedor() = p_laboratorio_id, false)
    OR EXISTS (SELECT 1 FROM public.examenes e
               WHERE e.laboratorio_id = p_laboratorio_id AND e.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No autorizado para notificar a este laboratorio';
  END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
  SELECT cp.id, p_tipo, p_titulo, p_mensaje, p_accion_url
  FROM public.cuentas_proveedor cp
  WHERE cp.empresa_id = p_laboratorio_id AND cp.activo = true;

  SELECT array_agg(cp.id) INTO v_ids
  FROM public.cuentas_proveedor cp
  WHERE cp.empresa_id = p_laboratorio_id AND cp.activo = true;

  RETURN COALESCE(v_ids, ARRAY[]::UUID[]);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_laboratorio(uuid,text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_laboratorio(uuid,text,text,text,text) TO authenticated, service_role;

-- 4. administrar_visita — aprobar/rechazar/modificar una visita
--    Antes: sin validar al caller en las primeras líneas. Ahora revalida:
--    super_admin / el médico de la visita / un miembro de la empresa proveedora.
CREATE OR REPLACE FUNCTION public.administrar_visita(
  p_visita_id uuid, p_accion text,
  p_nueva_fecha date DEFAULT NULL::date,
  p_nueva_hora_inicio text DEFAULT NULL::text,
  p_nueva_hora_fin text DEFAULT NULL::text,
  p_comentario text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- Revalidación del caller: aprobada_por referencia cuentas_proveedor → quien
  -- administra es la empresa proveedora (supervisor) o super_admin. El médico es
  -- la parte VISITADA, no el aprobador. COALESCE evita el fail-open trivaluado
  -- (mi_empresa_proveedor() NULL ⇒ 'false OR NULL' = NULL ⇒ RAISE saltado).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(public.mi_empresa_proveedor() = v_visita.empresa_id, false)
  ) THEN
    RAISE EXCEPTION 'No autorizado para administrar esta visita';
  END IF;

  -- aprobada_por solo si el caller es proveedor (su uid ∈ cuentas_proveedor);
  -- para super_admin se preserva el valor previo (no viola la FK).
  IF p_accion = 'aprobar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada');
  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'rechazada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'rechazada');
  ELSIF p_accion = 'modificar' THEN
    UPDATE public.visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin, hora_fin),
        estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada', 'modificado', true);
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.administrar_visita(uuid,text,date,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.administrar_visita(uuid,text,date,text,text,text) TO authenticated, service_role;
