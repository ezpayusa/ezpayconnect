-- ############################################################################################
-- Rollback de la migracion 328 - vuelve al estado medido el 25-sep-2026 (antes de la 328)
-- ############################################################################################
-- Restaura EXACTO: INSERT de authenticated en recetas y receta_items, recetas_insert,
-- receta_items_medico_all y receta_items_superadmin_all, y quita las 4 policies de la 328.
-- El relacl de las dos tablas y el conjunto de policies se comparan contra lo capturado.
-- OJO: reabre la ruta directa de emision (salteo de O1). Solo para volver atras la 328.
-- ############################################################################################

BEGIN;

GRANT INSERT ON public.recetas, public.receta_items TO authenticated;

DROP POLICY receta_items_medico_select ON public.receta_items;
DROP POLICY receta_items_superadmin_select ON public.receta_items;
DROP POLICY receta_items_superadmin_update ON public.receta_items;
DROP POLICY receta_items_superadmin_delete ON public.receta_items;

CREATE POLICY recetas_insert ON public.recetas
  FOR INSERT TO authenticated
  WITH CHECK ((auth.uid() = medico_id) AND (private.medico_atiende_paciente(paciente_id) OR (EXISTS (
    SELECT 1 FROM public.pacientes pa WHERE ((pa.id = recetas.paciente_id) AND (pa.medico_id = auth.uid()))))));

CREATE POLICY receta_items_medico_all ON public.receta_items
  FOR ALL TO authenticated
  USING (receta_id IN (SELECT r.id FROM public.recetas r WHERE r.medico_id = auth.uid()))
  WITH CHECK (receta_id IN (SELECT r.id FROM public.recetas r WHERE r.medico_id = auth.uid()));

CREATE POLICY receta_items_superadmin_all ON public.receta_items
  FOR ALL TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));

-- AUTOCHEQUEO -------------------------------------------------------------------------------------
DO $ac$
DECLARE v text := ''; sp text := current_setting('search_path'); esperado text; obtenido text;
BEGIN
  PERFORM set_config('search_path', '', true);

  SELECT string_agg(c.relname||'='||c.relacl::text, ' ' ORDER BY c.relname) INTO obtenido
    FROM pg_catalog.pg_class c WHERE c.oid IN ('public.recetas'::regclass, 'public.receta_items'::regclass);
  IF obtenido IS DISTINCT FROM
     'receta_items={postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres} '
   ||'recetas={postgres=arwdDxtm/postgres,anon=rm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    v := v||E'\n relacl distinto: '||COALESCE(obtenido,'NULL'); END IF;

  esperado := concat_ws(E'\n',
    'receta_items|Admin clinica ve items de recetas de su clinica|r|authenticated|COALESCE(private.receta_de_mi_clinica(receta_id), false)|',
    'receta_items|Paciente ve items de sus recetas|r|public|(receta_id IN ( SELECT r.id'||E'\n'||'   FROM (public.recetas r'||E'\n'||'     JOIN public.pacientes p ON ((r.paciente_id = p.id)))'||E'\n'||'  WHERE (p.auth_user_id = auth.uid())))|',
    'receta_items|receta_items_medico_all|*|authenticated|(receta_id IN ( SELECT r.id'||E'\n'||'   FROM public.recetas r'||E'\n'||'  WHERE (r.medico_id = auth.uid())))|(receta_id IN ( SELECT r.id'||E'\n'||'   FROM public.recetas r'||E'\n'||'  WHERE (r.medico_id = auth.uid())))',
    'receta_items|receta_items_superadmin_all|*|authenticated|private.tiene_rol(ARRAY[''super_admin''::text])|private.tiene_rol(ARRAY[''super_admin''::text])',
    'recetas|Admin clinica ve recetas de su clinica|r|authenticated|COALESCE(private.medico_es_de_mi_clinica(medico_id), false)|',
    'recetas|Admin ve recetas de su pais|r|public|((public.get_auth_user_rol() = ''super_admin''::text) OR ((public.get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = public.get_auth_user_pais_id())))|',
    'recetas|Paciente ve sus recetas|r|public|(paciente_id IN ( SELECT pacientes.id'||E'\n'||'   FROM public.pacientes'||E'\n'||'  WHERE (pacientes.auth_user_id = auth.uid())))|',
    'recetas|recetas_insert|a|authenticated||((auth.uid() = medico_id) AND (private.medico_atiende_paciente(paciente_id) OR (EXISTS ( SELECT 1'||E'\n'||'   FROM public.pacientes pa'||E'\n'||'  WHERE ((pa.id = recetas.paciente_id) AND (pa.medico_id = auth.uid()))))))',
    'recetas|recetas_select|r|authenticated|(auth.uid() = medico_id)|');
  SELECT string_agg(c.relname||'|'||p.polname||'|'||p.polcmd::text||'|'
           ||(SELECT string_agg(CASE WHEN x = 0 THEN 'public' ELSE pg_catalog.pg_get_userbyid(x) END, ',' ORDER BY 1) FROM pg_catalog.unnest(p.polroles) x)
           ||'|'||COALESCE(pg_catalog.pg_get_expr(p.polqual, p.polrelid),'')
           ||'|'||COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid),''), E'\n' ORDER BY c.relname, p.polname)
    INTO obtenido
    FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
   WHERE p.polrelid IN ('public.recetas'::regclass, 'public.receta_items'::regclass);
  IF obtenido IS DISTINCT FROM esperado THEN
    v := v||E'\n policies distintas de las capturadas:\n--- obtenido ---\n'||COALESCE(obtenido,'NULL'); END IF;

  PERFORM set_config('search_path', sp, true);
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK328 AUTOCHEQUEO FALLA:%', v; END IF;
END $ac$;

COMMIT;
