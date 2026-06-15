-- ============================================================
-- Robustez — obtener_personal_clinica: blindar el guard contra p_clinica_id NULL
-- ------------------------------------------------------------
-- Sin esto, con p_clinica_id NULL la condición trivaluada
-- `IF NOT (false OR NULL IN (...))` daba NULL → el RAISE se saltaba y la función
-- devolvía 0 filas (no fuga, pero no fail-closed limpio). Añadimos `p_clinica_id
-- IS NULL OR NOT (...)` → con NULL ahora LANZA. Resto idéntico a la 081.
-- ============================================================

CREATE OR REPLACE FUNCTION public.obtener_personal_clinica(p_clinica_id uuid)
RETURNS TABLE(
  medico_id uuid,
  nombre_completo text,
  email text,
  rol text,
  telefono text,
  especialidad text,
  es_principal boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF p_clinica_id IS NULL OR NOT (
       COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR p_clinica_id IN (SELECT private.clinicas_del_usuario())
  ) THEN
    RAISE EXCEPTION 'No autorizado para ver el personal de esta clínica';
  END IF;

  RETURN QUERY
  SELECT mc.medico_id,
         p.nombre_completo,
         p.email,
         p.rol,
         p.telefono,
         m.especialidad,
         COALESCE(mc.es_principal, false)
  FROM public.medico_clinicas mc
  JOIN public.perfiles p ON p.id = mc.medico_id
  LEFT JOIN public.medicos m ON m.id = mc.medico_id
  WHERE mc.clinica_id = p_clinica_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.obtener_personal_clinica(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.obtener_personal_clinica(uuid) TO authenticated, service_role;
