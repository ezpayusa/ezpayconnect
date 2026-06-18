-- ============================================================
-- Ola 2 · CHECK de dominio en solicitudes_campana.estado (INTEGRIDAD). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first P292–P296.
--
-- estado era text NOT NULL sin CHECK → aceptaba cualquier string. Dominio autoritativo
-- (de DEFAULT + RLS proveedor + RPC aprobar + frontend): {borrador, enviada, publicada, rechazada}.
-- Pre-validación confirmó 0 filas fuera del dominio (DISTINCT prod: borrador/enviada/publicada).
--
-- ORTOGONALIDAD: el CHECK es INTEGRIDAD de dominio, NO autorización. Quién puede setear
-- 'publicada' sigue en RLS/RPC: aprobar_solicitud_campana es super_admin-only (DEFINER) y las
-- policies de proveedor EXCLUYEN 'publicada' de su with_check (lección 10: el solicitante no
-- auto-publica). El CHECK solo restringe el VALOR; no es máquina de transiciones.
-- ============================================================

-- Guard de pre-validación (defensa en profundidad: aborta si apareciera un valor fuera de dominio)
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.solicitudes_campana
   WHERE estado NOT IN ('borrador','enviada','publicada','rechazada');
  IF n > 0 THEN
    RAISE EXCEPTION 'No se añade el CHECK: % filas con estado fuera de dominio (resolver primero)', n;
  END IF;
END $$;

ALTER TABLE public.solicitudes_campana
  ADD CONSTRAINT solicitudes_campana_estado_check
  CHECK (estado IN ('borrador','enviada','publicada','rechazada'));
