-- ############################################################################################
-- 318 - cerrar el auto-registro publico de perfiles
-- ############################################################################################
-- La policy "Insertar propio perfil" (INSERT, PUBLIC) dejaba a CUALQUIER usuario autenticado crear
-- su propia fila en public.perfiles ELIGIENDO su rol: el CHECK era
--   auth.uid() = id AND rol <> ALL(ARRAY['super_admin','admin_pais','admin','ezpay_admin','soporte','vendedor'])
-- o sea un blocklist de 6 roles que ACEPTABA los otros 9 (incluidos admin_clinica, medico, gerente,
-- enfermera, etc.). Combinado con RPCs SOLO-ROL como emitir_receta, era una escalada real.
--
-- Decision (Oscar): las altas de perfiles van SOLO por caminos gateados con service_role (edges
-- registrar-clinica-invitacion, registrar-medico-invitacion, crear-empleado, crear-staff-clinica,
-- que insertan con SB_SERVICE_ROLE_KEY y por lo tanto BYPASSEAN RLS) o por super_admin. El
-- auto-registro publico del front (AuthContext.register -> LoginPage) queda cerrado a nivel DB.
--
-- Dos cambios:
--   (B.2) DROP de "Insertar propio perfil".
--   (B.3) "Admins pueden insertar perfiles" pasa de un EXISTS directo sobre perfiles (que leia
--         perfiles.rol SIN mirar activo) a private.tiene_rol(ARRAY['super_admin']), heredando asi el
--         gate de activo que puso la mig 315 (tiene_rol -> rol_usuario -> activo IS TRUE). Mismo cmd
--         (INSERT), mismos roles (PUBLIC), mismo efecto salvo que un super_admin INACTIVO ya no pasa.
--
-- La policy ALL "Admin ve perfiles de su pais" (via get_auth_user_rol, activo-gated por 315) sigue
-- habilitando INSERT a super_admin/admin_pais: no es un camino publico y queda fuera de este cierre.
-- ############################################################################################

-- guardo el conteo previo para el autochequeo (el DDL de policies no debe tocar filas)
DO $snap$ BEGIN
  PERFORM set_config('mig318.perfiles_antes', (SELECT count(*)::text FROM public.perfiles), false);
END $snap$;

-- (B.2) cerrar el auto-registro publico
DROP POLICY IF EXISTS "Insertar propio perfil" ON public.perfiles;

-- (B.3) el gate de admins pasa por tiene_rol (hereda el gate de activo de la 315)
ALTER POLICY "Admins pueden insertar perfiles" ON public.perfiles
  WITH CHECK (private.tiene_rol(ARRAY['super_admin']));

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
DO $ac$
DECLARE
  v_self int;
  v_admin_ok int;
  v_total int;
  v_antes int := current_setting('mig318.perfiles_antes')::int;
  v_ahora int := (SELECT count(*) FROM public.perfiles);
BEGIN
  -- 1) ninguna policy que HABILITE insertar (INSERT o ALL) deje al propio usuario elegir su rol
  SELECT count(*) INTO v_self
    FROM pg_policy
   WHERE polrelid = 'public.perfiles'::regclass
     AND polcmd IN ('a','*')
     AND (COALESCE(pg_get_expr(polwithcheck,polrelid),'') || ' ' || COALESCE(pg_get_expr(polqual,polrelid),''))
         ~ 'auth\.uid\(\)\s*=\s*id';
  IF v_self <> 0 THEN
    RAISE EXCEPTION 'MIG318: quedo % policy(s) de INSERT que dejan al propio usuario elegir rol', v_self;
  END IF;

  -- 2) la policy de admins referencia tiene_rol
  SELECT count(*) INTO v_admin_ok
    FROM pg_policy
   WHERE polrelid = 'public.perfiles'::regclass
     AND polname = 'Admins pueden insertar perfiles'
     AND COALESCE(pg_get_expr(polwithcheck,polrelid),'') LIKE '%tiene_rol%';
  IF v_admin_ok <> 1 THEN
    RAISE EXCEPTION 'MIG318: la policy de admins no referencia tiene_rol (encontradas=%)', v_admin_ok;
  END IF;

  -- 3) total de policies sobre perfiles = 4 (eran 5, se dropeo 1)
  SELECT count(*) INTO v_total FROM pg_policy WHERE polrelid = 'public.perfiles'::regclass;
  IF v_total <> 4 THEN
    RAISE EXCEPTION 'MIG318: total de policies sobre perfiles = % (esperado 4)', v_total;
  END IF;

  -- 4) el conteo de filas de perfiles no cambio
  IF v_ahora <> v_antes THEN
    RAISE EXCEPTION 'MIG318: perfiles paso de % a % (el DDL no debe tocar filas)', v_antes, v_ahora;
  END IF;

  RAISE NOTICE 'MIG318 OK: auto-registro cerrado, admins via tiene_rol, % policies, perfiles intactos (%)', v_total, v_ahora;
END $ac$;
