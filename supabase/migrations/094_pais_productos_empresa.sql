-- ============================================================
-- PAÍS #1 · productos_empresa — aislar la vista del médico por país (SEGURIDAD/lectura)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva en prod (nota 20) → smoke al aplicar.
-- Probes red-first (P195–P198). Orden interno IMPORTA: backfill → trigger → NOT NULL → policy.
-- pais_id = país de SEDE de la empresa (empresa.pais_id). Ampliar un producto a varios países
-- = monetización futura (operación M:N), NO aquí.
-- ============================================================

-- 1) BACKFILL primero (las 32 filas NULL; empresas con país NULL = 0 → quedan 0)
UPDATE public.productos_empresa pe
   SET pais_id = e.pais_id
  FROM public.empresas_proveedoras e
 WHERE pe.empresa_id = e.id AND pe.pais_id IS NULL;

DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.productos_empresa WHERE pais_id IS NULL;
  IF n > 0 THEN RAISE EXCEPTION 'backfill incompleto: % filas con pais_id NULL', n; END IF;
END $$;

-- 2) CERRAR A FUTURO: trigger que FUERZA pais_id := país de la empresa (deriva server-side de
--    empresa_id; ignora cualquier país que mande el cliente — anti-escalada, lección 8).
CREATE OR REPLACE FUNCTION private.forzar_pais_producto()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  NEW.pais_id := (SELECT e.pais_id FROM public.empresas_proveedoras e WHERE e.id = NEW.empresa_id);
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION private.forzar_pais_producto() FROM PUBLIC, anon;

-- Dispara en INSERT y en UPDATE de pais_id O empresa_id: re-asignar el producto a otra
-- empresa (sin tocar pais_id) DEBE re-derivar el país de la nueva empresa (no conservar el viejo).
DROP TRIGGER IF EXISTS trg_forzar_pais_producto ON public.productos_empresa;
CREATE TRIGGER trg_forzar_pais_producto
  BEFORE INSERT OR UPDATE OF pais_id, empresa_id ON public.productos_empresa
  FOR EACH ROW EXECUTE FUNCTION private.forzar_pais_producto();

-- 3) NOT NULL (tras backfill; el trigger garantiza que futuros inserts traen país)
ALTER TABLE public.productos_empresa ALTER COLUMN pais_id SET NOT NULL;

-- 4) POLICY médico: añadir el término país (conjuntivo → solo restringe). Las demás SELECT
--    (Proveedor TO public, Admin ezpay, Proveedor gestiona ALL) NO le re-abren al médico
--    (para médico mi_empresa_proveedor() = NULL → 0 filas). fail-closed: mi_pais() NULL → 0.
DROP POLICY IF EXISTS "Médico ve productos activos" ON public.productos_empresa;
CREATE POLICY "Médico ve productos activos" ON public.productos_empresa
  FOR SELECT TO authenticated
  USING (
    estado = 'activo'
    AND NOT COALESCE(private.empresa_es_afin(empresa_id), false)
    AND pais_id = private.mi_pais()
  );
