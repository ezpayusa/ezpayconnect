-- ############################################################################################
-- 315 — perfiles.activo pasa a ser un gate de verdad
-- ############################################################################################
-- `perfiles.activo` no gateaba NADA: era una columna que la UI mostraba y que nadie consultaba.
-- Las dos funciones que resuelven el rol en todo el sistema leian `rol` sin mirarla, asi que un
-- perfil desactivado conservaba todos sus privilegios (la mig 314 lo demostro con dos cuentas).
-- get_auth_user_rol() y private.rol_usuario() son GEMELAS -- dos implementaciones del MISMO
-- SELECT -- y private.tiene_rol() pasa por la segunda: 51 de las 72 policies afectadas entran por
-- ahi. Por eso se cambian LAS DOS o no se cambia ninguna; tocar una sola deja el agujero abierto.
--
-- RADIO MEDIDO: 72 policies sobre 46 tablas y 116 funciones de public/private dependen de estas
-- dos (directo o via tiene_rol / puede_admin_pais). Las probes de este bloque comparan, usuario
-- por usuario y tabla por tabla, que para quien esta ACTIVO no cambia absolutamente nada.
--
-- SE USA `activo IS TRUE`, NO `activo <> false`. La columna es nullable; con `IS TRUE` un NULL
-- queda FUERA (fail-closed), con `<> false` quedaria adentro. Hoy no hay NULLs y el paso 1.5 los
-- prohibe hacia adelante, pero el predicado se escribe fail-closed igual: el NOT NULL puede
-- caerse en un rollback futuro y el gate no deberia depender de el.
--
-- NO SE TOCA get_auth_user_pais_id(). Medido: 0 policies y 0 funciones lo usan sin un gate de rol
-- al lado (10 policies lo usan, las 10 con rol). Gatearlo seria redundante y agregaria una lectura
-- mas a puede_admin_pais(), que ya lo llama detras de un AND cuyo otro lado seria NULL.
-- ############################################################################################


-- ============================================================================================
-- 0) No puede haber NULLs al momento de correr (el paso (b) asume que activo es decidible)
-- ============================================================================================
DO $pre$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.perfiles WHERE activo IS NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '315: hay % perfiles con activo IS NULL — decidir su valor ANTES de poner el NOT NULL', v_n;
  END IF;
END $pre$;


-- ============================================================================================
-- 1) public.get_auth_user_rol()
-- ============================================================================================
-- Ademas del gate se endurece `search_path` de 'public' a '' (queda igual que su gemela). Por eso
-- `public.perfiles` va calificado; `auth.uid()` ya lo estaba.
CREATE OR REPLACE FUNCTION public.get_auth_user_rol()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT rol FROM public.perfiles WHERE id = auth.uid() AND activo IS TRUE;
$fn$;


-- ============================================================================================
-- 2) private.rol_usuario()
-- ============================================================================================
-- La gemela. Ya venia con search_path = ''. Es la que consume private.tiene_rol().
CREATE OR REPLACE FUNCTION private.rol_usuario()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT rol FROM public.perfiles WHERE id = auth.uid() AND activo IS TRUE;
$fn$;


-- ============================================================================================
-- 3) Que quede escrito en el catalogo que son gemelas
-- ============================================================================================
-- Mismo texto en las dos a proposito: quien abra cualquiera de ellas tiene que enterarse de que
-- existe la otra ANTES de editarla.
COMMENT ON FUNCTION public.get_auth_user_rol() IS
  'GEMELA de private.rol_usuario(): son dos implementaciones del MISMO SELECT sobre perfiles. '
  'Cualquier cambio va en LAS DOS o no va. private.tiene_rol() depende de private.rol_usuario(), '
  'y por ahi entran 51 de las 72 policies que resuelven rol. Gatean por activo IS TRUE (mig 315).';

COMMENT ON FUNCTION private.rol_usuario() IS
  'GEMELA de public.get_auth_user_rol(): son dos implementaciones del MISMO SELECT sobre perfiles. '
  'Cualquier cambio va en LAS DOS o no va. private.tiene_rol() depende de ESTA, '
  'y por ahi entran 51 de las 72 policies que resuelven rol. Gatean por activo IS TRUE (mig 315).';


-- ============================================================================================
-- 4) perfiles.activo deja de admitir NULL
-- ============================================================================================
-- La columna ya tiene DEFAULT true, asi que omitirla sigue funcionando. Lo que se prohibe es el
-- NULL EXPLICITO, que hoy es alcanzable: `authenticated` tiene INSERT sobre perfiles y la policy
-- "Insertar propio perfil" deja que cualquiera cree el suyo. Con el NOT NULL, un cliente que mande
-- activo:null recibe un error en vez de crear un perfil en un tercer estado que nadie modela.
ALTER TABLE public.perfiles ALTER COLUMN activo SET NOT NULL;
