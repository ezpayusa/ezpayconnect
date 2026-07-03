-- ============================================================================
-- Migración 212: evidencias-visitas → bucket PRIVADO + policy SELECT scoped
-- ============================================================================
-- GAP QUE CIERRA:
-- El bucket evidencias-visitas nació público (mig 014, storage.buckets.public=true) con una
-- policy SELECT abierta ("Todos ven evidencias": bucket_id='evidencias-visitas', roles=public,
-- sin scope) → CUALQUIERA con la URL pública podía ver la evidencia fotográfica de checkin de
-- CUALQUIER visita. Esta migración lo cierra: bucket privado + SELECT scoped por empresa +
-- ownership/rol, espejando el molde ya en prod de entregas-evidencia (mig 148, privado + select
-- scoped). Complementa la mig 209 (que ya acotó INSERT/UPDATE por ownership) — esas NO se tocan.
--
-- MIGRACIÓN DE DATOS: ninguna. Confirmado 0 filas en visitas_agendadas.checkin_evidencia_url →
-- no hay evidencia legacy que servir por URL pública ni compatibilidad que preservar. El front
-- pasará a openSignedUrl (createSignedUrl) en la pieza siguiente.
-- ============================================================================

-- 1) Bucket privado.
UPDATE storage.buckets SET public = false WHERE id = 'evidencias-visitas';

-- 2) Quitar la policy SELECT abierta de la mig 014.
DROP POLICY IF EXISTS "Todos ven evidencias" ON storage.objects;

-- 3) SELECT scoped (para createSignedUrl). Espeja la RLS de visitas_agendadas, igual que el molde
--    entregas_evidencia_select espeja la de entregas: el EXISTS sobre visitas_agendadas se evalúa
--    BAJO la RLS de esa tabla, así la visibilidad de la evidencia == la visibilidad de la visita
--    (fuente única). Por la RLS de visitas_agendadas eso da: el visitador dueño ve su visita;
--    admin/editor ven toda la empresa; supervisor ve su equipo asignado (supervisa_cuenta_proveedor);
--    super_admin ve todo. Parseo del segmento con private.safe_uuid (mig 209): path malformado →
--    NULL → sin match. El OR super_admin es explícito (la RLS de visitas ya lo cubre; redundante pero claro).
CREATE POLICY "evidencias_visitas_select_scoped"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'evidencias-visitas'
    AND (
      EXISTS (
        SELECT 1
        FROM public.visitas_agendadas v
        WHERE v.id = private.safe_uuid(split_part(storage.objects.name, '/', 2))
      )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

-- 4) Las policies INSERT/UPDATE de la mig 209 (evidencias_visitas_insert_scoped /
--    _update_scoped) quedan INTACTAS. Sin policy DELETE → borrado solo owner/service_role.
