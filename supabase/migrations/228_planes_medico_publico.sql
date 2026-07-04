-- ============================================================================
-- Migración 228 (FIX 1 de /planes): abrir planes tipo='medico' a la lectura pública (anon).
-- ============================================================================
-- La exclusión de 'medico' en las 2 policies públicas de la mig 013 (planes_base + planes_configuracion)
-- fue ALCANCE INCOMPLETO — esa migración se enfocó en el portal proveedor (visitador/publicidad/farmacia)
-- y 'medico' quedó afuera sin razón documentada, NO por seguridad. Los datos de planes_base tipo=medico
-- son 100% comerciales (precio/nombre/descripción). Mismo patrón "policy pública + filtro de tipo en el
-- cliente" que ya usan /planes-clinica /planes-lab /planes-visitador → agregar 'medico' es consistente.
--
-- Solo se AGREGA 'medico' a la allowlist de tipos en el USING de las 2 policies existentes (ALTER, no
-- reescribe la 013). La policy de 'authenticated' (qual=true, ve todo) NO se toca.
-- ============================================================================

BEGIN;

ALTER POLICY "Proveedores ven planes disponibles" ON public.planes_base
  USING (
    activo = true
    AND tipo IN ('visitador', 'publicidad', 'farmacia', 'farmaceutico', 'empresas_afines', 'medico')
  );

ALTER POLICY "Proveedores ven configuraciones de planes" ON public.planes_configuracion
  USING (
    activo = true
    AND plan_base_id IN (
      SELECT id FROM public.planes_base
      WHERE activo = true
        AND tipo IN ('visitador', 'publicidad', 'farmacia', 'farmaceutico', 'empresas_afines', 'medico')
    )
  );

COMMIT;
