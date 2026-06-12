-- ============================================================
-- FASE 2 · Bloque B — RLS de PHI clínico (modelo POR CITA)
-- ------------------------------------------------------------
-- Decisión de modelo (confirmada):
--   * LECTURA (SELECT): cabecera (es_medico_de = pacientes.medico_id) O por cita
--     (medico_atiende_paciente) O autor (medico_id = auth.uid()). Así el médico
--     de cabecera nunca pierde lectura y el que atiende por cita la gana.
--   * ESCRITURA (INSERT): solo por cita (medico_id = auth.uid() AND
--     medico_atiende_paciente). Para escribir se exige una cita activa.
-- Motivo: 39/45 citas son cruzadas; el modelo solo-cabecera dejaba "paciente
-- fantasma" y solo-cita le quitaba lectura al médico de cabecera sin cita.
--
-- Helper nuevo: private.medico_atiende_paciente(bigint|text).
-- Tipos: historial_medico/recetas_avanzadas/dispensaciones → paciente_id TEXT;
-- expediente_notas/signos_vitales/citas.paciente_id/pacientes.id → INTEGER/BIGINT.
-- ============================================================

-- ---------- Helper Fase 2: ¿el médico atiende a este paciente (por cita)? ----------
CREATE OR REPLACE FUNCTION private.medico_atiende_paciente(p_paciente BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.citas
    WHERE medico_id = auth.uid() AND paciente_id = p_paciente
  );
$$;

