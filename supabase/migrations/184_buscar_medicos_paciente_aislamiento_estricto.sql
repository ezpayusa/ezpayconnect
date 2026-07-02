-- 184 Ajuste — aislamiento estricto de país en buscar_medicos_paciente
-- Superficie de cara al paciente: CERO fuga entre países.
-- Cambio vs. 183: quitar "OR pais_id IS NULL" en ambas fuentes.
--   Antes: (v_pais IS NULL OR pais_id = v_pais OR pais_id IS NULL)
--   Ahora: (v_pais IS NULL OR pais_id = v_pais)
-- Se mantiene "v_pais IS NULL OR" solo para el caso de paciente sin país derivado.
-- Un médico sin pais_id NO aparece para un paciente con país definido.
-- (El mismo hueco en listar_medicos_por_pais queda como work item aparte — verificar sus 3 consumidores antes de tocarla.)

CREATE OR REPLACE FUNCTION public.buscar_medicos_paciente(p_especialidad_id uuid DEFAULT NULL)
RETURNS TABLE (
  id              uuid,
  nombre_completo text,
  especialidad    text,
  especialidad_id uuid,
  foto_url        text,
  activo          boolean,
  pais_id         uuid,
  proximo_turno   timestamptz
)
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
  WITH base AS (
    -- Fuente 1: tabla medicos (invitados por clínicas)
    SELECT m.id, m.nombre_completo, m.especialidad, m.especialidad_id, m.foto_url, m.activo, m.pais_id
    FROM medicos m
    WHERE m.activo = true
      AND (v_pais IS NULL OR m.pais_id = v_pais)   -- aislamiento estricto: sin "OR pais_id IS NULL"
      AND (p_especialidad_id IS NULL OR m.especialidad_id = p_especialidad_id)
    UNION ALL
    -- Fuente 2: perfiles rol='medico' registro directo, no presentes en medicos
    SELECT pf.id, pf.nombre_completo, NULL::text, NULL::uuid, pf.avatar_url, pf.activo, pf.pais_id
    FROM perfiles pf
    WHERE pf.rol = 'medico' AND pf.activo = true
      AND (v_pais IS NULL OR pf.pais_id = v_pais)   -- aislamiento estricto
      AND p_especialidad_id IS NULL   -- perfiles no tiene especialidad_id; si se filtra por especialidad, no aplican
      AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = pf.id)
  ),
  con_turno AS (
    SELECT b.*, public.proximo_turno_disponible(b.id) AS proximo_turno
    FROM base b
  )
  SELECT ct.id, ct.nombre_completo, ct.especialidad, ct.especialidad_id,
         ct.foto_url, ct.activo, ct.pais_id, ct.proximo_turno
  FROM con_turno ct
  ORDER BY ct.proximo_turno ASC NULLS LAST, ct.nombre_completo;
END;
$$;

REVOKE ALL     ON FUNCTION public.buscar_medicos_paciente(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.buscar_medicos_paciente(uuid) TO authenticated;
