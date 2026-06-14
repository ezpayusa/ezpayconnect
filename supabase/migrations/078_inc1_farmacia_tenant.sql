-- ============================================================
-- INCREMENTO 1 (paneles) — Farmacias como TENANT (convivencia con el catálogo)
-- ------------------------------------------------------------
-- Rama: paneles/farmacia-tenant (NO va con el deploy de seguridad; es feature).
-- Aditivo y reversible. NO migra las farmacias-catálogo existentes.
--
-- Modelo de convivencia:
--   farmacias.empresa_id NULL  → CATÁLOGO (como hoy; lo gestiona super_admin).
--   farmacias.empresa_id set   → TENANT  (lo gestionan los miembros de SU empresa).
-- La lectura pública del catálogo (búsqueda de disponibilidad del médico) se
-- MANTIENE intacta: no se toca ninguna política SELECT existente.
--
-- Promoción CONTROLADA por super_admin (no autoactivación → evita que alguien
-- se apropie de una farmacia ajena): RPC SECURITY DEFINER que liga farmacia↔empresa.
-- ============================================================

-- 1) Vínculo tenant: columna aditiva NULLABLE + FK a la empresa proveedora
ALTER TABLE public.farmacias
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas_proveedoras(id);
-- (existentes quedan empresa_id NULL = catálogo, sin migración de datos)

-- 2) RLS — ESCRITURA del tenant (la lectura pública NO se toca)
--    farmacias: el dueño (miembro de la empresa) actualiza SU fila de farmacia.
--    super_admin sigue gestionando todo vía "farmacias_write_admin" (sin cambios).
DROP POLICY IF EXISTS "farmacias_tenant_update" ON public.farmacias;
CREATE POLICY "farmacias_tenant_update" ON public.farmacias
  FOR UPDATE TO authenticated
  USING      (COALESCE(empresa_id = public.mi_empresa_proveedor(), false))
  WITH CHECK (COALESCE(empresa_id = public.mi_empresa_proveedor(), false));

--    farmacia_medicamentos (inventario): el dueño gestiona el inventario de SUS
--    farmacias-tenant. Catálogo (empresa_id NULL) sigue solo super_admin
--    ("editar_medicamentos", sin cambios). Lectura pública intacta.
DROP POLICY IF EXISTS "farm_med_tenant_all" ON public.farmacia_medicamentos;
CREATE POLICY "farm_med_tenant_all" ON public.farmacia_medicamentos
  FOR ALL TO authenticated
  USING (
    farmacia_id IN (SELECT f.id FROM public.farmacias f
                    WHERE f.empresa_id IS NOT NULL
                      AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false))
  )
  WITH CHECK (
    farmacia_id IN (SELECT f.id FROM public.farmacias f
                    WHERE f.empresa_id IS NOT NULL
                      AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false))
  );

-- 3) Promoción a tenant — solo super_admin (revalida + COALESCE)
CREATE OR REPLACE FUNCTION public.promover_farmacia_a_tenant(
  p_farmacia_id integer, p_empresa_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_tipo text;
  v_actual uuid;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin promueve una farmacia a tenant';
  END IF;

  SELECT tipo INTO v_tipo FROM public.empresas_proveedoras WHERE id = p_empresa_id;
  IF v_tipo IS NULL THEN RAISE EXCEPTION 'Empresa no encontrada'; END IF;
  IF v_tipo <> 'farmacia' THEN
    RAISE EXCEPTION 'La empresa destino debe ser tipo farmacia (es %)', v_tipo;
  END IF;

  SELECT empresa_id INTO v_actual FROM public.farmacias WHERE id = p_farmacia_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Farmacia no encontrada'; END IF;
  IF v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'La farmacia ya es tenant (empresa %)', v_actual;  -- no re-apropiación
  END IF;

  UPDATE public.farmacias SET empresa_id = p_empresa_id WHERE id = p_farmacia_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.promover_farmacia_a_tenant(integer,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.promover_farmacia_a_tenant(integer,uuid) TO authenticated, service_role;
