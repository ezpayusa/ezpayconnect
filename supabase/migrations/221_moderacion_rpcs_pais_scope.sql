-- ============================================================================
-- Migración 221: acotar por país 7 RPCs de moderación/aprobación (canjes, especialidades,
--                personalización). A diferencia de la pieza 7, estas SÍ tienen call-site en el front.
-- ============================================================================
-- GAP QUE CIERRA: 7 RPCs de moderación tenían gate solo super_admin. Con admin_pais (migs 216-220)
-- deben admitirlo pero acotado a SU país. super_admin conserva su comportamiento EXACTO (autoridad
-- global) en todos los casos.
--
-- DOS FORMAS según el tipo de RPC:
--   · listar_* (retornan TODAS las filas): se agrega un FILTRO de país en el WHERE
--     (`get_auth_user_rol()='super_admin' OR pais_de_X(id) = get_auth_user_pais_id()`) — super ve todo,
--     admin_pais solo su país. El gate del IF pasa a "super_admin OR admin_pais".
--   · resolver_/aprobar_/rechazar_ (operan sobre UN id): alcanza un gate booleano
--     (super_admin OR (admin_pais AND pais_de_X(id) = get_auth_user_pais_id())).
--
-- 3 HELPERS nuevos que resuelven el país de cada entidad (SQL STABLE DEFINER):
--   · pais_de_canje(bigint): usa premios.pais_id (NOT NULL = siempre resoluble; verificado: nunca
--     difiere de pacientes.pais_id, que es nullable y fail-cerraría filas legacy → premios es el canónico).
--   · pais_de_propuesta_especialidad(uuid): via especialidades_propuestas.medico_id -> medicos.pais_id.
--   · pais_de_solicitud_personalizacion(uuid): polimórfico por tenant_tipo -> clinicas.pais_id /
--     empresas_proveedoras.pais_id.
-- pais NULL de un helper => nunca matchea get_auth_user_pais_id() => fila invisible/denegada para
-- admin_pais (fail-closed natural). Se preserva el estilo de RAISE de cada función (con/sin ERRCODE).
-- ============================================================================

BEGIN;

-- ========================= HELPERS =========================
CREATE OR REPLACE FUNCTION private.pais_de_canje(p_canje_id bigint)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT pr.pais_id
  FROM public.canjes c JOIN public.premios pr ON pr.id = c.premio_id
  WHERE c.id = p_canje_id;
$$;
REVOKE ALL ON FUNCTION private.pais_de_canje(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.pais_de_canje(bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.pais_de_propuesta_especialidad(p_propuesta_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT m.pais_id
  FROM public.especialidades_propuestas ep JOIN public.medicos m ON m.id = ep.medico_id
  WHERE ep.id = p_propuesta_id;
$$;
REVOKE ALL ON FUNCTION private.pais_de_propuesta_especialidad(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.pais_de_propuesta_especialidad(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.pais_de_solicitud_personalizacion(p_solicitud_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE s.tenant_tipo
           WHEN 'clinica'            THEN (SELECT c.pais_id FROM public.clinicas c             WHERE c.id = s.tenant_id)
           WHEN 'empresa_proveedora' THEN (SELECT e.pais_id FROM public.empresas_proveedoras e WHERE e.id = s.tenant_id)
         END
  FROM public.solicitudes_personalizacion s
  WHERE s.id = p_solicitud_id;
$$;
REVOKE ALL ON FUNCTION private.pais_de_solicitud_personalizacion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.pais_de_solicitud_personalizacion(uuid) TO authenticated, service_role;


-- ========================= 1d) listar_canjes_pendientes (search_path='') =========================
CREATE OR REPLACE FUNCTION public.listar_canjes_pendientes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR public.get_auth_user_rol() = 'admin_pais'
  ) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'canje_id', c.id, 'solicitado_at', c.solicitado_at, 'costo_puntos', c.costo_puntos,
             'paciente_id', c.paciente_id, 'paciente_nombre', p.nombre || ' ' || COALESCE(p.apellido, ''),
             'premio_id', c.premio_id, 'premio_nombre', pr.nombre, 'premio_tipo', pr.tipo
           ) ORDER BY c.solicitado_at)
    FROM public.canjes c
    JOIN public.pacientes p  ON p.id  = c.paciente_id
    JOIN public.premios   pr ON pr.id = c.premio_id
    WHERE c.estado = 'pendiente'
      AND (public.get_auth_user_rol() = 'super_admin'
           OR private.pais_de_canje(c.id) = public.get_auth_user_pais_id())
  ), '[]'::jsonb);
