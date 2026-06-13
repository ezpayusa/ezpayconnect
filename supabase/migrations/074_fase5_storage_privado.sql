-- ============================================================
-- FASE 5 · Bloque E — Storage privado + RLS scoped (PHI/financiero)
-- ------------------------------------------------------------
-- resultados-examenes (PHI) y comprobantes (financiero) eran buckets PÚBLICOS
-- → cualquiera con la URL accedía sin auth. Los hacemos PRIVADOS y scopeamos
-- storage.objects por objeto. El frontend pasa a createSignedUrl (cliente), que
-- exige SELECT sobre el objeto vía estas políticas → "no se firma sin derecho".
--
-- Mapeo objeto→autorización:
--   resultados: path = labId/ordenId-ts.ext (labId = empresa del laboratorio =
--     mi_empresa_proveedor del lab). Se une al examen comparando el path EXACTO
--     derivado de examenes.archivo_url contra storage.objects.name (sin LIKE, para
--     que _ y % del nombre no actúen como comodines y crucen el examen de otro).
--     Lectura: paciente dueño / médico que ordenó o atiende / admin de la clínica /
--     laboratorio dueño / super_admin.
--   comprobantes: path = empresaId/ts.ext; el 1er segmento ES la empresa.
--     Lectura: la empresa dueña (mi_empresa_proveedor) / super_admin.
--
-- Escritura (INSERT/UPDATE): antes ABIERTA (cualquier authenticated subía/
--   sobrescribía en CUALQUIER path → inyección/tampering de objetos ajenos).
--   Ahora cada quien sólo escribe en SU folder de empresa (split_part(name,'/',1)
--   = mi_empresa_proveedor) o super_admin. El lab sube a labId/...; el proveedor
--   sube su comprobante a empresaId/... (ambos con upsert:true → UPDATE también).
-- ============================================================

-- 1. Buckets → privados
UPDATE storage.buckets SET public = false WHERE id IN ('resultados-examenes', 'comprobantes');

-- 2. Quitar las SELECT abiertas (la fuga de LECTURA)
DROP POLICY IF EXISTS "Lectura publica resultados" ON storage.objects;        -- public read (resultados)
DROP POLICY IF EXISTS "Autenticados ven comprobantes" ON storage.objects;     -- cualquier authenticated
DROP POLICY IF EXISTS "Autenticados ven sus comprobantes" ON storage.objects; -- (idéntica, redundante)
DROP POLICY IF EXISTS "Admin ve comprobantes" ON storage.objects;             -- la replica el nuevo super_admin

-- 3. SELECT scoped — resultados-examenes (match EXACTO del path, sin comodines)
DROP POLICY IF EXISTS "resultados_scoped_select" ON storage.objects;
CREATE POLICY "resultados_scoped_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND EXISTS (
      SELECT 1 FROM public.examenes e
      WHERE COALESCE(
              NULLIF(split_part(e.archivo_url, '/resultados-examenes/', 2), ''),
              e.archivo_url
            ) = storage.objects.name
        AND (
             private.paciente_es_mio(e.paciente_id::bigint)
          OR e.medico_id = auth.uid()
          OR private.medico_atiende_paciente(e.paciente_id::bigint)
          OR (e.clinica_id IS NOT NULL AND private.es_admin_clinica(e.clinica_id))
          OR e.laboratorio_id = public.mi_empresa_proveedor()
          OR private.tiene_rol(ARRAY['super_admin'])
        )
    )
  );

-- 4. SELECT scoped — comprobantes (1er segmento del path = empresa)
DROP POLICY IF EXISTS "comprobantes_scoped_select" ON storage.objects;
CREATE POLICY "comprobantes_scoped_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'comprobantes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  );

-- 5. INSERT scoped — resultados-examenes (sólo en el folder de la propia empresa)
DROP POLICY IF EXISTS "Autenticados suben resultados" ON storage.objects;
DROP POLICY IF EXISTS "resultados_scoped_insert" ON storage.objects;
CREATE POLICY "resultados_scoped_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'resultados-examenes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  );

-- 6. UPDATE scoped — resultados-examenes (upsert:true sobrescribe; sólo el dueño del folder)
DROP POLICY IF EXISTS "Autenticados actualizan resultados" ON storage.objects;
DROP POLICY IF EXISTS "resultados_scoped_update" ON storage.objects;
CREATE POLICY "resultados_scoped_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  )
  WITH CHECK (
    bucket_id = 'resultados-examenes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  );

-- 7. INSERT scoped — comprobantes (sólo en el folder de la propia empresa)
DROP POLICY IF EXISTS "Autenticados suben comprobantes" ON storage.objects;
DROP POLICY IF EXISTS "comprobantes_scoped_insert" ON storage.objects;
CREATE POLICY "comprobantes_scoped_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'comprobantes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  );

-- 8. UPDATE scoped — comprobantes (upsert:true; sólo el dueño del folder)
DROP POLICY IF EXISTS "comprobantes_scoped_update" ON storage.objects;
CREATE POLICY "comprobantes_scoped_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'comprobantes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  )
  WITH CHECK (
    bucket_id = 'comprobantes'
    AND (
         split_part(storage.objects.name, '/', 1) = public.mi_empresa_proveedor()::text
      OR private.tiene_rol(ARRAY['super_admin'])
    )
  );

-- (DELETE en estos dos buckets ya estaba denegado: no existe policy permisiva.)
