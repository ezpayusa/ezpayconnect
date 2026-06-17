-- ============================================================
-- VIS-A · Visitas: el plan de visitas solo para país ∈ operación + NOT NULL
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first (P241–P245).
-- Recon: el ÚNICO write de planes_visitador_contratados es super_admin (policy ALL "Admin
-- ezpay gestiona planes visitador"); el proveedor NO tiene policy INSERT/UPDATE (no puede
-- escribir ni auto-activar — anti-escalada ya cerrada por RLS). No hay RPC/path de contratar
-- self-service. → el gate país va en el único write gate (super_admin), lección 7.
--
-- Gate: WITH CHECK += empresa_opera_en_pais(empresa_id, pais_id) (server-side, no param libre,
-- lección 8). El plan queda de su empresa; país ∈ operación. + pais_id NOT NULL (V-G1 lo usa).
-- Si en el futuro se añade un RPC de contratar (proveedor-iniciado), DEBE validar igual.
-- ============================================================

-- 1) Backfill (la 1 fila NULL → país de su empresa, sede operada por el seed de G1) + NOT NULL
UPDATE public.planes_visitador_contratados pvc
   SET pais_id = e.pais_id
  FROM public.empresas_proveedoras e
 WHERE pvc.empresa_id = e.id AND pvc.pais_id IS NULL;

DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.planes_visitador_contratados WHERE pais_id IS NULL;
  IF n > 0 THEN RAISE EXCEPTION 'backfill incompleto: % planes con pais_id NULL', n; END IF;
END $$;

ALTER TABLE public.planes_visitador_contratados ALTER COLUMN pais_id SET NOT NULL;

-- 2) País gate en el write super_admin (único write gate). USING sin cambio; WITH CHECK añade país.
DROP POLICY IF EXISTS "Admin ezpay gestiona planes visitador" ON public.planes_visitador_contratados;
CREATE POLICY "Admin ezpay gestiona planes visitador" ON public.planes_visitador_contratados
  FOR ALL TO authenticated
  USING (COALESCE(private.tiene_rol(ARRAY['super_admin']), false))
  WITH CHECK (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false)   -- país ∈ operación
  );