END;
$function$;


-- ========================= 1e) resolver_canje (search_path='') =========================
CREATE OR REPLACE FUNCTION public.resolver_canje(_canje_id bigint, _aprobar boolean, _nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_canje RECORD;
  v_estado text;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND private.pais_de_canje(_canje_id) = public.get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución
  SELECT id, paciente_id, premio_id, costo_puntos, estado INTO v_canje
  FROM public.canjes WHERE id = _canje_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'canje_inexistente'; END IF;
  IF v_canje.estado <> 'pendiente' THEN RAISE EXCEPTION 'canje_ya_resuelto'; END IF;

  IF _aprobar THEN
    v_estado := 'aprobado';
    -- puntos y stock YA descontados al solicitar; aprobar no los toca.
  ELSE
    v_estado := 'rechazado';
    -- REVERSA: devolver puntos + stock reservados.
    INSERT INTO public.puntos_movimientos (paciente_id, puntos, tipo, motivo)
    VALUES (v_canje.paciente_id, v_canje.costo_puntos, 'canje_reversa', 'Reversa por rechazo de canje');
    UPDATE public.premios SET stock = stock + 1 WHERE id = v_canje.premio_id;
  END IF;

  UPDATE public.canjes
  SET estado = v_estado, resuelto_at = now(), resuelto_por = auth.uid(), nota_resolucion = _nota
  WHERE id = _canje_id;

  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END;
$function$;


-- ========================= 1f) listar_propuestas_especialidad (search_path='public') =========================
CREATE OR REPLACE FUNCTION public.listar_propuestas_especialidad(p_estado text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR get_auth_user_rol() = 'admin_pais'
  ) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id',                 ep.id,
             'nombre_propuesto',   ep.nombre_propuesto,
             'estado',             ep.estado,
             'created_at',         ep.created_at,
             'resolved_at',        ep.resolved_at,
             'resolved_by',        ep.resolved_by,
             'medico_id',          ep.medico_id,
             'medico_nombre',      m.nombre_completo,
             'resolved_by_nombre', rp.nombre_completo
           )
           ORDER BY (ep.estado = 'pendiente') DESC, ep.created_at DESC)
    FROM public.especialidades_propuestas ep
    LEFT JOIN public.medicos  m  ON m.id  = ep.medico_id
    LEFT JOIN public.perfiles rp ON rp.id = ep.resolved_by       -- super_admin que resolvió (si aplica)
    WHERE (p_estado IS NULL OR ep.estado = p_estado)
      AND (get_auth_user_rol() = 'super_admin'
           OR private.pais_de_propuesta_especialidad(ep.id) = get_auth_user_pais_id())
  ), '[]'::jsonb);
END;
$function$;


-- ========================= 1g) resolver_propuesta_especialidad (search_path='') =========================
CREATE OR REPLACE FUNCTION public.resolver_propuesta_especialidad(p_propuesta_id uuid, p_aprobar boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_prop   RECORD;
  v_esp_id uuid;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND private.pais_de_propuesta_especialidad(p_propuesta_id) = public.get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución.
  SELECT id, medico_id, nombre_propuesto, estado
  INTO v_prop
  FROM public.especialidades_propuestas
  WHERE id = p_propuesta_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'propuesta_inexistente'; END IF;
  IF v_prop.estado <> 'pendiente' THEN RAISE EXCEPTION 'propuesta_ya_resuelta'; END IF;

  IF p_aprobar THEN
    -- a) crear especialidad, o REUSAR la existente por nombre exacto (UNIQUE) sin fallar.
    --    ON CONFLICT DO UPDATE (self no-op) permite RETURNING id tanto en insert nuevo como en reuso, y es race-safe.
    INSERT INTO public.especialidades (nombre, activo)
    VALUES (v_prop.nombre_propuesto, true)
    ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
    RETURNING id INTO v_esp_id;

    -- b) setear la especialidad del médico proponente.
    UPDATE public.medicos SET especialidad_id = v_esp_id WHERE id = v_prop.medico_id;

    -- c) marcar la propuesta como aprobada (referencia la especialidad usada).
    UPDATE public.especialidades_propuestas
    SET estado = 'aprobada', especialidad_id = v_esp_id, resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'aprobada', 'especialidad_id', v_esp_id);
  ELSE
    -- Rechazo: NO tocar medicos ni especialidades, solo marcar.
    UPDATE public.especialidades_propuestas
    SET estado = 'rechazada', resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'rechazada');
  END IF;
  -- Si cualquier paso de la aprobación falla, la excepción revierte TODA la transacción de la función.
