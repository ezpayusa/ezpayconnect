-- 185 RPC listar_especialidades_activas — para el select de especialidad del paciente
-- Devuelve SOLO especialidades (catálogo activo) que tengan >=1 médico activo en el país del paciente.
-- País derivado server-side de pacientes.pais_id vía auth.uid() (mismo patrón que buscar_medicos_paciente /
-- listar_premios_disponibles). Aislamiento estricto: m.pais_id = v_pais (sin "OR pais_id IS NULL", igual que 184).
-- Orden alfabético por nombre.

CREATE OR REPLACE FUNCTION public.listar_especialidades_activas()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid  uuid;
  v_pais uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT p.pais_id INTO v_pais FROM pacientes p WHERE p.auth_user_id = v_uid;

  RETURN QUERY
  SELECT e.id, e.nombre
  FROM especialidades e
  WHERE e.activo = true
    AND EXISTS (
      SELECT 1
      FROM medicos m
      WHERE m.especialidad_id = e.id      -- garantiza especialidad_id IS NOT NULL
        AND m.activo  = true
        AND m.pais_id = v_pais            -- aislamiento estricto (v_pais NULL ⇒ sin match ⇒ [])
    )
  ORDER BY e.nombre;
END;
$$;

REVOKE ALL     ON FUNCTION public.listar_especialidades_activas() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_especialidades_activas() TO authenticated;
