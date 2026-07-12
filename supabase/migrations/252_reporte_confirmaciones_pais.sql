-- 252: RPC de reporte de confirmaciones de recepción de receta, país-scoped.
-- super_admin: todos (o filtra p_pais_id). admin_pais: forzado a su país (ignora p_pais_id).
-- otro rol: RAISE PC020. Lee confirmaciones_receta (agregado por país, sin PHI).

CREATE OR REPLACE FUNCTION public.reporte_confirmaciones_pais(
  p_desde date,
  p_hasta date,
  p_pais_id uuid DEFAULT NULL
)
RETURNS TABLE (pais_id uuid, pais_nombre text, confirmaciones bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_rol         text := public.get_auth_user_rol();
  v_pais_caller uuid := public.get_auth_user_pais_id();
  v_filtro_pais uuid;
BEGIN
  -- Gate de rol (cortocircuito super_admin, patrón admin_pais)
  IF v_rol = 'super_admin' THEN
    v_filtro_pais := p_pais_id;            -- NULL = todos los países
  ELSIF v_rol = 'admin_pais' THEN
    IF v_pais_caller IS NULL THEN
      RAISE EXCEPTION 'admin_pais sin pais asignado' USING ERRCODE = 'PC020';
    END IF;
    v_filtro_pais := v_pais_caller;        -- forzado al suyo, ignora p_pais_id
  ELSE
    RAISE EXCEPTION 'No autorizado: solo super_admin o admin_pais' USING ERRCODE = 'PC020';
  END IF;

  RETURN QUERY
    SELECT c.pais_id,
           cp.nombre::text,
           count(*)::bigint
      FROM public.confirmaciones_receta c
      JOIN public.configuracion_pais cp ON cp.id = c.pais_id
     WHERE c.confirmada_at >= p_desde::timestamptz
       AND c.confirmada_at <  (p_hasta + 1)::timestamptz   -- inclusivo del dia p_hasta
       AND (v_filtro_pais IS NULL OR c.pais_id = v_filtro_pais)
     GROUP BY c.pais_id, cp.nombre
     ORDER BY 3 DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.reporte_confirmaciones_pais(date, date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_confirmaciones_pais(date, date, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reporte_confirmaciones_pais(date, date, uuid) TO authenticated;
