-- ############################################################################################
-- Migracion 328 - la emision de recetas pasa SOLO por emitir_receta
-- ############################################################################################
-- Antes (medido 25-sep contra la base viva):
--   * authenticated tenia INSERT en recetas y receta_items, y la RLS lo dejaba pasar:
--       recetas_insert           (INSERT, mig 320: medico_id = auth.uid() + pertenencia)
--       receta_items_medico_all  (ALL, receta propia)
--       receta_items_superadmin_all (ALL, super_admin)
--     El front (useRecetas.ts) usaba esa ruta directa cuando emision_flag('emitir_receta_rpc') no
--     devolvia true, incluido un error de lectura. Por ahi se salteaba O1: catalogo, activo, acuse,
--     correlativo, recetas_avanzadas y atomicidad.
--   * Todos los escritores legitimos son SECURITY DEFINER con owner postgres (BYPASSRLS):
--     emitir_receta (INSERT recetas + receta_items), notificar_receta (UPDATE recetas),
--     fijar_modalidad_grupo / registrar_dispensacion / registrar_dispensacion_dirigida
--     (UPDATE receta_items). No dependen de los grants ni de las policies de authenticated.
--   * Ninguna edge escribe recetas ni receta_items; el front solo lo hace en useRecetas.ts.
-- Decision (Oscar): cerrar las dos capas. Front: siempre emitir_receta. Base: authenticated no
-- inserta directo. Las 27 recetas legadas QA no se tocan; emision_flag y private.emision_flags
-- quedan como estan (se retiran en otro lote).
-- Cambios:
--   (a) REVOKE INSERT en recetas y receta_items a authenticated, anon y PUBLIC.
--   (b) DROP recetas_insert.
--   (c) receta_items_medico_all (ALL) -> receta_items_medico_select (SELECT, misma expresion).
--       El UPDATE/DELETE del medico sobre items no lo usa nadie (ni front, ni edge, ni RPC).
--   (d) receta_items_superadmin_all (ALL) -> SELECT / UPDATE / DELETE con la misma expresion:
--       super_admin conserva todo menos INSERT, que (a) ya le cierra.
--   (e) GRANTs explicitos de lo que queda en uso (regla del 30-oct): SELECT en recetas;
--       SELECT, UPDATE, DELETE en receta_items (policies de super_admin); service_role completo.
-- NO toca: emitir_receta, notificar_receta, las policies de paciente / clinica / pais,
-- emision_flag, private.emision_flags, ni el SELECT de anon sobre recetas (lo usan las policies
-- TO public: ver la leccion de la mig 284).
-- ############################################################################################

BEGIN;

-- (a) sin INSERT directo
REVOKE INSERT ON public.recetas, public.receta_items FROM authenticated, anon, PUBLIC;

-- (b) la policy de INSERT del medico
DROP POLICY recetas_insert ON public.recetas;

-- (c) medico: solo lectura de los items de sus recetas
DROP POLICY receta_items_medico_all ON public.receta_items;
CREATE POLICY receta_items_medico_select ON public.receta_items
  FOR SELECT TO authenticated
  USING (receta_id IN (SELECT r.id FROM public.recetas r WHERE r.medico_id = auth.uid()));

-- (d) super_admin: lo mismo que tenia, sin INSERT
DROP POLICY receta_items_superadmin_all ON public.receta_items;
CREATE POLICY receta_items_superadmin_select ON public.receta_items
  FOR SELECT TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY receta_items_superadmin_update ON public.receta_items
  FOR UPDATE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY receta_items_superadmin_delete ON public.receta_items
  FOR DELETE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));

-- (e) GRANTs explicitos de lo que queda
GRANT SELECT ON public.recetas TO authenticated;
GRANT SELECT, UPDATE, DELETE ON public.receta_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.recetas, public.receta_items TO service_role;

-- AUTOCHEQUEO -------------------------------------------------------------------------------------
DO $ac$
DECLARE
  v text := ''; t text; sp text := current_setting('search_path');
  r record; esperado text; obtenido text;
  f regprocedure := 'public.emitir_receta(bigint,text,jsonb)'::regprocedure;
