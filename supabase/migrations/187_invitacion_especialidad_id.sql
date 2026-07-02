-- 187 Trabajo B Parte 2 (DB) — la invitación de médico transporta especialidad_id (además del texto)
-- El Select curado de especialidad (front) guardará especialidad_id en la invitación; al aceptar,
-- el médico nace con medicos.especialidad_id seteado → aparece en el filtro de especialidad del paciente.
--
-- NOTA: la RPC se reproduce EXACTAMENTE de su definición viva en prod (v_clinica_id UUID, SECURITY DEFINER,
-- SIN search_path — igual que hoy). NO se toca el search_path acá a propósito: el que la función siga
-- SECURITY DEFINER sin search_path queda como cabo suelto de hardening para revisar por separado
-- (no se mezcla con este cambio de columna). Único cambio funcional: agregar especialidad_id al INSERT.

-- ============================================================
-- A) Columna especialidad_id en invitaciones_medico
-- ============================================================
ALTER TABLE public.invitaciones_medico
  ADD COLUMN IF NOT EXISTS especialidad_id uuid REFERENCES public.especialidades(id);

-- ============================================================
-- B) Redefinir registrar_medico_desde_invitacion (misma firma) para setear medicos.especialidad_id
--    desde la invitación. Si inv.especialidad_id es NULL ("sin especialidad") → medicos.especialidad_id NULL, sin fallar.
-- ============================================================
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

  INSERT INTO medicos (id, nombre_completo, email, telefono, especialidad, especialidad_id, pais_id)
  VALUES (p_user_id, p_nombre_completo, p_email,
          COALESCE(p_telefono, v_invitacion.telefono),
          COALESCE(p_especialidad, v_invitacion.especialidad),  -- texto legacy en paralelo (intacto)
          v_invitacion.especialidad_id,                          -- NULL si "sin especialidad" → no falla
          v_pais_id);

  UPDATE perfiles SET rol = 'medico', pais_id = v_pais_id, nombre_completo = p_nombre_completo WHERE id = p_user_id;
  IF v_clinica_id IS NOT NULL THEN
    INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
    VALUES (p_user_id, v_clinica_id, true) ON CONFLICT DO NOTHING;
  END IF;
  UPDATE invitaciones_medico SET estado = 'usada', used_at = NOW() WHERE id = v_invitacion.id;
  RETURN p_user_id;
END; $function$;
