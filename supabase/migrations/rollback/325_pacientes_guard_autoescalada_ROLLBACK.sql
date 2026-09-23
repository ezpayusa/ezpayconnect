-- ############################################################################################
-- ROLLBACK Migracion 325 - quita el guard anti-auto-escalada y restaura la policy ORIGINAL.
-- ############################################################################################
-- Policy ORIGINAL capturada literal con pg_policies el 23-sep-2026 (antes de la mig 325):
--   policyname = 'Paciente actualiza su perfil'
--   cmd        = UPDATE
--   roles      = {public}         (sin clausula TO -> PUBLIC)
--   qual       = (auth_user_id = auth.uid())
--   with_check = NULL             (usaba el USING como check)
-- ############################################################################################

DROP TRIGGER IF EXISTS trg_pacientes_guard_update ON public.pacientes;
DROP FUNCTION IF EXISTS private.pacientes_guard_update();

DROP POLICY IF EXISTS "Paciente actualiza su perfil" ON public.pacientes;
CREATE POLICY "Paciente actualiza su perfil" ON public.pacientes
  FOR UPDATE
  USING (auth_user_id = auth.uid());

-- Autochequeo: la firma de la policy restaurada debe coincidir (md5) con la de antes.
DO $ac$
DECLARE
  v_sig_restored text;
  v_sig_expected text := '{public}|(auth_user_id = auth.uid())|<null>';
  v_tg  int;
  v_fn  int;
BEGIN
  SELECT (pol.roles::text || '|' || COALESCE(pol.qual,'<null>') || '|' || COALESCE(pol.with_check,'<null>'))
    INTO v_sig_restored
    FROM pg_policies pol
   WHERE pol.schemaname='public' AND pol.tablename='pacientes' AND pol.policyname='Paciente actualiza su perfil';

  IF v_sig_restored IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK325: la policy no quedo creada';
  END IF;
  IF md5(v_sig_restored) <> md5(v_sig_expected) THEN
    RAISE EXCEPTION 'ROLLBACK325: policy restaurada != original. restored=[%] expected=[%]', v_sig_restored, v_sig_expected;
  END IF;

  -- El trigger y la funcion no deben quedar.
  SELECT count(*) INTO v_tg FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace
    WHERE ns.nspname='public' AND c.relname='pacientes' AND t.tgname='trg_pacientes_guard_update' AND NOT t.tgisinternal;
  SELECT count(*) INTO v_fn FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='private' AND p.proname='pacientes_guard_update';
  IF v_tg <> 0 THEN RAISE EXCEPTION 'ROLLBACK325: el trigger sigue presente'; END IF;
  IF v_fn <> 0 THEN RAISE EXCEPTION 'ROLLBACK325: la funcion sigue presente'; END IF;
END $ac$;
