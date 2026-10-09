-- ############################################################################################
-- Rollback de la migracion 373 - quita public.completar_registro_proveedor()
-- ############################################################################################
-- Precondicion: la funcion existe y registrar_proveedor tiene la huella de la 327/373
--   (md5(prosrc) fae23eeeacb393328f774386ccd88479), que la 373 no toca.
-- Autochequeo: la funcion ya no existe y registrar_proveedor sigue con la misma huella.
-- Efecto de producto: con Confirm email ON el autorregistro de empresas vuelve a fallar en
--   registrar_proveedor ('Usuario no autenticado'). Revertir tambien el front que la llama.
-- ############################################################################################

BEGIN;

DO $$
DECLARE
  v text := '';
BEGIN
  IF to_regprocedure('public.completar_registro_proveedor()') IS NULL THEN
    v := v||E'\n public.completar_registro_proveedor() no existe';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor no tiene la huella esperada (md5 fae23eee...)';
  END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK373 PRECONDICION:%', v; END IF;
END
$$;

DROP FUNCTION public.completar_registro_proveedor();

DO $$
DECLARE
  v text := '';
BEGIN
  IF to_regprocedure('public.completar_registro_proveedor()') IS NOT NULL THEN
    v := v||E'\n public.completar_registro_proveedor() sigue existiendo';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor cambio de cuerpo';
  END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK373 AUTOCHEQUEO FALLA:%', v; END IF;
END
$$;

COMMIT;
