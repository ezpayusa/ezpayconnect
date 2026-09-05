-- ############################################################################################
-- 279 — Borrado de material comercial: RPC con gate + DELETE de storage acotado a huerfanos
-- ############################################################################################
-- Contrato aprobado por Oscar. Dos objetos, nada mas:
--   1. public.borrar_material_comercial(uuid)  — hard delete de la fila, gateado por pais.
--   2. material_com_storage_delete             — DELETE sobre el bucket 'material-comercial',
--      acotado a objetos que NO figuran en material_comercial (o sea: huerfanos).
-- Mismo molde que la 276 para `visitas-comerciales`: primero desaparece la fila, y recien
-- entonces el objeto pasa a ser borrable. Mientras la fila exista, el objeto es intocable.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.borrar_material_comercial(p_material_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_pais uuid;
BEGIN
  -- LA LINEA QUE ATA: el pais sale de la FILA, no de un parametro. Fila inexistente -> v_pais
  -- NULL -> puede_admin_pais(NULL) da false dentro del COALESCE, asi que "no existe" y "no podes"
  -- devuelven lo mismo. Es el trade-off aceptado: no se filtra existencia.
  SELECT m.pais_id INTO v_pais FROM public.material_comercial m WHERE m.id = p_material_id;

  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.material_comercial WHERE id = p_material_id;
END
$function$;

-- Higiene de privilegios, igual que en 272-278: toda funcion nueva en public nace con EXECUTE
-- para PUBLIC. El REVOKE va PRIMERO y solo, el GRANT despues.
REVOKE ALL ON FUNCTION public.borrar_material_comercial(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.borrar_material_comercial(uuid) TO authenticated;

DROP POLICY IF EXISTS material_com_storage_delete ON storage.objects;
CREATE POLICY material_com_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'material-comercial'
    AND COALESCE(private.puede_admin_pais(private.safe_uuid(split_part(name, '/', 1))), false)
    AND NOT EXISTS (
      SELECT 1 FROM public.material_comercial m WHERE m.storage_path = storage.objects.name)
  );
