-- ============================================================
-- C.2 · Confinar staff operativo a SU sucursal en farmacia_medicamentos (least-privilege OPERATIVO)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA+ESCRITURA viva (nota 20). Probes red-first P309–P316.
--
-- MARCO (no es boundary): el confinamiento por sucursal es least-privilege OPERATIVO DENTRO de la
-- empresa, NO una frontera de aislamiento. La frontera sigue siendo `empresa` (mi_empresa_proveedor,
-- fail-closed, INTACTA). El término sucursal se ANDea ENCIMA y solo estrecha dentro de la empresa ya
-- aislada. Por eso es opt-in con NULL=GRANDFATHER (lección 33) — lo OPUESTO al fail-closed de país,
-- y ES ACEPTABLE SOLO porque sucursal NO es boundary: si mi_sucursal() IS NULL el staff ve toda su
-- empresa (sin regresión). NADIE debe tratar este término como boundary de seguridad.
--
-- Partición (confirmada Oscar): EXENTOS (ven/operan todas las sucursales de su empresa) =
-- {admin, gerente_farmacia, finanzas, pagador} (ARRAY explícito de rol_en_empresa — NO se usa
-- tiene_permiso('sucursales_gestionar') porque finanzas/pagador no lo tienen). CONFINABLES = el
-- resto (cajero, dependiente, delivery, inventario, supervisor).
--
-- Lectura+escritura: el término va en farm_med_propia_empresa (SELECT) y en farm_med_tenant_all
-- (ALL: USING + WITH CHECK) → un confinable no LEE ni ESCRIBE stock de otra sucursal.
-- OR-trap (lección 41): las otras permissive de farmacia_medicamentos no aplican a staff confinable
-- (editar_medicamentos=super_admin; disp_clinico=NOT cuentas_proveedor; disp_medico=rol médico) →
-- no queda camino que dé otra sucursal.
-- ============================================================

-- Helper: ¿la sucursal (farmacia_id) es visible para el caller? (exento OR grandfather OR su sucursal)
CREATE OR REPLACE FUNCTION private.sucursal_visible(p_farmacia_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT public.mi_rol_proveedor() = ANY (ARRAY['admin','gerente_farmacia','finanzas','pagador'])  -- EXENTOS
      OR private.mi_sucursal() IS NULL                 -- GRANDFATHER (lección 33, opt-in, NO boundary)
      OR p_farmacia_id = private.mi_sucursal();          -- CONFINADO a su sucursal
$function$;
REVOKE EXECUTE ON FUNCTION private.sucursal_visible(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.sucursal_visible(integer) TO authenticated;

-- SELECT: lectura confinada (empresa fail-closed intacta + término sucursal ANDeado)
DROP POLICY IF EXISTS farm_med_propia_empresa ON public.farmacia_medicamentos;
CREATE POLICY farm_med_propia_empresa ON public.farmacia_medicamentos
  FOR SELECT TO authenticated
  USING (
    (farmacia_id IN ( SELECT f.id FROM public.farmacias f
                      WHERE f.empresa_id IS NOT NULL AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false) ))
    AND COALESCE(private.sucursal_visible(farmacia_id), false)
  );

-- ALL: escritura/lectura de inventario confinada (USING + WITH CHECK con el término sucursal)
DROP POLICY IF EXISTS farm_med_tenant_all ON public.farmacia_medicamentos;
CREATE POLICY farm_med_tenant_all ON public.farmacia_medicamentos
  FOR ALL TO authenticated
  USING (
    COALESCE(private.tiene_permiso('inventario_editar'), false)
    AND (farmacia_id IN ( SELECT f.id FROM public.farmacias f
                          WHERE f.empresa_id IS NOT NULL AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false) ))
    AND COALESCE(private.sucursal_visible(farmacia_id), false)
  )
  WITH CHECK (
    COALESCE(private.tiene_permiso('inventario_editar'), false)
    AND (farmacia_id IN ( SELECT f.id FROM public.farmacias f
                          WHERE f.empresa_id IS NOT NULL AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false) ))
    AND COALESCE(private.sucursal_visible(farmacia_id), false)
  );
