-- FASE 4 — Gate "liberado al paciente" (bloque 1/3: esquema + policies de enforcement).
-- Decisiones: modelo por-examen; enforcement REAL en RLS (no solo frontend); backfill en false (se libera en la prueba).
-- Aplicar con: supabase db query --linked -f <este archivo>   (NUNCA db push)

-- 1) Esquema: flag de liberación + auditoría. Idempotente.
ALTER TABLE public.examenes
  ADD COLUMN IF NOT EXISTS liberado_al_paciente boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fecha_liberacion timestamptz,
  ADD COLUMN IF NOT EXISTS liberado_por uuid;

-- 2) Enforcement del ARCHIVO: la rama del paciente en la SELECT de storage ahora exige liberado.
--    (medico / lab / clinica / super_admin intactos: el medico debe poder ver el archivo ANTES de liberar.)
ALTER POLICY resultados_scoped_select ON storage.objects
USING (
  ((bucket_id = 'resultados-examenes'::text) AND ((split_part(name, '/'::text, 1) = (mi_empresa_proveedor())::text) OR (EXISTS ( SELECT 1
     FROM examenes e
    WHERE ((COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/'::text, 2), ''::text), e.archivo_url) = objects.name) AND ((private.paciente_es_mio((e.paciente_id)::bigint) AND e.liberado_al_paciente) OR (e.medico_id = auth.uid()) OR private.medico_atiende_paciente((e.paciente_id)::bigint) OR ((e.clinica_id IS NOT NULL) AND private.es_admin_clinica(e.clinica_id)) OR (e.laboratorio_id = mi_empresa_proveedor()) OR private.tiene_rol(ARRAY['super_admin'::text])))))))
);

-- 3) Enforcement de la FILA/TEXTO: el paciente ve el examen mientras NO esta completado; una vez completado,
--    solo lo ve si fue liberado. La ventana "completado + no liberado" queda oculta a nivel RLS (ni por API directa).
ALTER POLICY "Paciente ve sus examenes" ON public.examenes
USING (
  (paciente_id IN ( SELECT pacientes.id FROM pacientes WHERE (pacientes.auth_user_id = auth.uid())))
  AND (liberado_al_paciente OR (estado <> 'completado'::examen_estado))
);