BEGIN
  -- deparse determinista: con search_path vacio pg_get_expr califica todo
  PERFORM set_config('search_path', '', true);

  FOREACH t IN ARRAY ARRAY['recetas','receta_items'] LOOP
    IF has_any_column_privilege('authenticated', ('public.'||t)::regclass, 'INSERT') THEN
      v := v||E'\n authenticated conserva INSERT en '||t; END IF;
    IF has_any_column_privilege('anon', ('public.'||t)::regclass, 'INSERT') THEN
      v := v||E'\n anon conserva INSERT en '||t; END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c, pg_catalog.aclexplode(c.relacl) a
                WHERE c.oid = ('public.'||t)::regclass AND a.grantee = 0 AND a.privilege_type = 'INSERT') THEN
      v := v||E'\n PUBLIC conserva INSERT en '||t; END IF;
    IF NOT has_table_privilege('authenticated', ('public.'||t)::regclass, 'SELECT') THEN
      v := v||E'\n authenticated perdio SELECT en '||t; END IF;
    IF NOT has_table_privilege('service_role', ('public.'||t)::regclass, 'INSERT') THEN
      v := v||E'\n service_role perdio INSERT en '||t; END IF;
  END LOOP;
  IF NOT (has_table_privilege('authenticated','public.receta_items','UPDATE')
      AND has_table_privilege('authenticated','public.receta_items','DELETE')) THEN
    v := v||E'\n authenticated perdio UPDATE/DELETE en receta_items (policies de super_admin)'; END IF;

  -- ninguna policy INSERT o ALL que alcance a authenticated o public
  FOR r IN SELECT c.relname, p.polname, p.polcmd FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
            WHERE p.polrelid IN ('public.recetas'::regclass, 'public.receta_items'::regclass)
              AND p.polcmd IN ('a','*')
              AND (0 = ANY(p.polroles) OR 'authenticated'::regrole::oid = ANY(p.polroles)) LOOP
    v := v||E'\n queda policy '||r.polcmd||' '||r.relname||'.'||r.polname;
  END LOOP;

  -- el conjunto COMPLETO de policies de las dos tablas, exacto (nombre|cmd|roles|USING|CHECK)
  esperado := concat_ws(E'\n',
    'receta_items|Admin clinica ve items de recetas de su clinica|r|authenticated|COALESCE(private.receta_de_mi_clinica(receta_id), false)|',
    'receta_items|Paciente ve items de sus recetas|r|public|(receta_id IN ( SELECT r.id'||E'\n'||'   FROM (public.recetas r'||E'\n'||'     JOIN public.pacientes p ON ((r.paciente_id = p.id)))'||E'\n'||'  WHERE (p.auth_user_id = auth.uid())))|',
    'receta_items|receta_items_medico_select|r|authenticated|(receta_id IN ( SELECT r.id'||E'\n'||'   FROM public.recetas r'||E'\n'||'  WHERE (r.medico_id = auth.uid())))|',
    'receta_items|receta_items_superadmin_delete|d|authenticated|private.tiene_rol(ARRAY[''super_admin''::text])|',
    'receta_items|receta_items_superadmin_select|r|authenticated|private.tiene_rol(ARRAY[''super_admin''::text])|',
    'receta_items|receta_items_superadmin_update|w|authenticated|private.tiene_rol(ARRAY[''super_admin''::text])|private.tiene_rol(ARRAY[''super_admin''::text])',
    'recetas|Admin clinica ve recetas de su clinica|r|authenticated|COALESCE(private.medico_es_de_mi_clinica(medico_id), false)|',
    'recetas|Admin ve recetas de su pais|r|public|((public.get_auth_user_rol() = ''super_admin''::text) OR ((public.get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = public.get_auth_user_pais_id())))|',
    'recetas|Paciente ve sus recetas|r|public|(paciente_id IN ( SELECT pacientes.id'||E'\n'||'   FROM public.pacientes'||E'\n'||'  WHERE (pacientes.auth_user_id = auth.uid())))|',
    'recetas|recetas_select|r|authenticated|(auth.uid() = medico_id)|');
  SELECT string_agg(c.relname||'|'||p.polname||'|'||p.polcmd::text||'|'
           ||(SELECT string_agg(CASE WHEN x = 0 THEN 'public' ELSE pg_catalog.pg_get_userbyid(x) END, ',' ORDER BY 1) FROM pg_catalog.unnest(p.polroles) x)
           ||'|'||COALESCE(pg_catalog.pg_get_expr(p.polqual, p.polrelid),'')
           ||'|'||COALESCE(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid),''), E'\n' ORDER BY c.relname, p.polname)
    INTO obtenido
    FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
   WHERE p.polrelid IN ('public.recetas'::regclass, 'public.receta_items'::regclass)
     AND p.polpermissive;
  IF obtenido IS DISTINCT FROM esperado THEN
    v := v||E'\n policies distintas de lo definido:\n--- obtenido ---\n'||COALESCE(obtenido,'NULL'); END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid IN ('public.recetas'::regclass, 'public.receta_items'::regclass)
              AND NOT p.polpermissive) THEN
    v := v||E'\n aparecio una policy RESTRICTIVE'; END IF;

  -- emitir_receta intacta
  SELECT md5(p.prosrc)||'|'||pg_catalog.pg_get_userbyid(p.proowner)||'|'||p.prosecdef||'|'
         ||ARRAY(SELECT a::text FROM pg_catalog.unnest(p.proacl) a ORDER BY 1)::text
    INTO obtenido FROM pg_catalog.pg_proc p WHERE p.oid = f;
  IF obtenido IS DISTINCT FROM
     '74d7013aeea17659bbafb84d780d644b|postgres|true|{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}' THEN
    v := v||E'\n emitir_receta cambio: '||COALESCE(obtenido,'NULL'); END IF;

  PERFORM set_config('search_path', sp, true);
  IF v <> '' THEN RAISE EXCEPTION 'MIG328 AUTOCHEQUEO FALLA:%', v; END IF;
END $ac$;

COMMIT;
