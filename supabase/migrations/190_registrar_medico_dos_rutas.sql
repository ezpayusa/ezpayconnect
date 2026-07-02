-- 190 Auto-registro clínica FASE 3 — registrar_medico_desde_invitacion con DOS rutas
-- Ruta A (invitación TRAE clinica_id, clínica invita médico): comportamiento actual, membresía en esa clínica.
-- Ruta B (invitación SIN clinica_id, admin EzPay): el médico crea su propia clínica vía crear_clinica_con_dueno
--         (dueño + miembro es_principal), nombre 'Consultorio ' || nombre, país del médico.
-- NO se setea medicos.clinica_id (se elimina; requiere medicos.clinica_id nullable = FASE 4 para el alta real).
-- Reproduce la def viva (v_clinica_id UUID, SECURITY DEFINER, especialidad_id de mig 187, sin search_path — hardening aparte).

CREATE OR REPLACE FUNCTION public.registrar_medico_desde_invitacion(
  p_token uuid, p_user_id uuid, p_email text, p_nombre_completo text,
  p_telefono text DEFAULT NULL, p_especialidad text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_invitacion RECORD; v_pais_id UUID; v_clinica_id UUID;
BEGIN
  SELECT * INTO v_invitacion FROM invitaciones_medico
  WHERE token = p_token AND estado = 'pendiente' AND expires_at > NOW() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitación no válida o expirada'; END IF;
  v_pais_id := v_invitacion.pais_id; v_clinica_id := v_invitacion.clinica_id;
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN RAISE EXCEPTION 'El email no coincide con la invitación'; END IF;
  IF EXISTS (SELECT 1 FROM medicos WHERE id = p_user_id) THEN RAISE EXCEPTION 'Este usuario ya está registrado como médico'; END IF;

  -- Crear médico. NO se setea clinica_id (se elimina; requiere medicos.clinica_id nullable = FASE 4).
  INSERT INTO medicos (id, nombre_completo, email, telefono, especialidad, especialidad_id, pais_id)
  VALUES (p_user_id, p_nombre_completo, p_email,
          COALESCE(p_telefono, v_invitacion.telefono),
          COALESCE(p_especialidad, v_invitacion.especialidad),  -- texto legacy en paralelo (intacto)
          v_invitacion.especialidad_id,                          -- NULL si "sin especialidad" → no falla
          v_pais_id);

  UPDATE perfiles SET rol = 'medico', pais_id = v_pais_id, nombre_completo = p_nombre_completo WHERE id = p_user_id;

  IF v_clinica_id IS NOT NULL THEN
    -- Ruta A: la clínica invitó al médico → membresía en ESA clínica (comportamiento actual).
    INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
    VALUES (p_user_id, v_clinica_id, true) ON CONFLICT DO NOTHING;
  ELSE
    -- Ruta B: invitación de admin EzPay sin clínica → el médico crea su propia clínica (dueño + miembro).
    PERFORM public.crear_clinica_con_dueno(
      p_user_id,
      'Consultorio ' || p_nombre_completo,
      v_pais_id
    );
  END IF;

  UPDATE invitaciones_medico SET estado = 'usada', used_at = NOW() WHERE id = v_invitacion.id;
  RETURN p_user_id;
END; $function$;
