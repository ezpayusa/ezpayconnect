-- RPC de metricas de campana para el PANEL DEL PAIS (admin_pais / super_admin). SECURITY DEFINER: agrega
-- campana_metricas (RLS super_admin-only) por pais SIN ampliar la policy. Misma FORMA que metricas_campana_proveedor.
-- GATE: super_admin (cualquier pais) O admin_pais cuyo pais asignado == p_pais_id (rechaza admin_pais de OTRO pais).
CREATE OR REPLACE FUNCTION public.metricas_campana_pais(p_pais_id uuid)
 RETURNS TABLE(campana_id integer, titulo text, imagen_url text, fecha_inicio date, fecha_fin date,
               impresiones bigint, clicks bigint, usuarios_unicos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT ( public.get_auth_user_rol() = 'super_admin'
           OR ( public.get_auth_user_rol() = 'admin_pais'
                AND public.get_auth_user_pais_id() = p_pais_id ) ) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin,
           count(cm.id) FILTER (WHERE cm.clickeado = false) AS impresiones,
           count(cm.id) FILTER (WHERE cm.clickeado = true)  AS clicks,
           count(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos
    FROM public.campanas_publicitarias cp
    LEFT JOIN public.campana_metricas cm ON cm.campana_id = cp.id
    WHERE cp.pais_id = p_pais_id
    GROUP BY cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin
    ORDER BY cp.fecha_inicio DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.metricas_campana_pais(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.metricas_campana_pais(uuid) TO authenticated;
