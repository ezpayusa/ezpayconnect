-- 160 · Ola 1 — CIMIENTO backend de signos vitales multi-rol (panel de admisión).
-- Habilita captura de vitales por staff clínico no-médico (asistente_medico, enfermería), con
-- pertenencia clínica (mig 159: private.clinicas_de) y auditoría de quién capturó/validó.
-- signos_vitales (mig 021) existe, está VACÍA (0 filas) y HOY sin caller. medico_id→perfiles(id),
-- paciente_id→pacientes(id). authz cuelga de private.rol_usuario()→private.tiene_rol() sobre
-- perfiles.rol (text, FK→roles_catalogo). 'secretaria' = capa administrativa: NO captura vitales.
--
-- Acompaña (NO en esta migración): ajuste de crear-staff-clinica para persistir el rol REAL
-- ('asistente'→'asistente_medico', 'secretaria'→'secretaria') en vez del 'gerente' hardcodeado.
-- ⚠️ Esta migración debe aplicarse ANTES de desplegar ese edge (perfiles.rol tiene FK→roles_catalogo;
--    insertar 'asistente_medico'/'secretaria' sin estas filas violaría la FK).

-- ============================================================
-- 1) Catálogo: 3 roles de staff clínico (idempotente, no toca roles existentes).
-- ============================================================
INSERT INTO public.roles_catalogo (codigo, descripcion, ambito, es_staff_clinica, es_super, orden, activo)
VALUES
  ('asistente_medico', 'Asistente médico (captura signos vitales)', 'clinica', true, false, 41, true),
  ('enfermeria',       'Enfermería (captura signos vitales)',       'clinica', true, false, 42, true),
  ('secretaria',       'Secretaría de clínica (administrativo)',    'clinica', true, false, 43, true)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================
-- 2) Columnas de captura/validación en signos_vitales (tabla vacía → sin backfill).
--    capturado_por NULLABLE: la policy de captura lo exige = auth.uid(); super_admin (FOR ALL) no.
--    cita_id (bigint, FK→citas): ata la captura de ADMISIÓN a la cita ANTES de que exista la consulta.
--    Decisión Oscar: signos_vitales = fuente ÚNICA de vitales (expediente_notas deja de duplicar, Ola 3).
--    consulta_id se MANTIENE: un registro podrá tener cita_id (admisión) y consulta_id (al crear la consulta).
-- ============================================================
ALTER TABLE public.signos_vitales
  ADD COLUMN IF NOT EXISTS capturado_por uuid,
  ADD COLUMN IF NOT EXISTS validado_por  uuid,
  ADD COLUMN IF NOT EXISTS estado        text NOT NULL DEFAULT 'capturado',
  ADD COLUMN IF NOT EXISTS validado_at   timestamptz,
  ADD COLUMN IF NOT EXISTS cita_id       bigint;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='signos_vitales_capturado_por_fkey') THEN
    ALTER TABLE public.signos_vitales
      ADD CONSTRAINT signos_vitales_capturado_por_fkey FOREIGN KEY (capturado_por) REFERENCES public.perfiles(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='signos_vitales_validado_por_fkey') THEN
    ALTER TABLE public.signos_vitales
      ADD CONSTRAINT signos_vitales_validado_por_fkey FOREIGN KEY (validado_por) REFERENCES public.perfiles(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='signos_vitales_estado_check') THEN
    ALTER TABLE public.signos_vitales
      ADD CONSTRAINT signos_vitales_estado_check CHECK (estado IN ('declarado','capturado','validado','corregido'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='signos_vitales_cita_id_fkey') THEN
    ALTER TABLE public.signos_vitales
      ADD CONSTRAINT signos_vitales_cita_id_fkey FOREIGN KEY (cita_id) REFERENCES public.citas(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_signos_vitales_cita ON public.signos_vitales (cita_id);

-- ============================================================
-- 3) Helper de pertenencia paciente↔clínica del actor (interno, sin gate propio).
--    Reusa private.clinicas_de (mig 159). Cubre clínica primaria del paciente Y vía cita.
-- ============================================================
CREATE OR REPLACE FUNCTION private.paciente_en_clinica_de(p_paciente_id integer)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.pacientes pa
    WHERE pa.id = p_paciente_id
      AND pa.clinica_primaria_id IN (SELECT private.clinicas_de(auth.uid()))
  )
  OR EXISTS (
    SELECT 1 FROM public.citas c
    WHERE c.paciente_id = p_paciente_id
      AND c.clinica_id IN (SELECT private.clinicas_de(auth.uid()))
  );
