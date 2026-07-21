-- Frequency cap: cuenta las impresiones (clickeado=false) de las ultimas 24h del PROPIO usuario (auth.uid()),
-- por campana. filtrarCampanasPorFrequencyCap leia campana_metricas directo -> RLS super_admin-only devolvia []
-- -> el cap NUNCA se aplicaba (siempre mostraba todas). SECURITY DEFINER scoped a auth.uid(), sin ampliar RLS.
CREATE OR REPLACE FUNCTION public.mis_impresiones_campana_recientes()
 RETURNS TABLE(campana_id integer, impresiones bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT cm.campana_id, count(*) AS impresiones
  FROM public.campana_metricas cm
  WHERE cm.perfil_id = auth.uid()
    AND cm.clickeado = false
    AND cm.visto_at >= now() - interval '1 day'
  GROUP BY cm.campana_id;
$function$;

REVOKE ALL ON FUNCTION public.mis_impresiones_campana_recientes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mis_impresiones_campana_recientes() TO authenticated;
