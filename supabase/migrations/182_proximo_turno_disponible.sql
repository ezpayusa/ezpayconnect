-- 182 Migración B — proximo_turno_disponible(medico) → primer slot libre hacia adelante
-- Insumo del algoritmo de orden de búsqueda de médicos ("disponible ahora / próximo").
-- Reglas:
--  * Disponibilidad: disponibilidad_medico del médico con contexto='paciente' AND activo=true.
--    (la tabla comparte contexto con 'visitador' → SIEMPRE filtrar 'paciente').
--  * dia_semana: 0=domingo .. 6=sábado  ==  extract(dow FROM fecha).
--  * duracion_slot en minutos; se generan slots [ini, ini+dur) que quepan dentro de hora_inicio..hora_fin.
--  * Ocupado = existe cita del mismo médico en esa fecha con estado <> 'cancelada' que se solape
--    con el slot (cita.hora_inicio < slot_fin AND cita.hora_fin > slot_ini).
--    Solo 'cancelada' libera (pendiente/solicitada/agendada/confirmada/en_curso cuentan como ocupado).
--  * Horizonte: hoy .. hoy+30 días. Devuelve el timestamptz del primer slot libre >= ahora, o NULL.
--  * Tiempos naïve (wall-clock) del sistema; el timestamptz se construye en la zona de la sesión.

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
      WHERE c.medico_id  = p_medico_id
        AND c.fecha      = s.dia
        AND c.estado    <> 'cancelada'
        AND c.hora_inicio < s.slot_fin
        AND c.hora_fin    > s.slot_ini
    );
$$;

REVOKE ALL     ON FUNCTION public.proximo_turno_disponible(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.proximo_turno_disponible(uuid) TO authenticated;
