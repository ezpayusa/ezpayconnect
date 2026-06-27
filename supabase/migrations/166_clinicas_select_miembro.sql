-- 166 · QA#0 fix — SELECT de public.clinicas por PERTENENCIA (no solo por país/dueño).
-- Hoy las 2 policies SELECT de clinicas son: doctor_id=auth.uid() (dueño) y "ve clinicas de su pais"
-- (perfiles.pais_id = clinicas.pais_id). Un staff de captura (asistente_medico/enfermeria) miembro de
-- su clínica vía medico_clinicas NO pasa ninguna → GET clinicas devuelve [] → useClinicaAuth no carga
-- (clinica null → Admisión no abre). Esta policy permite a cualquier MIEMBRO ver SU(S) clínica(s).
-- clinicas_del_usuario es SECURITY DEFINER (corre como owner) → NO recursa sobre clinicas. Mismo patrón
-- ya vivo y probado en citas_select_admin_clinica (clinica_id IN (SELECT private.clinicas_del_usuario())).
-- Aditiva: no toca las 2 policies existentes. Backout: DROP POLICY clinicas_select_miembro ON public.clinicas;
CREATE POLICY clinicas_select_miembro ON public.clinicas
  FOR SELECT TO authenticated
  USING (id IN (SELECT private.clinicas_del_usuario()));
