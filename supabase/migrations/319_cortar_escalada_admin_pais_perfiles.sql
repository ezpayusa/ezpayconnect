-- ############################################################################################
-- 319 - cortar la escalada admin_pais -> super_admin en perfiles
-- ############################################################################################
-- La policy "Admin ve perfiles de su pais" es cmd=ALL con USING y SIN WITH CHECK. En ese caso
-- Postgres usa el USING como check de INSERT/UPDATE/DELETE. Su USING solo exige rol super_admin, o
-- admin_pais con pais_id coincidente -- NO restringe el 'rol' de la fila nueva. Cadena de escalada
-- MEDIDA end-to-end:
--   1. signup publico (habilitado): el atacante crea una cuenta auth.users que controla.
--      authenticated NO tiene grants sobre auth.users; el ancla es el signup, no un INSERT directo.
--   2. como admin_pais, INSERT en perfiles de una fila (id = ese uid, pais_id = su pais,
--      rol = 'super_admin'): la policy ALL lo ACEPTA porque solo mira el pais, no el rol.
--   3. login con esa cuenta: get_auth_user_rol() = 'super_admin' -> super_admin GLOBAL.
--      El pais_id NO acota a un super_admin. Un solo admin_pais = toma total.
--
-- FIX: se saca el INSERT del alcance de esa policy. Se reemplaza la ALL por tres policies EXPLICITAS
-- (SELECT/UPDATE/DELETE) con EL MISMO predicado (traido textual de la base), sin ninguna de INSERT.
-- El comportamiento de lectura/actualizacion/borrado del admin_pais queda IDENTICO; solo desaparece
-- la capacidad de INSERT que la ALL le concedia de rebote.
--
-- El INSERT de perfiles queda cubierto UNICAMENTE por "Admins pueden insertar perfiles"
-- (CHECK private.tiene_rol(ARRAY['super_admin'])): solo super_admin activo. admin_pais ya no inserta.
-- El cambio de rol/pais/activo por UPDATE ya lo frena el trigger perfiles_guard_rol_update (BEFORE
-- UPDATE), independiente de esta policy.
-- ############################################################################################

DO $snap$ BEGIN
  PERFORM set_config('mig319.perfiles_antes', (SELECT count(*)::text FROM public.perfiles), false);
END $snap$;

-- fuera la ALL (concedia INSERT de rebote)
DROP POLICY "Admin ve perfiles de su pais" ON public.perfiles;

-- mismo predicado textual que tenia la ALL, ahora acotado a SELECT/UPDATE/DELETE
CREATE POLICY "Admin lee perfiles de su pais" ON public.perfiles
  FOR SELECT TO public
  USING (((get_auth_user_rol() = 'super_admin'::text) OR ((get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = get_auth_user_pais_id()))));

CREATE POLICY "Admin actualiza perfiles de su pais" ON public.perfiles
  FOR UPDATE TO public
  USING (((get_auth_user_rol() = 'super_admin'::text) OR ((get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = get_auth_user_pais_id()))))
  WITH CHECK (((get_auth_user_rol() = 'super_admin'::text) OR ((get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = get_auth_user_pais_id()))));

CREATE POLICY "Admin borra perfiles de su pais" ON public.perfiles
  FOR DELETE TO public
  USING (((get_auth_user_rol() = 'super_admin'::text) OR ((get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = get_auth_user_pais_id()))));

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
DO $ac$
DECLARE
  v_esperado text := '((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))';
  v_admin_ins int;
  v_admins_ok int;
  v_u text; v_d text; v_s text;
  v_antes int := current_setting('mig319.perfiles_antes')::int;
  v_ahora int := (SELECT count(*) FROM public.perfiles);
BEGIN
  -- (a) ninguna policy cmd IN ('a','*') sobre perfiles habilita a admin_pais
  SELECT count(*) INTO v_admin_ins
    FROM pg_policy
   WHERE polrelid='public.perfiles'::regclass
     AND polcmd IN ('a','*')
     AND (COALESCE(pg_get_expr(polqual,polrelid),'')||' '||COALESCE(pg_get_expr(polwithcheck,polrelid),'')) LIKE '%admin_pais%';
  IF v_admin_ins <> 0 THEN
    RAISE EXCEPTION 'MIG319: quedo % policy(s) INSERT/ALL que habilitan admin_pais', v_admin_ins;
  END IF;

  -- (b) el predicado de SELECT/UPDATE/DELETE no cambio respecto del USING original
  SELECT pg_get_expr(polqual,polrelid) INTO v_s FROM pg_policy WHERE polrelid='public.perfiles'::regclass AND polname='Admin lee perfiles de su pais';
  SELECT pg_get_expr(polqual,polrelid) INTO v_u FROM pg_policy WHERE polrelid='public.perfiles'::regclass AND polname='Admin actualiza perfiles de su pais';
  SELECT pg_get_expr(polqual,polrelid) INTO v_d FROM pg_policy WHERE polrelid='public.perfiles'::regclass AND polname='Admin borra perfiles de su pais';
  IF v_s IS DISTINCT FROM v_esperado OR v_u IS DISTINCT FROM v_esperado OR v_d IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'MIG319: el predicado SELECT/UPDATE/DELETE difiere del USING original. s=% u=% d=%', v_s, v_u, v_d;
  END IF;
  -- y el WITH CHECK del UPDATE tambien = predicado original
  IF (SELECT pg_get_expr(polwithcheck,polrelid) FROM pg_policy WHERE polrelid='public.perfiles'::regclass AND polname='Admin actualiza perfiles de su pais') IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'MIG319: el WITH CHECK del UPDATE difiere del predicado original';
  END IF;

  -- (c) el conteo de filas de perfiles no cambio
  IF v_ahora <> v_antes THEN
    RAISE EXCEPTION 'MIG319: perfiles paso de % a %', v_antes, v_ahora;
  END IF;

  -- (d) "Admins pueden insertar perfiles" sigue existiendo y usando tiene_rol
  SELECT count(*) INTO v_admins_ok
    FROM pg_policy
   WHERE polrelid='public.perfiles'::regclass AND polname='Admins pueden insertar perfiles'
     AND COALESCE(pg_get_expr(polwithcheck,polrelid),'') LIKE '%tiene_rol%';
  IF v_admins_ok <> 1 THEN
    RAISE EXCEPTION 'MIG319: "Admins pueden insertar perfiles" ausente o sin tiene_rol (encontradas=%)', v_admins_ok;
  END IF;

  RAISE NOTICE 'MIG319 OK: ALL reemplazada por SELECT/UPDATE/DELETE (mismo predicado), sin INSERT para admin_pais; INSERT solo super_admin; perfiles intactos (%)', v_ahora;
END $ac$;
