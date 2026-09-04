-- ############################################################################################
-- 278 — "Desactivado" deja de ser un adorno: el filtro por `activo` baja a la DB
-- ############################################################################################
-- QUÉ ESTABA MAL
-- --------------
-- La 274 dejó la policy de SELECT de `material_comercial` así:
--     COALESCE(private.puede_admin_pais(pais_id), false) OR pais_id = private.mi_pais()
-- Sin `activo`. Es decir: un asesor recibe TODO el material de su país, incluido el desactivado, y
-- la única forma de que no lo vea sería filtrarlo en el cliente — que es donde no vive ningún
-- control. Mismo error de forma que las coordenadas de la 277: el dato viaja igual y se lee con
-- las devtools abiertas.
--
-- Y la policy de storage tenía el mismo agujero: el objeto seguía siendo legible por cualquiera
-- del país que conociera el path, aunque la fila estuviera desactivada.
--
-- LA REGLA, AHORA EN LA BASE
--   admin del país / super_admin : ve TODO, activo e inactivo (lo necesita para reactivarlo)
--   cualquier otro del país      : sólo lo ACTIVO
-- Desactivar no borra — sigue siendo reversible — pero deja de ser visible de verdad, no de mentira.
--
-- No usa errcode nuevo. El próximo PA libre sigue siendo PA026.
-- ############################################################################################

DROP POLICY IF EXISTS material_comercial_select ON public.material_comercial;
CREATE POLICY material_comercial_select ON public.material_comercial
  FOR SELECT TO authenticated
  USING (
    COALESCE(private.puede_admin_pais(pais_id), false)
    OR (pais_id = private.mi_pais() AND activo)
  );

COMMENT ON POLICY material_comercial_select ON public.material_comercial IS
'El admin del país ve todo (necesita ver lo desactivado para reactivarlo); el resto del país ve
sólo lo activo. El filtro está ACÁ y no en el cliente a propósito: en el cliente el dato igual
viaja, y "no lo pinto" no es lo mismo que "no lo puede leer".';

-- Storage: que el objeto siga la suerte de la fila. Sin esto, alguien que se guardó el path podía
-- seguir descargando un material desactivado.
DROP POLICY IF EXISTS material_com_storage_select ON storage.objects;
CREATE POLICY material_com_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'material-comercial'
    AND (
      COALESCE(private.puede_admin_pais(private.safe_uuid(split_part(name, '/', 1))), false)
      OR EXISTS (
        SELECT 1 FROM public.material_comercial m
         WHERE m.storage_path = storage.objects.name
           AND m.activo
           AND m.pais_id = private.mi_pais())
    )
  );

-- Alta y baja del material: la escritura sigue siendo exclusiva de RPCs con gate.
CREATE OR REPLACE FUNCTION public.activar_material_comercial(p_material_id uuid, p_activo boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid;
BEGIN
  -- LA LINEA QUE ATA: el país sale de la FILA, no de un parámetro. Fila inexistente -> NULL ->
  -- puede_admin_pais(NULL) da false dentro del COALESCE, y "no existe" no se distingue de
  -- "no podés".
  SELECT m.pais_id INTO v_pais FROM public.material_comercial m WHERE m.id = p_material_id;
  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  UPDATE public.material_comercial
     SET activo = COALESCE(p_activo, false), updated_at = now()
   WHERE id = p_material_id;
END
$function$;

REVOKE ALL ON FUNCTION public.activar_material_comercial(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activar_material_comercial(uuid,boolean) TO authenticated;

COMMENT ON FUNCTION public.activar_material_comercial(uuid,boolean) IS
'Activa o desactiva material. Sólo el admin del país del material y super_admin. Desactivar NO
borra: la fila y el objeto quedan, y el admin los sigue viendo. Borrar material —igual que borrar
adjuntos de visita— es una decisión de producto pendiente y no tiene RPC.';

DO $$
DECLARE v_qual text;
BEGIN
  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname='public' AND tablename='material_comercial' AND policyname='material_comercial_select';
  IF v_qual IS NULL OR v_qual NOT LIKE '%activo%' THEN
    RAISE EXCEPTION 'la policy de material no filtra por activo';
  END IF;
  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects' AND policyname='material_com_storage_select';
  IF v_qual IS NULL OR v_qual NOT LIKE '%material_comercial%' THEN
    RAISE EXCEPTION 'la policy de storage de material no se ata a la fila';
  END IF;
  IF has_function_privilege('anon','public.activar_material_comercial(uuid,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar activar_material_comercial';
  END IF;
END $$;
