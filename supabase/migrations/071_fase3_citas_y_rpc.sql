-- ============================================================
-- FASE 3 · Bloque A — RLS de citas + endurecer RPC + fix triggers historial
-- ============================================================

-- ------------------------------------------------------------
-- 0. (Cabo de Fase 2) Triggers de historial → SECURITY DEFINER
--    Eran SECURITY INVOKER e insertaban en historial_medico con NEW.medico_id;
--    con la nueva RLS de historial, un NO-médico creando cita/receta fallaría.
--    Como audit-log interno, deben bypassar RLS (owner postgres = bypassrls).
--    search_path='' + relación calificada (estándar Fase 0).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insertar_historial_cita()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.historial_medico (paciente_id, tipo_evento, titulo, descripcion, medico_id, fecha_evento, referencia_id, metadata)
  VALUES (NEW.paciente_id, 'cita', 'Cita programada', COALESCE(NEW.motivo, 'Sin motivo especificado'),
          NEW.medico_id, NOW(), NEW.id::TEXT,
          jsonb_build_object('estado', NEW.estado, 'hora_inicio', NEW.hora_inicio, 'hora_fin', NEW.hora_fin));
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.insertar_historial_receta()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.historial_medico (paciente_id, tipo_evento, titulo, descripcion, medico_id, fecha_evento, referencia_id, metadata)
  VALUES (NEW.paciente_id, 'receta', 'Receta emitida', COALESCE(NEW.diagnostico, 'Receta medica emitida'),
          NEW.medico_id, NOW(), NEW.id::TEXT,
          jsonb_build_object('estado', NEW.estado, 'medicamentos', NEW.medicamentos));
  RETURN NEW;
END; $$;

-- ------------------------------------------------------------
-- 1. RLS de citas — quitar lo abierto, scopear por audiencia
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "citas_select_all" ON citas;
DROP POLICY IF EXISTS "Allow anon insert citas" ON citas;
DROP POLICY IF EXISTS "Allow authenticated insert citas" ON citas;
-- INSERT directo: el frontend ya NO inserta en citas directamente (todo vía la
-- RPC crear_cita, SECURITY DEFINER que revalida). Se cierran las políticas de
-- INSERT por-cliente para dejar un ÚNICO punto de entrada validado.
DROP POLICY IF EXISTS "citas_insert" ON citas;            -- (médico WITH CHECK auth.uid()=medico_id)
DROP POLICY IF EXISTS "Paciente crea sus citas" ON citas; -- (paciente WITH CHECK paciente propio)
-- Se mantienen: "Admin ve citas de su pais" (ALL, super_admin), "Paciente ve sus citas" (SELECT).

-- SELECT del médico que atiende
CREATE POLICY citas_select_medico ON citas
  FOR SELECT TO authenticated
  USING ( medico_id = auth.uid() );

-- SELECT del staff de la clínica (admin_clinica / gerente), por su clínica
CREATE POLICY citas_select_admin_clinica ON citas
  FOR SELECT TO authenticated
  USING ( private.tiene_rol(ARRAY['admin_clinica','gerente'])
          AND clinica_id IN (SELECT private.clinicas_del_usuario()) );

-- UPDATE del médico sobre SU cita (estado: confirmar / en sala / completar)
CREATE POLICY citas_update_medico ON citas
  FOR UPDATE TO authenticated
  USING ( medico_id = auth.uid() ) WITH CHECK ( medico_id = auth.uid() );

-- UPDATE del staff de la clínica
CREATE POLICY citas_update_admin_clinica ON citas
  FOR UPDATE TO authenticated
  USING ( private.tiene_rol(ARRAY['admin_clinica','gerente']) AND clinica_id IN (SELECT private.clinicas_del_usuario()) )
  WITH CHECK ( private.tiene_rol(ARRAY['admin_clinica','gerente']) AND clinica_id IN (SELECT private.clinicas_del_usuario()) );

-- ------------------------------------------------------------
-- 2. Endurecer las RPC SECURITY DEFINER (revalidan al caller) + integer→bigint
-- ------------------------------------------------------------

