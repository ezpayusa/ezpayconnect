-- 207 Storage para logos de personalización de tema — bucket público + policies scoped por tenant.
-- El staff sube su logo aquí ANTES de solicitar_personalizacion; la URL pública viaja como p_logo_url.
-- Público de lectura (logo no sensible) SIN policy SELECT → se sirve por URL directa pero NO se puede
-- enumerar el bucket. Escritura atada a la sesión: nadie sube "a nombre de" otro tenant.
-- Path: {tenant_tipo}/{tenant_id}/{uuid}.{ext}  (tipo ∈ 'clinica' | 'empresa_proveedora').
--
-- PENDIENTE (no en este bloque): limpiar_logos_huerfanos() — borrar objetos bajo {tipo}/{id}/ no
-- referenciados por la fila del tenant ni por ninguna solicitud pendiente. Se deja para después.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'personalizacion-logos', 'personalizacion-logos', true,
  1048576,  -- 1 MB
  ARRAY['image/png','image/jpeg','image/webp','image/svg+xml']
)
ON CONFLICT (id) DO NOTHING;

-- INSERT: solo el staff autorizado del tenant, y solo bajo su propia carpeta.
DROP POLICY IF EXISTS "personalizacion_logos_insert" ON storage.objects;
CREATE POLICY "personalizacion_logos_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'personalizacion-logos' AND (
      ( split_part(name, '/', 1) = 'clinica'
        AND split_part(name, '/', 2) IN (SELECT c::text FROM private.clinicas_del_usuario() c)
        AND private.tiene_rol(ARRAY['admin_clinica','gerente']) )
      OR
      ( split_part(name, '/', 1) = 'empresa_proveedora'
        AND split_part(name, '/', 2) = public.mi_empresa_proveedor()::text
        AND public.mi_rol_proveedor() = 'admin' )
    )
  );

-- UPDATE: misma condición scoped (permite reemplazar el propio archivo).
DROP POLICY IF EXISTS "personalizacion_logos_update" ON storage.objects;
CREATE POLICY "personalizacion_logos_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'personalizacion-logos' AND (
      ( split_part(name, '/', 1) = 'clinica'
        AND split_part(name, '/', 2) IN (SELECT c::text FROM private.clinicas_del_usuario() c)
        AND private.tiene_rol(ARRAY['admin_clinica','gerente']) )
      OR
      ( split_part(name, '/', 1) = 'empresa_proveedora'
        AND split_part(name, '/', 2) = public.mi_empresa_proveedor()::text
        AND public.mi_rol_proveedor() = 'admin' )
    )
  )
  WITH CHECK (
    bucket_id = 'personalizacion-logos' AND (
      ( split_part(name, '/', 1) = 'clinica'
        AND split_part(name, '/', 2) IN (SELECT c::text FROM private.clinicas_del_usuario() c)
        AND private.tiene_rol(ARRAY['admin_clinica','gerente']) )
      OR
      ( split_part(name, '/', 1) = 'empresa_proveedora'
        AND split_part(name, '/', 2) = public.mi_empresa_proveedor()::text
        AND public.mi_rol_proveedor() = 'admin' )
    )
  );

-- DELETE: el staff borra SU propio draft (scoped) OR super_admin borra cualquiera (moderación).
DROP POLICY IF EXISTS "personalizacion_logos_delete" ON storage.objects;
CREATE POLICY "personalizacion_logos_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'personalizacion-logos' AND (
      ( split_part(name, '/', 1) = 'clinica'
        AND split_part(name, '/', 2) IN (SELECT c::text FROM private.clinicas_del_usuario() c)
        AND private.tiene_rol(ARRAY['admin_clinica','gerente']) )
      OR
      ( split_part(name, '/', 1) = 'empresa_proveedora'
        AND split_part(name, '/', 2) = public.mi_empresa_proveedor()::text
        AND public.mi_rol_proveedor() = 'admin' )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

-- SELECT SCOPED: necesaria para que el propio staff / super_admin puedan resolver el objeto (el DELETE
-- del Storage lee el objeto antes de borrarlo — sin SELECT, "Access denied"). Es SCOPED por tenant (o
-- super_admin), NO global: un tenant lista SOLO su carpeta → NO hay enumeración cross-tenant. El render
-- por URL pública no depende de esto (bucket público sirve directo).
DROP POLICY IF EXISTS "personalizacion_logos_select" ON storage.objects;
CREATE POLICY "personalizacion_logos_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'personalizacion-logos' AND (
      ( split_part(name, '/', 1) = 'clinica'
        AND split_part(name, '/', 2) IN (SELECT c::text FROM private.clinicas_del_usuario() c) )
      OR
      ( split_part(name, '/', 1) = 'empresa_proveedora'
        AND split_part(name, '/', 2) = public.mi_empresa_proveedor()::text )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );
