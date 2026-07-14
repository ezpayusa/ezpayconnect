-- 258: bandeja del selector de chat multi-médico (lado PACIENTE).
-- El paciente NO puede leer perfiles bajo su RLS (0 filas) → esta RPC DEBE ser DEFINER para
-- resolver nombre/foto de medicos + perfiles server-side. Devuelve SOLO los médicos con relación
-- real (mig 135: citas ∪ medico_primario_id ∪ medico_id), normalizando ambas tablas.
-- NO devuelve último-mensaje ni no-leídos: eso lo arma el front leyendo chat_mensajes por su
-- policy SELECT del paciente. Esta RPC solo dice QUIÉNES son sus médicos y cómo mostrarlos.
-- Errcodes PT020/PT021 (familia PT).
CREATE OR REPLACE FUNCTION public.mis_medicos_chat()
 RETURNS TABLE(
   medico_id       uuid,
   nombre_completo text,
   especialidad    text,
   foto_url        text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_pid integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT020'; END IF;

  SELECT p.id INTO v_pid FROM public.pacientes p WHERE p.auth_user_id = v_uid LIMIT 1;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'No autorizado: el usuario no es un paciente' USING ERRCODE = 'PT021'; END IF;

  RETURN QUERY
  WITH rel AS (
    -- conjunto DISTINCT de médicos con relación real al paciente v_pid
    SELECT DISTINCT r.medico_id
    FROM (
      SELECT c.medico_id            FROM public.citas c     WHERE c.paciente_id = v_pid AND c.medico_id IS NOT NULL
      UNION
      SELECT p.medico_primario_id   FROM public.pacientes p WHERE p.id = v_pid          AND p.medico_primario_id IS NOT NULL
      UNION
      SELECT p.medico_id            FROM public.pacientes p WHERE p.id = v_pid          AND p.medico_id IS NOT NULL
    ) r
    WHERE r.medico_id IS NOT NULL
  )
  SELECT
    rel.medico_id,
    COALESCE(pf.nombre_completo, m.nombre_completo)  AS nombre_completo,
    m.especialidad                                   AS especialidad,   -- NULL si el médico es solo-login
    COALESCE(m.foto_url, pf.avatar_url)              AS foto_url         -- medicos primero (más probable foto real)
  FROM rel
  LEFT JOIN public.perfiles pf ON pf.id = rel.medico_id
  LEFT JOIN public.medicos  m  ON m.id  = rel.medico_id
  WHERE COALESCE(pf.nombre_completo, m.nombre_completo) IS NOT NULL      -- excluye ids colgados / médico borrado
  ORDER BY nombre_completo;
END;
$function$;

REVOKE ALL     ON FUNCTION public.mis_medicos_chat() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mis_medicos_chat() FROM anon;
GRANT  EXECUTE ON FUNCTION public.mis_medicos_chat() TO authenticated;