CREATE OR REPLACE FUNCTION private.medico_atiende_paciente(p_paciente TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_paciente ~ '^[0-9]+$'
     AND EXISTS (
       SELECT 1 FROM public.citas
       WHERE medico_id = auth.uid() AND paciente_id = p_paciente::bigint
     );
$$;

REVOKE EXECUTE ON FUNCTION private.medico_atiende_paciente(BIGINT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.medico_atiende_paciente(TEXT)   FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION private.medico_atiende_paciente(BIGINT) TO authenticated;
GRANT  EXECUTE ON FUNCTION private.medico_atiende_paciente(TEXT)   TO authenticated;

-- ---------- pacientes: lectura POR CITA (arregla el "paciente fantasma") ----------
-- Aditiva: las políticas existentes (cabecera / paciente dueño / admin país) se mantienen.
DROP POLICY IF EXISTS pacientes_select_medico_cita ON pacientes;
CREATE POLICY pacientes_select_medico_cita ON pacientes
  FOR SELECT TO authenticated
  USING ( private.medico_atiende_paciente(id) );

-- ============================================================
-- historial_medico  (paciente_id / medico_id TEXT)
-- ============================================================
DROP POLICY IF EXISTS "ver_historial" ON historial_medico;
DROP POLICY IF EXISTS "crear_historial" ON historial_medico;
DROP POLICY IF EXISTS "Allow anon insert historial_medico" ON historial_medico;
DROP POLICY IF EXISTS "Allow authenticated insert historial_medico" ON historial_medico;

CREATE POLICY historial_select_medico ON historial_medico
  FOR SELECT TO authenticated
  USING ( private.es_medico_de(paciente_id) OR private.medico_atiende_paciente(paciente_id) OR medico_id = auth.uid()::text );

CREATE POLICY historial_select_paciente ON historial_medico
  FOR SELECT TO authenticated
  USING ( private.paciente_es_mio(paciente_id) );

CREATE POLICY historial_insert_medico ON historial_medico
  FOR INSERT TO authenticated
  WITH CHECK ( medico_id = auth.uid()::text AND private.medico_atiende_paciente(paciente_id) );

CREATE POLICY historial_superadmin_all ON historial_medico
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- recetas_avanzadas  (paciente_id / medico_id TEXT)
-- ============================================================
DROP POLICY IF EXISTS "ver_recetas_adv" ON recetas_avanzadas;
DROP POLICY IF EXISTS "crear_recetas_adv" ON recetas_avanzadas;

CREATE POLICY recadv_select_medico ON recetas_avanzadas
  FOR SELECT TO authenticated
  USING ( medico_id = auth.uid()::text OR private.es_medico_de(paciente_id) OR private.medico_atiende_paciente(paciente_id) );

CREATE POLICY recadv_select_paciente ON recetas_avanzadas
  FOR SELECT TO authenticated
  USING ( private.paciente_es_mio(paciente_id) );

CREATE POLICY recadv_insert_medico ON recetas_avanzadas
  FOR INSERT TO authenticated
  WITH CHECK ( medico_id = auth.uid()::text AND private.medico_atiende_paciente(paciente_id) );

CREATE POLICY recadv_superadmin_all ON recetas_avanzadas
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- receta_items  (scoping por la receta PADRE = autor médico)
-- (se mantiene "Paciente ve items de sus recetas")
-- ============================================================
DROP POLICY IF EXISTS "receta_items_select" ON receta_items;
DROP POLICY IF EXISTS "receta_items_insert" ON receta_items;
DROP POLICY IF EXISTS "receta_items_update" ON receta_items;
DROP POLICY IF EXISTS "receta_items_delete" ON receta_items;

CREATE POLICY receta_items_medico_all ON receta_items
  FOR ALL TO authenticated
  USING ( receta_id IN (SELECT r.id FROM public.recetas r WHERE r.medico_id = auth.uid()) )
  WITH CHECK ( receta_id IN (SELECT r.id FROM public.recetas r WHERE r.medico_id = auth.uid()) );

CREATE POLICY receta_items_superadmin_all ON receta_items
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- dispensaciones  (paciente_id / medico_id TEXT)
-- INSERT real por edge function registrar-dispensacion (service_role).
-- ============================================================
DROP POLICY IF EXISTS "ver_dispensaciones" ON dispensaciones;
DROP POLICY IF EXISTS "crear_dispensaciones" ON dispensaciones;

CREATE POLICY disp_select_medico ON dispensaciones
  FOR SELECT TO authenticated
  USING ( private.es_medico_de(paciente_id) OR private.medico_atiende_paciente(paciente_id) OR medico_id = auth.uid()::text );

CREATE POLICY disp_select_paciente ON dispensaciones
  FOR SELECT TO authenticated
  USING ( private.paciente_es_mio(paciente_id) );

CREATE POLICY disp_superadmin_all ON dispensaciones
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- expediente_notas  (REPARAR deny-all; paciente_id INTEGER, medico_id UUID)
-- ============================================================
CREATE POLICY exp_select_medico ON expediente_notas
  FOR SELECT TO authenticated
  USING ( medico_id = auth.uid() OR private.es_medico_de(paciente_id::bigint) OR private.medico_atiende_paciente(paciente_id::bigint) );

CREATE POLICY exp_select_paciente ON expediente_notas
  FOR SELECT TO authenticated
  USING ( private.paciente_es_mio(paciente_id::bigint) );

CREATE POLICY exp_insert_medico ON expediente_notas
  FOR INSERT TO authenticated
  WITH CHECK ( medico_id = auth.uid() AND private.medico_atiende_paciente(paciente_id::bigint) );

CREATE POLICY exp_update_medico ON expediente_notas
  FOR UPDATE TO authenticated
  USING ( medico_id = auth.uid() )
  WITH CHECK ( medico_id = auth.uid() );

CREATE POLICY exp_superadmin_all ON expediente_notas
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- signos_vitales  (SELECT médico pasa a POR CITA; se añade INSERT)
-- paciente_id INTEGER, medico_id UUID
-- ============================================================
DROP POLICY IF EXISTS "Medico ve signos vitales de sus pacientes" ON signos_vitales;
CREATE POLICY sv_select_medico ON signos_vitales
  FOR SELECT TO authenticated
  USING ( medico_id = auth.uid() OR private.es_medico_de(paciente_id::bigint) OR private.medico_atiende_paciente(paciente_id::bigint) );

CREATE POLICY sv_insert_medico ON signos_vitales
  FOR INSERT TO authenticated
  WITH CHECK ( medico_id = auth.uid() AND private.medico_atiende_paciente(paciente_id::bigint) );

CREATE POLICY sv_superadmin_all ON signos_vitales
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );
-- (se mantiene "Admin ve todo signos vitales" para super_admin)

-- ============================================================
-- examenes  (rama super_admin faltante; el resto se mantiene)
-- ============================================================
CREATE POLICY examenes_superadmin_all ON examenes
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );
