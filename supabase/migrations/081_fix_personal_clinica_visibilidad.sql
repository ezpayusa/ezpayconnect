-- ============================================================
-- FIX — Visibilidad del PERSONAL de la clínica para su admin
-- ------------------------------------------------------------
-- Regresión destapada en prod: la remediación dejó perfiles SELECT = "propio o
-- super_admin". ClinicaPersonalPage leía perfiles DIRECTO (.in(ids)) → un
-- admin_clinica solo veía SU perfil (1 de N). La RLS de perfiles es correcta;
-- lo que falta es un camino DEFINER que le devuelva a un miembro de la clínica
-- el personal de SU clínica, revalidando que pertenece a ella.
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
  -- Revalidación del caller: miembro de ESA clínica (médico/staff/admin) o super_admin.
  IF NOT (
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
