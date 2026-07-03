-- ============================================================================
-- Migración 209: HARDENING Storage — bucket evidencias-visitas, scope de ownership
-- ============================================================================
-- GAP QUE CIERRA:
-- La policy INSERT original (mig 014, "Autenticados suben evidencias") permitía a
-- CUALQUIER usuario authenticated subir a CUALQUIER path del bucket evidencias-visitas,
-- sin verificar que el path perteneciera a una visita/empresa suya. El front sube a
--   `${empresa_id}/${visita_id}/checkin_${ts}.${ext}`  (con upsert:true → reintentos).
-- Un tercero podía escribir bajo el path de otra empresa/visita (y, por el upsert,
-- sobrescribir evidencia ajena — máxime cuando NO existía policy UPDATE que lo acotara).
--
-- QUÉ HACE (mínimo y quirúrgico):
--   1. Dropea la policy INSERT laxa de la 014.
--   2. Crea INSERT scoped: path[1]=mi empresa, y path[2] apunta a una visita_agendada
--      REAL mía (empresa_id = mi empresa AND cuenta_proveedor_id = auth.uid()) en un
--      estado válido para evidencia ('confirmada'/'aprobada', los mismos que habilitan
--      check-in en el front: VisitadorMisVisitasPage.puedeCheckin).
--   3. Crea UPDATE (no existía) con el MISMO check → cubre el upsert/reintento.
--   NO toca: config del bucket (2 MB, MIME image/jpeg|png|webp) ni la policy SELECT pública.
--
-- Espeja el patrón ya en prod de "entregas_evidencia_insert" (bucket entregas-evidencia):
-- split_part(path) para empresa + EXISTS sobre la tabla de negocio con ownership por auth.uid().
-- ============================================================================

-- Helper de parseo de path: castea a uuid de forma segura. Un path malformado (segmento
-- que no es uuid) devuelve NULL → el EXISTS no matchea → DENEGACIÓN LIMPIA (en vez de un
-- error de cast en tiempo de evaluación de la policy). En schema private, search_path fijo.
CREATE OR REPLACE FUNCTION private.safe_uuid(p_text text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN p_text::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION private.safe_uuid(text) TO authenticated;

-- 1. Drop de la policy INSERT laxa de la mig 014.
DROP POLICY IF EXISTS "Autenticados suben evidencias" ON storage.objects;

-- 2. INSERT scoped por ownership de empresa + visita.
CREATE POLICY "evidencias_visitas_insert_scoped"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'evidencias-visitas'
    -- path[1] (empresa_id) == la empresa del uploader
    AND split_part(name, '/', 1) = public.mi_empresa_proveedor()::text
    -- path[2] (visita_id) apunta a una visita REAL, de mi empresa, agendada a mí,
    -- y en un estado que habilita subir evidencia.
    AND EXISTS (
      SELECT 1
      FROM public.visitas_agendadas v
      WHERE v.id = private.safe_uuid(split_part(storage.objects.name, '/', 2))
        AND v.empresa_id = public.mi_empresa_proveedor()
        AND v.cuenta_proveedor_id = auth.uid()
        AND v.estado IN ('confirmada', 'aprobada')
    )
  );

-- 3. UPDATE con el MISMO check (no existía policy UPDATE → el upsert:true del front quedaba
--    sin acotar). USING acota qué objeto existente se puede sobrescribir; WITH CHECK acota
--    el objeto resultante. Ambos con la misma condición de ownership.
CREATE POLICY "evidencias_visitas_update_scoped"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'evidencias-visitas'
    AND split_part(name, '/', 1) = public.mi_empresa_proveedor()::text
    AND EXISTS (
      SELECT 1
      FROM public.visitas_agendadas v
      WHERE v.id = private.safe_uuid(split_part(storage.objects.name, '/', 2))
        AND v.empresa_id = public.mi_empresa_proveedor()
        AND v.cuenta_proveedor_id = auth.uid()
        AND v.estado IN ('confirmada', 'aprobada')
    )
  )
  WITH CHECK (
    bucket_id = 'evidencias-visitas'
    AND split_part(name, '/', 1) = public.mi_empresa_proveedor()::text
    AND EXISTS (
      SELECT 1
      FROM public.visitas_agendadas v
      WHERE v.id = private.safe_uuid(split_part(storage.objects.name, '/', 2))
        AND v.empresa_id = public.mi_empresa_proveedor()
        AND v.cuenta_proveedor_id = auth.uid()
        AND v.estado IN ('confirmada', 'aprobada')
    )
  );

-- 4. La policy SELECT pública ("Todos ven evidencias") queda INTACTA — decisión de otra sesión.
