-- ============================================================
-- PUB-B · Publicidad: display por país del VIEWER (paciente+clínica+médico) + vigencia
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) → smoke al aplicar.
-- Probes red-first (P229–P236).
--
-- Hoy "Paciente ve campanas activas" (TO public) cuelga de pacientes.pais_id → SOLO pacientes
-- ven ads (médicos/clínicas → 0, no están en pacientes; anon → 0, subquery vacío). Audiencia #2:
-- paciente + clínica (admin_clinica) + médico, todos país-scoped por su país.
--
-- D1: helper dedicado mi_pais_viewer() (NO se toca mi_pais() ni el catálogo aislado). Cubre:
--   · médico/clínica/proveedor → private.mi_pais() (perfiles.pais_id / cuenta / empresa)
--   · paciente → pacientes.pais_id (los pacientes NO están en perfiles → mi_pais()=NULL).
-- fail-closed: sin país → NULL → 0 ads.
-- Anon: la policy pasa a TO authenticated (anon ya veía 0 hoy; evita 42501 al evaluar el helper
-- sin EXECUTE, lección 13). Ningún lector anon legítimo (banners en superficies autenticadas).
-- Vigencia: se añade fecha_inicio <= CURRENT_DATE (bug fail-open: hoy una campaña con inicio
-- futuro ya se muestra).
-- "Admin ve campanas de su pais" (super_admin ALL) intacta.
-- ============================================================

CREATE OR REPLACE FUNCTION private.mi_pais_viewer()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT COALESCE(
    private.mi_pais(),
    (SELECT pa.pais_id FROM public.pacientes pa WHERE pa.auth_user_id = auth.uid() LIMIT 1)
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.mi_pais_viewer() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.mi_pais_viewer() TO authenticated;

DROP POLICY IF EXISTS "Paciente ve campanas activas" ON public.campanas_publicitarias;
CREATE POLICY "Viewer ve campanas activas por pais" ON public.campanas_publicitarias
  FOR SELECT TO authenticated
  USING (
    activa = true
    AND fecha_inicio <= CURRENT_DATE       -- NUEVO: cierra el fail-open de vigencia
    AND fecha_fin   >= CURRENT_DATE
    AND pais_id = private.mi_pais_viewer()  -- por país del viewer (paciente/clínica/médico)
  );