END;
$function$;


-- ========================= 1h) listar_solicitudes_personalizacion (search_path='public') =========================
CREATE OR REPLACE FUNCTION public.listar_solicitudes_personalizacion(p_estado text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, tenant_tipo text, tenant_id uuid, tenant_nombre text, estado text, logo_url text, color_primario text, color_secundario text, color_fondo text, motivo_rechazo text, solicitante_nombre text, created_at timestamp with time zone, revisado_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Gate: super_admin (global) o admin_pais (acotado en el WHERE). PT002 = no_autorizado del listador.
  IF NOT (
    EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')
    OR get_auth_user_rol() = 'admin_pais'
  ) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PT002';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.tenant_tipo,
    s.tenant_id,
    CASE s.tenant_tipo
      WHEN 'clinica'            THEN (SELECT c.nombre         FROM public.clinicas c              WHERE c.id = s.tenant_id)
      WHEN 'empresa_proveedora' THEN (SELECT e.nombre_empresa FROM public.empresas_proveedoras e  WHERE e.id = s.tenant_id)
    END AS tenant_nombre,
    s.estado,
    s.logo_url,
    s.color_primario,
    s.color_secundario,
    s.color_fondo,
    s.motivo_rechazo,
    COALESCE(
      (SELECT pf.nombre_completo FROM public.perfiles pf          WHERE pf.id = s.solicitado_por),
      (SELECT cp.nombre_completo FROM public.cuentas_proveedor cp WHERE cp.id = s.solicitado_por),
      'Desconocido'
    ) AS solicitante_nombre,
    s.created_at,
    s.revisado_at
  FROM public.solicitudes_personalizacion s
  WHERE (p_estado IS NULL OR s.estado = p_estado)
    AND (get_auth_user_rol() = 'super_admin'
         OR private.pais_de_solicitud_personalizacion(s.id) = get_auth_user_pais_id())
  ORDER BY s.created_at DESC;
END;
$function$;


-- ========================= 1i) aprobar_personalizacion (search_path='public') =========================
CREATE OR REPLACE FUNCTION public.aprobar_personalizacion(p_solicitud_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_s RECORD;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (get_auth_user_rol() = 'admin_pais' AND private.pais_de_solicitud_personalizacion(p_solicitud_id) = get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;

  SELECT * INTO v_s FROM public.solicitudes_personalizacion WHERE id = p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_s.estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;

  PERFORM set_config('app.personalizacion_rpc','on', true);  -- habilita el guard SOLO en esta tx

  IF v_s.tenant_tipo = 'clinica' THEN
    UPDATE public.clinicas
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  ELSE
    UPDATE public.empresas_proveedoras
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  END IF;

  UPDATE public.solicitudes_personalizacion
    SET estado='aprobada', revisado_por=auth.uid(), revisado_at=now()
    WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok',true,'estado','aprobada','tenant_tipo',v_s.tenant_tipo,'tenant_id',v_s.tenant_id);
END;
$function$;


-- ========================= 1j) rechazar_personalizacion (search_path='public') =========================
CREATE OR REPLACE FUNCTION public.rechazar_personalizacion(p_solicitud_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_estado text;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (get_auth_user_rol() = 'admin_pais' AND private.pais_de_solicitud_personalizacion(p_solicitud_id) = get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;
  SELECT estado INTO v_estado FROM public.solicitudes_personalizacion WHERE id=p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;
  UPDATE public.solicitudes_personalizacion
    SET estado='rechazada', revisado_por=auth.uid(), revisado_at=now(), motivo_rechazo=p_motivo
    WHERE id=p_solicitud_id;
  RETURN jsonb_build_object('ok',true,'estado','rechazada');
END;
$function$;

COMMIT;
