-- ============================================================================
-- Migración 231 (Mig A del calendario de clínica): amplía SOLO la rama (c) de crear_cita
-- para que el staff de agenda de la clínica (admin_clinica/gerente/admin/secretaria/
-- asistente_medico — SIN enfermería) pueda crear citas en SU clínica. Antes solo lo permitía
-- private.es_admin_clinica (admin_clinica/gerente). Las ramas (a) paciente, (b) médico y
-- (d) super_admin quedan IDÉNTICAS. Gate por private.clinicas_del_usuario() (staff resuelve
-- su clínica vía medico_clinicas).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.crear_cita(
  p_paciente_id bigint,
  p_medico_id uuid DEFAULT NULL::uuid,
  p_clinica_id uuid DEFAULT NULL::uuid,
  p_fecha date DEFAULT NULL::date,
  p_hora_inicio time without time zone DEFAULT NULL::time without time zone,
  p_hora_fin time without time zone DEFAULT NULL::time without time zone,
  p_motivo text DEFAULT NULL::text,
  p_notas text DEFAULT NULL::text,
  p_estado text DEFAULT 'agendada'::text,
  p_pais_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_cita_id     BIGINT;
  v_es_paciente BOOLEAN;
  v_estado      TEXT;
  v_pais        UUID;
BEGIN
  v_es_paciente := EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = p_paciente_id AND p.auth_user_id = auth.uid());

  -- Autorización + COHERENCIA paciente/médico con el caller:
  IF NOT (
       -- (a) un paciente crea SU propia cita CON UN MÉDICO DE SU PROPIO PAÍS (deuda c)
       ( v_es_paciente AND COALESCE(private.medico_en_mi_pais_viewer(p_medico_id), false) )
       -- (b) un médico se pone a SÍ MISMO y solo para un paciente que YA atiende
       OR ( p_medico_id = auth.uid()
            AND (private.es_medico_de(p_paciente_id) OR private.medico_atiende_paciente(p_paciente_id)) )
       -- (c) staff de agenda de la clínica (admin_clinica/gerente/admin/secretaria/asistente_medico,
       --     SIN enfermería): para SU clínica, con un médico de esa clínica (o sin médico aún)
       OR ( p_clinica_id IS NOT NULL
            AND private.tiene_rol(ARRAY['admin_clinica','gerente','admin','secretaria','asistente_medico'])
            AND p_clinica_id IN (SELECT private.clinicas_del_usuario())
            AND ( p_medico_id IS NULL
                  OR EXISTS (SELECT 1 FROM public.medico_clinicas mc
                             WHERE mc.medico_id = p_medico_id AND mc.clinica_id = p_clinica_id) ) )
       -- (d) super_admin
       OR private.tiene_rol(ARRAY['super_admin'])
  ) THEN
    RAISE EXCEPTION 'No autorizado para crear esta cita (paciente/médico/país incoherentes con el usuario)';
  END IF;

  -- Estado inicial FORZADO por rol (se ignora p_estado del caller): el paciente queda
  -- en 'solicitada' hasta que la clínica apruebe.
  v_estado := CASE WHEN v_es_paciente THEN 'solicitada' ELSE 'agendada' END;

  -- País de la cita DERIVADO del médico en el alta de PACIENTE (server-side; ignora
  -- p_pais_id del cliente — lección 8). Otras rutas conservan p_pais_id (sin cambio).
  IF v_es_paciente AND p_medico_id IS NOT NULL THEN
    SELECT pe.pais_id INTO v_pais FROM public.perfiles pe WHERE pe.id = p_medico_id;
  ELSE
    v_pais := p_pais_id;
  END IF;

  INSERT INTO public.citas (paciente_id, medico_id, clinica_id, fecha, hora_inicio, hora_fin, motivo, notas, estado, pais_id)
  VALUES (p_paciente_id, p_medico_id, p_clinica_id, p_fecha, p_hora_inicio, p_hora_fin, p_motivo, p_notas, v_estado, v_pais)
  RETURNING id INTO v_cita_id;
  RETURN v_cita_id;
END; $function$;

COMMIT;
