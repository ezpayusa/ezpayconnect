-- ============================================================
-- PAÍS #2 · farmacia_medicamentos — aislar la vista médico/clínico por país (SEGURIDAD)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) → smoke al aplicar.
-- Probes red-first (P204–P209). Cubre farmacia Y lab farmacéutico (misma tabla).
-- Término país CONJUNTIVO vía helper DEFINER private.farmacia_en_mi_pais (país-0): la tabla
-- no tiene pais_id → se deriva de farmacias.pais_id; DEFINER evita la RLS del caller (nota 12).
-- fail-closed: mi_pais() NULL → false.
--
-- SOLO se tocan las 2 policies de lectura médico/clínico. NO se tocan:
--   · farm_med_propia_empresa (proveedor → su empresa; queda empresa-scoped, NUNCA país)
--   · farm_med_tenant_all / editar_medicamentos (write/ALL)
--   · nada no-proveedor adicional.
-- super_admin: sigue viéndolo todo vía editar_medicamentos (ALL) — el término país en
--   disp_medico no lo afecta (esa rama queda país-scoped, pero la ALL lo cubre).
-- ============================================================

-- Lado MÉDICO (rol medico/super_admin)
DROP POLICY IF EXISTS "farm_med_disp_medico" ON public.farmacia_medicamentos;
CREATE POLICY "farm_med_disp_medico" ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.perfiles p
            WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico','super_admin']))
    AND private.farmacia_en_mi_pais(farmacia_id)
  );

-- Lado CLÍNICO no-médico (enfermera/asistente: authenticated, NO proveedor, activo)
DROP POLICY IF EXISTS "farm_med_disp_clinico" ON public.farmacia_medicamentos;
CREATE POLICY "farm_med_disp_clinico" ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (
    COALESCE(activo, true) = true
    AND NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor cp WHERE cp.id = auth.uid())
    AND private.farmacia_en_mi_pais(farmacia_id)
  );
