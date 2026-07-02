-- 183 Migración C — RPC de búsqueda ordenada de médicos para el paciente + alineación de estados
--
-- Parte 1: proximo_turno_disponible ahora libera slot con 'cancelada' Y 'rechazada'
--          (estado NOT IN ('cancelada','rechazada')) para ser consistente con slots_ocupados_cita.
--          Único cambio respecto de la mig 182.  (Zona horaria = work item transversal aparte, NO se toca acá.)
--
-- Parte 2: buscar_medicos_paciente(p_especialidad_id) — RPC NUEVA y dedicada a la búsqueda del paciente.
--          NO se modifica listar_medicos_por_pais (la usan CitasPage.tsx, useClinicaCitas.ts, AgendarCitaModal.tsx).
--          País = pacientes.pais_id del auth.uid() (patrón de listar_premios_disponibles).
--          Orden: proximo_turno ASC NULLS LAST, luego nombre_completo.
--          Dos fuentes, igual que listar_medicos_por_pais: tabla medicos + perfiles(rol='medico') registro directo.

-- ============================================================
-- 1) proximo_turno_disponible — alinear estados con slots_ocupados_cita
-- ============================================================
CREATE OR REPLACE FUNCTION public.proximo_turno_disponible(p_medico_id uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH dias AS (
    SELECT g::date AS dia
    FROM generate_series(current_date, current_date + 30, interval '1 day') AS g
  ),
  franjas AS (
    SELECT d.dia, dm.hora_inicio, dm.hora_fin, dm.duracion_slot
    FROM dias d
    JOIN disponibilidad_medico dm
      ON dm.medico_id = p_medico_id
     AND dm.contexto  = 'paciente'
     AND dm.activo    = true
     AND dm.dia_semana = extract(dow FROM d.dia)::int
    WHERE dm.duracion_slot > 0
  ),
  slots AS (
    SELECT
      f.dia,
      (f.hora_inicio +  n      * (f.duracion_slot * interval '1 minute'))::time AS slot_ini,
      (f.hora_inicio + (n + 1) * (f.duracion_slot * interval '1 minute'))::time AS slot_fin
    FROM franjas f
    CROSS JOIN LATERAL generate_series(
      0,
      floor(extract(epoch FROM (f.hora_fin - f.hora_inicio)) / 60.0 / f.duracion_slot)::int - 1
    ) AS n
  )
  SELECT min(s.dia + s.slot_ini)::timestamptz
  FROM slots s
  WHERE (s.dia + s.slot_ini) >= localtimestamp
    AND NOT EXISTS (
      SELECT 1
      FROM citas c
      WHERE c.medico_id   = p_medico_id
        AND c.fecha       = s.dia
        AND c.estado NOT IN ('cancelada','rechazada')   -- << alineado con slots_ocupados_cita
        AND c.hora_inicio < s.slot_fin
        AND c.hora_fin    > s.slot_ini
    );
$$;

REVOKE ALL     ON FUNCTION public.proximo_turno_disponible(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.proximo_turno_disponible(uuid) TO authenticated;

-- ============================================================
-- 2) buscar_medicos_paciente(p_especialidad_id) — listado ordenado para búsqueda del paciente
-- ============================================================
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
      AND (v_pais IS NULL OR m.pais_id = v_pais OR m.pais_id IS NULL)   -- mismo criterio país que listar_medicos_por_pais
      AND (p_especialidad_id IS NULL OR m.especialidad_id = p_especialidad_id)
    UNION ALL
    -- Fuente 2: perfiles rol='medico' registro directo, no presentes en medicos
    SELECT pf.id, pf.nombre_completo, NULL::text, NULL::uuid, pf.avatar_url, pf.activo, pf.pais_id
    FROM perfiles pf
    WHERE pf.rol = 'medico' AND pf.activo = true
      AND (v_pais IS NULL OR pf.pais_id = v_pais OR pf.pais_id IS NULL)
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
