-- ############################################################################################
-- 320 - pertenencia en recetas_insert + scope de admin_pais a solo-lectura en recetas
-- ############################################################################################
-- (1) La policy recetas_insert exigia SOLO auth.uid() = medico_id. Un INSERT directo por PostgREST
--     (supabase.from('recetas').insert(...)) le pasaba por al lado al gate PR009 que la mig 316 puso
--     en la RPC emitir_receta: un medico podia crear una receta para CUALQUIER paciente, sin relacion.
-- (2) Esa receta forjada NO era dispensable -- recetas_avanzadas tiene INSERT cerrado para
--     authenticated y el circuito de despacho busca por recetas_avanzadas.dispatch_token -- pero SI
--     era visible al paciente (policy "Paciente ve sus recetas") y figuraba como 'activa'. Es un
--     problema de INTEGRIDAD (falsear una receta en la historia del paciente), no de dispensacion.
-- (3) La policy ALL "Admin ve recetas de su pais" (USING sin WITH CHECK) dejaba a un admin_pais
--     CREAR, ALTERAR y BORRAR recetas reales de su pais (el USING funciona como check de
--     INSERT/UPDATE/DELETE). Ningun flujo legitimo hace eso: censado en src/ (unico escritor es
--     useRecetas del medico) y en edges (0 escritores). Se reduce la policy a SELECT.
-- (4) emitir_receta NO se ve afectada: corre como owner postgres con rolbypassrls=true y recetas no
--     tiene force RLS (relforcerowsecurity=false), asi que la RPC bypassea RLS. Medido, no supuesto.
--     El flag emision_flag('emitir_receta_rpc') esta en TRUE: el front emite por la RPC.
-- ############################################################################################

DO $snap$ BEGIN
  PERFORM set_config('mig320.recetas_antes',  (SELECT count(*)::text FROM public.recetas), false);
  PERFORM set_config('mig320.items_antes',    (SELECT count(*)::text FROM public.receta_items), false);
END $snap$;

-- ===== PARTE (i): pertenencia en el INSERT directo =====
-- Mismo predicado que la mig 316 (PR009), a proposito: si algun dia se apaga
-- emision_flag('emitir_receta_rpc'), la rama de INSERT directo (useRecetas, backout) hereda el mismo
-- gate en vez de ser una puerta trasera. Espeja la RLS de pacientes para el rol medico.
ALTER POLICY recetas_insert ON public.recetas
  WITH CHECK (
    (auth.uid() = medico_id)
    AND (
         private.medico_atiende_paciente(paciente_id)
      OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = paciente_id AND pa.medico_id = auth.uid())
    )
  );

-- ===== PARTE (ii): admin_pais/super_admin solo LEEN recetas =====
-- Un "anular receta" de admin, si alguna vez se necesita, va por RPC SECURITY DEFINER (O6
-- anular_receta del backlog), no reabriendo esta policy a escritura.
DROP POLICY "Admin ve recetas de su pais" ON public.recetas;
CREATE POLICY "Admin ve recetas de su pais" ON public.recetas
  FOR SELECT TO public
  USING (((get_auth_user_rol() = 'super_admin'::text) OR ((get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = get_auth_user_pais_id()))));

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
DO $ac$
DECLARE
  v_esperado_using text := '((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))';
  v_admin_wr int;
  v_ins_check text;
  v_sel_using text;
  v_rec_a int := current_setting('mig320.recetas_antes')::int;
  v_it_a  int := current_setting('mig320.items_antes')::int;
  v_rec_h int := (SELECT count(*) FROM public.recetas);
  v_it_h  int := (SELECT count(*) FROM public.receta_items);
BEGIN
  -- (a) ninguna policy de ESCRITURA (a/w/d/*) sobre recetas habilita admin_pais
  SELECT count(*) INTO v_admin_wr
    FROM pg_policy
   WHERE polrelid='public.recetas'::regclass
     AND polcmd IN ('a','w','d','*')
     AND (COALESCE(pg_get_expr(polqual,polrelid),'')||' '||COALESCE(pg_get_expr(polwithcheck,polrelid),'')) LIKE '%admin_pais%';
  IF v_admin_wr <> 0 THEN
    RAISE EXCEPTION 'MIG320: quedo % policy(s) de escritura sobre recetas que habilitan admin_pais', v_admin_wr;
  END IF;

  -- (b) el USING de la nueva SELECT = USING original de la ALL
  SELECT pg_get_expr(polqual,polrelid) INTO v_sel_using
    FROM pg_policy WHERE polrelid='public.recetas'::regclass AND polname='Admin ve recetas de su pais';
  IF v_sel_using IS DISTINCT FROM v_esperado_using THEN
    RAISE EXCEPTION 'MIG320: el USING de la SELECT difiere del original: %', COALESCE(v_sel_using,'(ausente)');
  END IF;
  -- y quedo como SELECT (no ALL)
  IF (SELECT polcmd::text FROM pg_policy WHERE polrelid='public.recetas'::regclass AND polname='Admin ve recetas de su pais') <> 'r' THEN
    RAISE EXCEPTION 'MIG320: "Admin ve recetas de su pais" no quedo como SELECT';
  END IF;

  -- (c) recetas_insert referencia medico_atiende_paciente
  SELECT pg_get_expr(polwithcheck,polrelid) INTO v_ins_check
    FROM pg_policy WHERE polrelid='public.recetas'::regclass AND polname='recetas_insert';
  IF v_ins_check NOT LIKE '%medico_atiende_paciente%' THEN
    RAISE EXCEPTION 'MIG320: recetas_insert no referencia medico_atiende_paciente: %', COALESCE(v_ins_check,'(ausente)');
  END IF;

  -- (d) conteos intactos
  IF v_rec_h <> v_rec_a OR v_it_h <> v_it_a THEN
    RAISE EXCEPTION 'MIG320: conteos cambiaron (recetas %->%, items %->%)', v_rec_a, v_rec_h, v_it_a, v_it_h;
  END IF;

  RAISE NOTICE 'MIG320 OK: pertenencia en recetas_insert; admin_pais solo-lectura; recetas=% items=% intactos', v_rec_h, v_it_h;
END $ac$;
