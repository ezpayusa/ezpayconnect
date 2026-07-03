-- 208 — Listador DEFINER de solicitudes de personalización para el panel Admin EZPayConnect.
-- Molde: listar_canjes_pendientes (RPC DEFINER que devuelve filas ya resueltas para la bandeja).
-- Resuelve server-side, en UNA sola llamada gateada a super_admin:
--   · el NOMBRE del tenant (clinicas.nombre / empresas_proveedoras.nombre_empresa según tenant_tipo)
--   · el NOMBRE del solicitante (perfiles.nombre_completo → cuentas_proveedor.nombre_completo → 'Desconocido')
-- Así el front no necesita leer 4 tablas ni depende de la RLS por-tabla de cada una.

CREATE OR REPLACE FUNCTION public.listar_solicitudes_personalizacion(p_estado text DEFAULT NULL)
RETURNS TABLE (
  id                uuid,
  tenant_tipo       text,
  tenant_id         uuid,
  tenant_nombre     text,
  estado            text,
  logo_url          text,
  color_primario    text,
  color_secundario  text,
  color_fondo       text,
  motivo_rechazo    text,
  solicitante_nombre text,
  created_at        timestamptz,
  revisado_at       timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Defensa en profundidad: la RLS SELECT de solicitudes_personalizacion ya tiene rama super_admin,
  -- pero como esta RPC es DEFINER (bypassa RLS) revalidamos el rol explícitamente acá.
  -- ERRCODE PT002: no_autorizado del listador admin. Se usa PT002 porque era el hueco libre de la
  -- familia PT (PT001=guard trg_guard_tema_columns, PT003=rol_insuf en solicitar, PT004/PT005=
  -- aprobar/rechazar, PT006=sin_tenant). Único por causa → no se reusa PT001 para no confundir dx.
  IF NOT EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin') THEN
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
  ORDER BY s.created_at DESC;
END;
$$;

REVOKE ALL    ON FUNCTION public.listar_solicitudes_personalizacion(text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.listar_solicitudes_personalizacion(text) TO authenticated;
