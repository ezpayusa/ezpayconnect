-- ============================================================
-- INCREMENTO 5 (Frente A) · Catálogo de farmacia — Parte 1: columna + guards + LECTURA
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — NO aplicar sin OK.
-- Orden de aplicación: 086 (esta) → MERGE (scripts/086_merge_colisiones, usa la
-- COLUMNA generada) → 087 (UNIQUE + RPC). El UNIQUE va en 087 (post-merge) para no
-- fallar con las colisiones de seed.
-- Decisiones (Oscar): product-level (farmacia_id, nombre_normalizado); acentos
-- eliminados; lectura endurecida (B).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Columna normalizada STORED (ÚNICA fuente de la normalización) + guards.
--    translate(acentos) → colapsa espacios → btrim (AL FINAL) → upper.
--    El MERGE y el UNIQUE usan ESTA columna (no una expresión inline) → imposible
--    que diverjan.
-- ------------------------------------------------------------
ALTER TABLE public.farmacia_medicamentos
  ALTER COLUMN nombre_medicamento SET NOT NULL;   -- ya lo es; explícito/defensivo

ALTER TABLE public.farmacia_medicamentos
  ADD COLUMN IF NOT EXISTS nombre_normalizado text
  GENERATED ALWAYS AS (
    upper(btrim(regexp_replace(
      translate(nombre_medicamento, 'áéíóúüÁÉÍÓÚÜñÑ', 'aeiouuAEIOUUnN'),
      '\s+', ' ', 'g')))
  ) STORED;

ALTER TABLE public.farmacia_medicamentos
  ADD CONSTRAINT farmacia_medicamentos_nombrenorm_no_vacio CHECK (nombre_normalizado <> '');

-- ------------------------------------------------------------
-- 2) LECTURA endurecida (B): proveedor/farmacia → solo su empresa; lado clínico
--    (médico/enfermera/asistente/super_admin) + paciente NO-proveedor → disponibilidad.
--    Se QUITAN las policies abiertas USING(true) (anon + authenticated).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Allow anon read farmacia_medicamentos" ON public.farmacia_medicamentos;
DROP POLICY IF EXISTS "Allow authenticated read farmacia_medicamentos" ON public.farmacia_medicamentos;

-- (a) Médico/super_admin (perfil): disponibilidad. Garantiza P70 aunque el médico
--     tuviera además una cuenta de proveedor. (Reemplaza ver_medicamentos, mismo efecto.)
DROP POLICY IF EXISTS "ver_medicamentos" ON public.farmacia_medicamentos;
CREATE POLICY "farm_med_disp_medico" ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico','super_admin'])));

-- (b) Lado clínico/paciente NO-proveedor: disponibilidad de productos ACTIVOS.
--     Cubre enfermera/asistente/gerente_clinica/paciente (authenticated, no cuenta de proveedor).
CREATE POLICY "farm_med_disp_clinico" ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (
    COALESCE(activo, true) = true
    AND NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor cp WHERE cp.id = auth.uid())
  );

-- (c) Cuenta de proveedor/farmacia: SOLO el catálogo de SU empresa (no ajeno).
CREATE POLICY "farm_med_propia_empresa" ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (
    farmacia_id IN (SELECT f.id FROM public.farmacias f
                    WHERE f.empresa_id IS NOT NULL
                      AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false))
  );
-- (anon: SIN policy de lectura → 0 filas. Confirmado: ningún front lee como anon.)
-- (Escritura intacta: farm_med_tenant_all [inventario_editar + empresa] + editar_medicamentos [super_admin].)