-- 2.1 actualizar_estado_cita
DROP FUNCTION IF EXISTS public.actualizar_estado_cita(integer, text);
CREATE OR REPLACE FUNCTION public.actualizar_estado_cita(p_cita_id bigint, p_estado text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v public.citas%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada'; END IF;
  -- citas.estado es TEXT: validar contra el conjunto permitido antes de escribir.
  IF p_estado NOT IN ('solicitada','agendada','confirmada','en_curso','completada','cancelada','no_show') THEN
    RAISE EXCEPTION 'Estado de cita inválido: %', p_estado;
  END IF;
  IF NOT (
       v.medico_id = auth.uid()
       OR EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = v.paciente_id AND p.auth_user_id = auth.uid())
       OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
       OR private.tiene_rol(ARRAY['super_admin'])
  ) THEN
    RAISE EXCEPTION 'No autorizado para modificar esta cita';
  END IF;
  UPDATE public.citas SET estado = p_estado WHERE id = p_cita_id;
END; $$;
REVOKE EXECUTE ON FUNCTION public.actualizar_estado_cita(bigint, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.actualizar_estado_cita(bigint, text) TO authenticated;

-- 2.2 asignar_medico_cita — solo admin de la clínica de la cita o super_admin
DROP FUNCTION IF EXISTS public.asignar_medico_cita(integer, uuid);
CREATE OR REPLACE FUNCTION public.asignar_medico_cita(p_cita_id bigint, p_medico_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v public.citas%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada'; END IF;
  -- Caller: admin de la clínica de la cita o super_admin
  IF NOT (
       (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
       OR private.tiene_rol(ARRAY['super_admin'])
  ) THEN
    RAISE EXCEPTION 'No autorizado para asignar médico a esta cita';
  END IF;
  -- Coherencia: el médico asignado debe pertenecer a la clínica de la cita
  IF v.clinica_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.medico_clinicas mc
                    WHERE mc.medico_id = p_medico_id AND mc.clinica_id = v.clinica_id) THEN
    RAISE EXCEPTION 'El médico no pertenece a la clínica de la cita';
  END IF;
  UPDATE public.citas SET medico_id = p_medico_id, estado = 'agendada' WHERE id = p_cita_id;
END; $$;
REVOKE EXECUTE ON FUNCTION public.asignar_medico_cita(bigint, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.asignar_medico_cita(bigint, uuid) TO authenticated;

-- 2.3 crear_cita — paciente dueño / médico / admin de la clínica / super_admin
DROP FUNCTION IF EXISTS public.crear_cita(integer, uuid, uuid, date, time without time zone, time without time zone, text, text, text, uuid);
CREATE OR REPLACE FUNCTION public.crear_cita(
  p_paciente_id bigint,
  p_medico_id   uuid DEFAULT NULL,
  p_clinica_id  uuid DEFAULT NULL,
  p_fecha       date DEFAULT NULL,
  p_hora_inicio time without time zone DEFAULT NULL,
  p_hora_fin    time without time zone DEFAULT NULL,
  p_motivo      text DEFAULT NULL,
  p_notas       text DEFAULT NULL,
  p_estado      text DEFAULT 'agendada',
  p_pais_id     uuid DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_cita_id     BIGINT;
  v_es_paciente BOOLEAN;
  v_estado      TEXT;
BEGIN
  v_es_paciente := EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = p_paciente_id AND p.auth_user_id = auth.uid());

  -- Autorización + COHERENCIA paciente/médico con el caller:
  IF NOT (
       -- (a) un paciente crea SU propia cita (no con otro paciente_id); el médico elegido es libre
       v_es_paciente
       -- (b) un médico se pone a SÍ MISMO y solo para un paciente que YA atiende (cabecera o cita previa)
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
    RAISE EXCEPTION 'No autorizado para crear esta cita (paciente/médico incoherentes con el usuario)';
  END IF;

  -- Estado inicial FORZADO por rol (se ignora p_estado del caller): el paciente NO
  -- puede auto-agendar/confirmar; queda en 'solicitada' hasta que la clínica apruebe.
  -- (citas.estado es TEXT; ambos valores forzados son válidos del set de estados.)
  v_estado := CASE WHEN v_es_paciente THEN 'solicitada' ELSE 'agendada' END;

  INSERT INTO public.citas (paciente_id, medico_id, clinica_id, fecha, hora_inicio, hora_fin, motivo, notas, estado, pais_id)
  VALUES (p_paciente_id, p_medico_id, p_clinica_id, p_fecha, p_hora_inicio, p_hora_fin, p_motivo, p_notas, v_estado, p_pais_id)
  RETURNING id INTO v_cita_id;
  RETURN v_cita_id;
END; $$;
REVOKE EXECUTE ON FUNCTION public.crear_cita(bigint,uuid,uuid,date,time without time zone,time without time zone,text,text,text,uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.crear_cita(bigint,uuid,uuid,date,time without time zone,time without time zone,text,text,text,uuid) TO authenticated;
