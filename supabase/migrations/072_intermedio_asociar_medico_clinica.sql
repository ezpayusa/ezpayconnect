-- ============================================================
-- PASO INTERMEDIO (pre-Fase 4) · Endurecer asociar_medico_clinica
-- ------------------------------------------------------------
-- Hoy: SECURITY DEFINER, EXECUTE a anon+authenticated, sin revalidar → cualquiera
-- inserta en medico_clinicas y se asocia (o asocia a otro) a cualquier clínica =
-- ESCALADA DE TENANT que burla el aislamiento por clínica de Fases 2-3.
--
-- Único llamador legítimo: la edge function crear-staff-clinica (service_role).
-- El flujo de invitación (registrar_*_desde_invitacion) inserta en medico_clinicas
-- DIRECTO (no usa esta función) → no se rompe. El frontend NO la llama.
--
-- Regla de dos capas:
--  (1) GRANT: revocar de anon/public/authenticated; solo service_role.
--  (2) Defensa en profundidad: si hay usuario autenticado (auth.uid() no NULL),
--      debe ser admin de ESA clínica o super_admin; service_role (auth.uid() NULL)
--      pasa (lo llama la edge function, que valida al solicitante por su lado).
-- ============================================================

CREATE OR REPLACE FUNCTION public.asociar_medico_clinica(
  p_medico_id uuid, p_clinica_id uuid, p_es_principal boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND NOT (private.es_admin_clinica(p_clinica_id) OR private.tiene_rol(ARRAY['super_admin'])) THEN
    RAISE EXCEPTION 'No autorizado para asociar a esta clínica';
  END IF;

  INSERT INTO public.medico_clinicas (medico_id, clinica_id, es_principal)
  VALUES (p_medico_id, p_clinica_id, p_es_principal)
  ON CONFLICT (medico_id, clinica_id) DO UPDATE SET es_principal = EXCLUDED.es_principal;
END; $$;

REVOKE EXECUTE ON FUNCTION public.asociar_medico_clinica(uuid, uuid, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.asociar_medico_clinica(uuid, uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.asociar_medico_clinica(uuid, uuid, boolean) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.asociar_medico_clinica(uuid, uuid, boolean) TO service_role;
