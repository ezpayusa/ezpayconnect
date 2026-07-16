-- Fix: el upload del laboratorio a 'resultados-examenes' falla con "new row violates RLS".
-- Causa real: storage.upload() inserta el objeto y lo LEE de vuelta; ese read-back pasa por la
-- policy SELECT. La SELECT de resultados exigía que un examen ya referenciara el objeto (examenes.archivo_url),
-- referencia que se escribe DESPUÉS del upload -> dependencia circular. comprobantes no la tiene.
-- Solución: sumar la rama "dueño del prefijo" (igual que comprobantes_scoped_select) para que el lab
-- pueda leer su propio prefijo y el read-back del upload pase. No cambia acceso de paciente/médico/clínica.
ALTER POLICY resultados_scoped_select ON storage.objects
USING (
  (bucket_id = 'resultados-examenes'::text)
  AND (
    (split_part(name, '/'::text, 1) = (mi_empresa_proveedor())::text)
    OR (EXISTS (
      SELECT 1 FROM examenes e
      WHERE ((COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/'::text, 2), ''::text), e.archivo_url) = objects.name)
        AND (private.paciente_es_mio((e.paciente_id)::bigint)
          OR (e.medico_id = auth.uid())
          OR private.medico_atiende_paciente((e.paciente_id)::bigint)
          OR ((e.clinica_id IS NOT NULL) AND private.es_admin_clinica(e.clinica_id))
          OR (e.laboratorio_id = mi_empresa_proveedor())
          OR private.tiene_rol(ARRAY['super_admin'::text])))
    ))
  )
);
