-- RPC de metricas de campana para el PROVEEDOR (los 4 tipos). SECURITY DEFINER: agrega campana_metricas
-- (RLS super_admin-only) scoped a las campanas de mi_empresa_proveedor() SIN ampliar la policy de RLS.
-- Reemplaza el camino roto: hook leia v_metricas_campana_resumen (security_invoker -> 0 filas) y matcheaba
-- por titulo. Ahora usa el link real campanas_publicitarias.empresa_id (bloque A). LEFT JOIN -> 0/0 visible.
CREATE OR REPLACE FUNCTION public.metricas_campana_proveedor()
 RETURNS TABLE(campana_id integer, titulo text, imagen_url text, fecha_inicio date, fecha_fin date,
               impresiones bigint, clicks bigint, usuarios_unicos bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin,
         count(cm.id) FILTER (WHERE cm.clickeado = false) AS impresiones,
         count(cm.id) FILTER (WHERE cm.clickeado = true)  AS clicks,
         count(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos
  FROM public.campanas_publicitarias cp
  LEFT JOIN public.campana_metricas cm ON cm.campana_id = cp.id
  WHERE cp.empresa_id = public.mi_empresa_proveedor()   -- NULL si no es proveedor activo -> 0 filas (fail-closed)
  GROUP BY cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin
  ORDER BY cp.fecha_inicio DESC;
$function$;

REVOKE ALL ON FUNCTION public.metricas_campana_proveedor() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.metricas_campana_proveedor() TO authenticated;
