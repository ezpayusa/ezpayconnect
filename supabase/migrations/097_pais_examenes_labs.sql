-- ============================================================
-- PAÍS #3 · examenes_catalogo + laboratorios_para_medico — aislar labs clínicos por país
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20) → smoke al aplicar.
-- Probes red-first (P210–P215).
--
-- examenes_catalogo no tiene pais_id → se deriva del lab (laboratorio_id → empresa.pais_id)
-- vía helper DEFINER private.lab_en_mi_pais (país-0). Conjuntivo, fail-closed.
-- CAMBIO DE ROL: catalogo_read_activos pasa de TO public a TO authenticated. lab_en_mi_pais
-- está REVOKE de anon → con TO public, anon erroraría al evaluar la función; TO authenticated
-- lo evita y retira el read anon del catálogo de exámenes (no hay lector anon legítimo).
-- NO se toca catalogo_lab_all (el lab gestiona su propio catálogo) ni write/ALL.
-- ============================================================

DROP POLICY IF EXISTS "catalogo_read_activos" ON public.examenes_catalogo;
CREATE POLICY "catalogo_read_activos" ON public.examenes_catalogo
  FOR SELECT TO authenticated
  USING (
    activo = true
    AND private.lab_en_mi_pais(laboratorio_id)
  );

-- ------------------------------------------------------------
-- laboratorios_para_medico: fail-closed (v_pais NULL → 0 labs, no todos). v_pais sigue
-- derivado server-side de perfiles.pais_id/auth.uid() (NO parámetro). Refs schema-calificadas.
-- search_path = 'public' (NO ''): la función llama a public.obtener_clinica_principal_medico,
-- que NO tiene SET search_path propio y usa 'medico_clinicas' sin calificar → con '' heredaría
-- el path vacío y rompería ("relation medico_clinicas does not exist"). 'public' = el original
-- y el inner resuelve. Endurecer a '' queda DIFERIDO (requiere endurecer ese helper primero).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.laboratorios_para_medico()
RETURNS TABLE(id uuid, nombre_empresa text, ciudad text, afiliado boolean, es_preferido boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_pais    uuid;
  v_clinica uuid;
  v_pref    uuid;
BEGIN
  SELECT p.pais_id, p.laboratorio_preferido_id INTO v_pais, v_pref
  FROM public.perfiles p WHERE p.id = auth.uid();

  SELECT m.clinica_id INTO v_clinica
  FROM public.obtener_clinica_principal_medico(auth.uid()) m LIMIT 1;

  RETURN QUERY
  SELECT e.id, e.nombre_empresa, e.ciudad,
         EXISTS (
           SELECT 1 FROM public.laboratorio_clinicas lc
           WHERE lc.laboratorio_id = e.id AND lc.clinica_id = v_clinica AND lc.estado = 'activa'
         ) AS afiliado,
         (e.id = v_pref) AS es_preferido
  FROM public.empresas_proveedoras e
  WHERE e.tipo = 'laboratorio_clinico'
    AND e.estado = 'activa'
    AND e.pais_id = v_pais          -- fail-closed: v_pais NULL → '= NULL' → 0 labs
  ORDER BY afiliado DESC, es_preferido DESC, e.nombre_empresa;
END;
$function$;
