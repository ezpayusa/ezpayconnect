-- ============================================================
-- Deuda (c) · Aislamiento por país en el agendamiento paciente↔médico (SEGURIDAD)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) + write gate. Probes
-- red-first P263–P266.
--
-- HALLAZGO (recon): el paciente podía (1) VER disponibilidad de médicos de OTRO país
-- (policy "Disponibilidad paciente para agendar" sin término país) y (2) AGENDAR con
-- un médico de otro país vía crear_cita caso (a) ("el médico elegido es libre"); además
-- crear_cita estampaba pais_id del CLIENTE (p_pais_id) — lección 8. citas no tiene policy
-- INSERT de paciente: TODO el alta pasa por crear_cita → el gate país va ahí (lección 7).
--
-- Patrón: país del médico derivado server-side (nota 12 → helper DEFINER). País del
-- VIEWER = mi_pais_viewer() (= pacientes.pais_id para el paciente). Fail-closed, sin
-- grandfather (país = borde de tenant duro). Impacto país-NULL hoy = cero (pacientes 0
-- NULL, médicos 0 NULL, 1 país); cierra el leak para país #2+.
--
-- ALCANCE acotado al flujo de PACIENTE: las rutas médico-self / admin_clinica /
-- super_admin de crear_cita quedan SIN cambio (ya tenant-scoped por self/clínica).
-- ============================================================

-- 1) Helper: ¿el médico está en el país del viewer (paciente)?  DEFINER, fail-closed.
CREATE OR REPLACE FUNCTION private.medico_en_mi_pais_viewer(p_medico_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = p_medico_id
      AND p.pais_id IS NOT NULL
      AND p.pais_id = private.mi_pais_viewer()
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.medico_en_mi_pais_viewer(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.medico_en_mi_pais_viewer(uuid) TO authenticated;

-- 2) SELECT policy: añadir término país (conjuntivo — solo restringe; las otras 4 intactas)
DROP POLICY IF EXISTS "Disponibilidad paciente para agendar" ON public.disponibilidad_medico;
CREATE POLICY "Disponibilidad paciente para agendar" ON public.disponibilidad_medico
  FOR SELECT TO authenticated
  USING (
    activo = true
    AND contexto = 'paciente'
    AND public.mi_empresa_proveedor() IS NULL                       -- excluye visitadores
    AND COALESCE(private.medico_en_mi_pais_viewer(medico_id), false) -- médico del país del paciente
  );

-- 3) Write gate crear_cita: caso (a) paciente solo con médico de su país + país derivado.
--    Firma idéntica. Único cambio: término país en (a) + derivación de v_pais (paciente).
CREATE OR REPLACE FUNCTION public.crear_cita(
  p_paciente_id bigint,
  p_medico_id   uuid DEFAULT NULL::uuid,
  p_clinica_id  uuid DEFAULT NULL::uuid,
  p_fecha       date DEFAULT NULL::date,
  p_hora_inicio time without time zone DEFAULT NULL::time without time zone,
  p_hora_fin    time without time zone DEFAULT NULL::time without time zone,
  p_motivo      text DEFAULT NULL::text,
  p_notas       text DEFAULT NULL::text,
  p_estado      text DEFAULT 'agendada'::text,
  p_pais_id     uuid DEFAULT NULL::uuid)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
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
       -- (c) admin de la clínica: para SU clínica, con un médico de esa clínica (o sin médico aún)
       OR ( p_clinica_id IS NOT NULL AND private.es_admin_clinica(p_clinica_id)
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