$function$;
REVOKE ALL ON FUNCTION private.paciente_en_clinica_de(integer) FROM PUBLIC;

-- ============================================================
-- 4) RLS signos_vitales.
--    SOLO se reescribe la policy de INSERT (sv_insert_medico, mig 070, médico-only). Las de SELECT
--    y la de super_admin se MANTIENEN intactas (no se reduce visibilidad). Se agrega UPDATE (Ola 3).
-- ============================================================

-- 4a) INSERT — captura multi-rol fail-closed. 'secretaria' NO está en la lista → no captura vitales.
DROP POLICY IF EXISTS sv_insert_medico ON public.signos_vitales;
CREATE POLICY sv_insert_captura ON public.signos_vitales
  FOR INSERT TO authenticated
  WITH CHECK (
        private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria'])
    AND capturado_por = auth.uid()
    AND private.paciente_en_clinica_de(paciente_id)
  );

-- 4b) UPDATE — validación por el médico de la clínica del paciente.
--     OLA 3 (NO esta ola): acotar a transición estado capturado→validado/corregido y forzar
--     validado_por = auth.uid() + validado_at = now() en WITH CHECK. Por ahora gate de pertenencia+rol médico.
CREATE POLICY sv_update_valida_medico ON public.signos_vitales
  FOR UPDATE TO authenticated
  USING (
        private.tiene_rol(ARRAY['medico'])
    AND private.paciente_en_clinica_de(paciente_id)
  )
  WITH CHECK (
        private.tiene_rol(ARRAY['medico'])
    AND private.paciente_en_clinica_de(paciente_id)
  );

-- SELECT (sv_select_medico, "Admin clinica ve...", "Admin ve todo...") y sv_superadmin_all: SIN cambios.

-- ============================================================
-- 5) Separar "gestión de citas" de "lectura de PHI".
--    Al persistir el rol real, secretaria/asistente_medico/enfermeria salen de es_admin_clinica
--    (= tiene_rol(['admin_clinica','gerente'])) y perderían la gestión de citas (mig 071).
--    Decisión Oscar: secretaria SÍ gestiona citas, pero NO lee PHI clínico (mig 108 intacto).
--    Camino de MENOR SUPERFICIE: un único predicado nombrado para "gestión de citas" (suma
--    'secretaria') al que se reapuntan SOLO las 2 policies de citas; centraliza el privilegio
--    en un lugar (no duplica 'secretaria' en 2 policies) y deja es_admin_clinica/PHI sin tocar.
--    ⚠️ 'secretaria' NO entra en es_admin_clinica ni en medico_es_de_mi_clinica → no toca PHI.
-- ============================================================
CREATE OR REPLACE FUNCTION private.puede_gestionar_citas(p_clinica uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT private.tiene_rol(ARRAY['admin_clinica','gerente','secretaria'])
     AND p_clinica IN (SELECT private.clinicas_del_usuario());
$function$;
REVOKE ALL ON FUNCTION private.puede_gestionar_citas(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.puede_gestionar_citas(uuid) TO authenticated;

-- Reapuntar SOLO las 2 policies de gestión de citas (mig 071). Idéntica salvo +secretaria.
DROP POLICY IF EXISTS citas_select_admin_clinica ON public.citas;
CREATE POLICY citas_select_admin_clinica ON public.citas
  FOR SELECT TO authenticated
  USING ( private.puede_gestionar_citas(clinica_id) );

DROP POLICY IF EXISTS citas_update_admin_clinica ON public.citas;
CREATE POLICY citas_update_admin_clinica ON public.citas
  FOR UPDATE TO authenticated
  USING ( private.puede_gestionar_citas(clinica_id) )
  WITH CHECK ( private.puede_gestionar_citas(clinica_id) );

-- PHI (pacientes/expediente_notas/recetas/signos_vitales) y es_admin_clinica/medico_es_de_mi_clinica:
-- SIN CAMBIOS. secretaria queda fuera de toda lectura de PHI clínico.
