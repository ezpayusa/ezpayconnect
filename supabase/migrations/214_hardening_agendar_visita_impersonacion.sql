-- ============================================================================
-- Migración 214: HARDENING — cierra impersonación en el alta de visitas (INSERT directo)
-- ============================================================================
-- GAP QUE CIERRA:
-- El alta de visitas (agendarVisita) es un INSERT DIRECTO a visitas_agendadas. Dos huecos que,
-- combinados, permitían saltarse la aprobación:
--   1. La policy INSERT validaba que cuenta_proveedor_id pertenezca a la empresa
--      (private.cuenta_en_empresa), pero NO que cuenta_proveedor_id = auth.uid() → un visitador
--      podía insertar una visita atribuida a OTRA cuenta de su empresa.
--   2. El trigger set_default_estado_propuesta (mig 015) decidía si forzar estado='propuesta'
--      mirando el rol de NEW.cuenta_proveedor_id, NO el rol de quien realmente hace el INSERT
--      (auth.uid()).
-- Combinados: un visitador insertaba una visita con cuenta_proveedor_id = un admin/editor de su
-- misma empresa → el trigger veía "rol admin/editor" y NO forzaba 'propuesta' → la visita quedaba
-- 'confirmada' directo, saltándose la aprobación. (Hoy ningún caller legítimo asigna la visita a
-- otra cuenta: el param visitadorId del hook existe pero nadie lo usa.)
--
-- FIX (100% DB, la firma de agendarVisita no cambia):
--   1) RLS INSERT más estricta: cuenta_proveedor_id debe ser la propia (auth.uid()), salvo que el
--      caller sea admin/editor de la empresa (autoridad real para agendar a nombre de otro).
--   2) Trigger corregido: mira el rol del CALLER (auth.uid()), no el de NEW.cuenta_proveedor_id.
-- Defensa en profundidad: la RLS rechaza el INSERT impersonado; y aunque pasara, el trigger fuerza
-- 'propuesta' según el rol real del caller.
-- ============================================================================


-- ============================================================================
-- 1) RLS INSERT más estricta (DROP + CREATE; preserva las 2 cláusulas previas, agrega la 3ª).
-- ============================================================================
DROP POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas;
CREATE POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas
  FOR INSERT
  WITH CHECK (
    empresa_id IN (
      SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor
      WHERE cuentas_proveedor.id = auth.uid()
        AND cuentas_proveedor.activo = true
        AND cuentas_proveedor.rol_en_empresa = ANY (ARRAY['admin', 'editor', 'visitador_medico'])
    )
    AND private.cuenta_en_empresa(cuenta_proveedor_id, empresa_id)
    AND (
      cuenta_proveedor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM cuentas_proveedor
        WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
      )
    )
  );


-- ============================================================================
-- 2) Trigger corregido — decide el forzado a 'propuesta' por el rol del CALLER (auth.uid()),
--    no por el rol de NEW.cuenta_proveedor_id (que era impersonable). El trigger
--    trigger_forzar_estado_propuesta ya apunta a esta función por nombre → REPLACE alcanza.
--    Se sube a SECURITY DEFINER + search_path fijo (antes era INVOKER sin search_path) para leer
--    el rol del caller de forma robusta, en línea con el patrón de las migs 209-213.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_default_estado_propuesta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor
    WHERE id = auth.uid()
      AND rol_en_empresa IN ('admin', 'editor')
  ) THEN
    NEW.estado := 'propuesta';
  END IF;
  RETURN NEW;
END;
$function$;
