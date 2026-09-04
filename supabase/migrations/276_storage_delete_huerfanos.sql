-- ############################################################################################
-- 276 — DELETE de storage acotado a objetos HUÉRFANOS (los que nunca se registraron)
-- ############################################################################################
-- EL PROBLEMA
-- -----------
-- Subir un adjunto son dos pasos: el objeto va al bucket y después `registrar_adjunto_visita`
-- crea la fila. Si el segundo falla —PA023 por un path mal armado, o simplemente se corta la
-- red— el objeto queda en el bucket sin fila que lo nombre: un HUÉRFANO que nadie ve en la UI y
-- nadie limpia. La compensación correcta es borrarlo en el mismo catch.
--
-- PERO la 274 no dejó policy de DELETE sobre `visitas-comerciales`, a propósito: si un asesor
-- puede borrar su propia evidencia es una decisión de producto que todavía no está tomada.
-- Agregar un DELETE amplio para poder compensar sería tomarla por la ventana.
--
-- LA SALIDA
-- ---------
-- Un DELETE que sólo alcanza a objetos que NO están en `visita_adjuntos`. Es decir: se puede
-- limpiar lo que nunca llegó a ser evidencia, y es ESTRUCTURALMENTE IMPOSIBLE borrar lo que sí.
-- La decisión de Oscar queda intacta — el día que diga "sí, que puedan borrar", eso es otra
-- policy y otra migración.
--
-- No usa errcode nuevo: es una policy. El próximo PA libre sigue siendo PA026.
-- ############################################################################################

DROP POLICY IF EXISTS visitas_com_storage_delete ON storage.objects;
CREATE POLICY visitas_com_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'visitas-comerciales'
    -- tiene que ser un objeto del directorio de UNA VISITA PROPIA...
    AND EXISTS (
      SELECT 1 FROM public.visitas_comerciales v
       WHERE v.id = private.safe_uuid(split_part(name, '/', 2))
         AND v.asesor_id = auth.uid())
    -- ...y que NUNCA se haya registrado. Un adjunto que llegó a `visita_adjuntos` es evidencia y
    -- no lo borra nadie por esta vía.
    AND NOT EXISTS (
      SELECT 1 FROM public.visita_adjuntos a WHERE a.storage_path = storage.objects.name)
  );

COMMENT ON POLICY visitas_com_storage_delete ON storage.objects IS
'Limpieza de huérfanos, NO borrado de evidencia. Alcanza sólo a objetos del directorio de una
visita propia que no figuran en visita_adjuntos — o sea, subidas cuyo registro falló. Que un asesor
pueda borrar evidencia YA REGISTRADA es una decisión de producto pendiente; esta policy la deja
abierta a propósito, porque el NOT EXISTS la vuelve imposible por este camino.';

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects' AND policyname='visitas_com_storage_delete';
  IF v_n <> 1 THEN RAISE EXCEPTION 'la policy de DELETE no quedó creada'; END IF;
END $$;
