-- ============================================================================
-- Migración 233 (para "Nueva cita" del calendario de clínica): el staff puede
-- BUSCAR pacientes de su clínica y dar de ALTA un paciente nuevo (registro completo,
-- SIN auth_user_id — el índice único parcial de mig 230 ya contempla NULLs). NO es el
-- flujo de admisión (documentos/consentimientos/foto), solo el registro en `pacientes`.
-- Ambas DEFINER, gateadas por private.es_staff_calendario_clinica (mismos 7 roles + super_admin).
-- ============================================================================

BEGIN;

-- (1) Búsqueda de pacientes DE LA CLÍNICA (para adjuntar a una cita nueva).
--     Scope: clinica_primaria_id = clínica  OR  medico_id ∈ médicos de la clínica.
CREATE OR REPLACE FUNCTION public.buscar_pacientes_clinica(p_clinica_id uuid, p_texto text)
RETURNS TABLE(paciente_id bigint, nombre text, apellido text, telefono text, fecha_nacimiento date, foto_path text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_q text;
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para buscar pacientes de esta clínica';
  END IF;
  IF p_texto IS NULL OR length(trim(p_texto)) < 2 THEN
    RETURN;  -- no volcar toda la tabla ante textos vacíos/cortos
  END IF;
  v_q := '%' || trim(p_texto) || '%';
  RETURN QUERY
    SELECT p.id, p.nombre, p.apellido, p.telefono, p.fecha_nacimiento, p.foto_path
    FROM public.pacientes p
    WHERE p.activo = true
      AND ( p.clinica_primaria_id = p_clinica_id
            OR p.medico_id IN (SELECT mc.medico_id FROM public.medico_clinicas mc WHERE mc.clinica_id = p_clinica_id) )
      AND ( p.nombre ILIKE v_q OR p.apellido ILIKE v_q
            OR (p.nombre || ' ' || p.apellido) ILIKE v_q OR p.telefono ILIKE v_q )
    ORDER BY p.nombre, p.apellido
    LIMIT 20;
END; $fn$;

-- (2) Alta de paciente por staff de clínica (registro completo, SIN auth_user_id).
CREATE OR REPLACE FUNCTION public.crear_paciente_clinica(
  p_clinica_id uuid, p_nombre text, p_apellido text,
  p_telefono text DEFAULT NULL, p_fecha_nacimiento date DEFAULT NULL,
  p_genero text DEFAULT NULL, p_email text DEFAULT NULL, p_pais_id uuid DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_id bigint; v_pais uuid;
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para crear pacientes en esta clínica';
  END IF;
  IF p_nombre IS NULL OR btrim(p_nombre) = '' OR p_apellido IS NULL OR btrim(p_apellido) = '' THEN
    RAISE EXCEPTION 'Nombre y apellido son obligatorios';
  END IF;
  v_pais := COALESCE(p_pais_id, (SELECT c.pais_id FROM public.clinicas c WHERE c.id = p_clinica_id));

  INSERT INTO public.pacientes
    (nombre, apellido, telefono, fecha_nacimiento, genero, email, pais_id, clinica_primaria_id, activo, auth_user_id)
  VALUES
    (btrim(p_nombre), btrim(p_apellido), NULLIF(btrim(COALESCE(p_telefono,'')),''), p_fecha_nacimiento,
     NULLIF(p_genero,''), NULLIF(btrim(COALESCE(p_email,'')),''), v_pais, p_clinica_id, true, NULL)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $fn$;

-- Hardening EXECUTE: solo authenticated (REVOKE de PUBLIC y anon por default privileges).
REVOKE EXECUTE ON FUNCTION public.buscar_pacientes_clinica(uuid,text)                          FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.crear_paciente_clinica(uuid,text,text,text,date,text,text,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.buscar_pacientes_clinica(uuid,text)                          TO authenticated;
GRANT  EXECUTE ON FUNCTION public.crear_paciente_clinica(uuid,text,text,text,date,text,text,uuid) TO authenticated;

COMMIT;
