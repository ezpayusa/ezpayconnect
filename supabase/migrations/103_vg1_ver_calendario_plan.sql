-- ============================================================
-- V-G1 · Visitas: VER el calendario del médico gateado por plan activo + país (SEGURIDAD)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) → smoke al aplicar.
-- Probes red-first (P246–P252).
--
-- HALLAZGO (dual-use): "Proveedor ve disponibilidad activa" (activo=true, role public) servía
-- DOS flujos a la vez: el visitador (contexto='visitador') Y el AGENDAMIENTO DE PACIENTES
-- (contexto='paciente', AgendarCitaModal). Narrowing a 'visitador' rompería el agendamiento.
-- → SPLIT en dos SELECT policies, preservando el read de pacientes:
--   1) Visitador → contexto='visitador' SOLO si plan activo/vigente cubre el país del médico.
--   2) Paciente/agendamiento → contexto='paciente', excluyendo proveedores (el visitador NO ve
--      los slots de paciente). TO authenticated (⚠️ confirmar que no hay agendamiento ANON; si lo
--      hubiera, manejar anon aparte — el helper no es ejecutable por anon, lección 13).
--
-- OR-trap: para un visitador, de las 4 policies de disponibilidad_medico solo aplicaba la de
-- proveedor (médico own / admin_clinica / super_admin no matchean a un visitador). Las otras 3
-- NO se tocan.
-- ============================================================

-- Helper: ¿el visitador (su empresa) tiene un plan activo/vigente que cubra el país del médico?
CREATE OR REPLACE FUNCTION private.visitador_ve_medico(p_medico_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.planes_visitador_contratados pvc
    WHERE pvc.empresa_id = public.mi_empresa_proveedor()
      AND pvc.estado = 'activo'
      AND CURRENT_DATE BETWEEN pvc.fecha_inicio AND pvc.fecha_fin
      AND pvc.pais_id = (SELECT p.pais_id FROM public.perfiles p WHERE p.id = p_medico_id)
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.visitador_ve_medico(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.visitador_ve_medico(uuid) TO authenticated;

DROP POLICY IF EXISTS "Proveedor ve disponibilidad activa" ON public.disponibilidad_medico;

-- 1) Visitador: solo contexto='visitador' y con plan activo país-cubriente
CREATE POLICY "Visitador ve disponibilidad con plan" ON public.disponibilidad_medico
  FOR SELECT TO authenticated
  USING (
    activo = true
    AND contexto = 'visitador'
    AND private.visitador_ve_medico(medico_id)
  );

-- 2) Agendamiento de pacientes: contexto='paciente', NO proveedores (preserva el flujo actual)
CREATE POLICY "Disponibilidad paciente para agendar" ON public.disponibilidad_medico
  FOR SELECT TO authenticated
  USING (
    activo = true
    AND contexto = 'paciente'
    AND public.mi_empresa_proveedor() IS NULL   -- excluye visitadores (lección 12, DEFINER)
  );
