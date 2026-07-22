-- Extiende metricas_campana_pais: ademas del agregado por campana, devuelve el DUEÑO (empresa_id, nombre, tipo)
-- via LEFT JOIN a empresas_proveedoras. Para desglosar el panel del pais por empresa. Las house-ads del admin
-- (empresa_id NULL) NO se descartan (LEFT JOIN) -> el frontend las agrupa como "EzPay / anuncios propios".
-- Mismo gate (super_admin O admin_pais de p_pais_id), SECURITY DEFINER, search_path='', fail-closed. -f.
-- DROP + CREATE porque cambia el RETURNS TABLE (no basta CREATE OR REPLACE).
DROP FUNCTION IF EXISTS public.metricas_campana_pais(uuid);

CREATE OR REPLACE FUNCTION public.metricas_campana_pais(p_pais_id uuid)
 RETURNS TABLE(campana_id integer, titulo text, imagen_url text, fecha_inicio date, fecha_fin date,
               impresiones bigint, clicks bigint, usuarios_unicos bigint,
               empresa_id uuid, empresa_nombre text, empresa_tipo text)
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
           count(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos,
           cp.empresa_id, ep.nombre_empresa, ep.tipo
    FROM public.campanas_publicitarias cp
    LEFT JOIN public.campana_metricas cm ON cm.campana_id = cp.id
    LEFT JOIN public.empresas_proveedoras ep ON ep.id = cp.empresa_id
    WHERE cp.pais_id = p_pais_id
    GROUP BY cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin, cp.empresa_id, ep.nombre_empresa, ep.tipo
    ORDER BY ep.nombre_empresa NULLS FIRST, cp.fecha_inicio DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.metricas_campana_pais(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.metricas_campana_pais(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
