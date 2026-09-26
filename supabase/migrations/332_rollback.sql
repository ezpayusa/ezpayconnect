-- ############################################################################################
-- 332 ROLLBACK - deja examenes / ordenes_examen / examenes_catalogo exactamente como antes de la 332
-- ############################################################################################
-- Restaura: UPDATE de tabla de authenticated en las tres tablas (quita los grants por columna),
-- la policy examenes_medico_update con su definicion previa, y quita el trigger de congelamiento,
-- las dos RPCs, el helper, el UNIQUE del catalogo y la columna examenes.catalogo_id (con su FK e
-- indice).
--
-- NO restaura / NO borra:
--   * Las ordenes creadas por crear_orden_examen_medico / crear_orden_examen_walkin entre el apply
--     y este rollback: son ordenes validas y se conservan. Pierden su catalogo_id (la columna se
--     borra); examenes.tipo conserva el nombre ordenado, asi que el front viejo las lee igual.
--   * El backfill: se va con la columna.
-- Orden de despliegue: con el front NUEVO publicado, este rollback lo deja sin RPCs; revertir el
-- front antes (o junto). Mientras la 333 no este aplicada, el front viejo funciona con o sin la 332.
-- ############################################################################################

BEGIN;

DROP TRIGGER trg_examenes_congelar_identidad ON public.examenes;
DROP FUNCTION private.examenes_congelar_identidad();
DROP FUNCTION public.crear_orden_examen_medico(bigint, uuid, jsonb, text);
DROP FUNCTION public.crear_orden_examen_walkin(jsonb, text, text, text, text, text);
DROP FUNCTION private.armar_items_orden_examen(uuid, jsonb);

REVOKE UPDATE (estado, fecha_resultado, resultados, archivo_url) ON public.examenes FROM authenticated;
GRANT UPDATE ON public.examenes TO authenticated;
REVOKE UPDATE (activo, categoria) ON public.examenes_catalogo FROM authenticated;
GRANT UPDATE ON public.examenes_catalogo TO authenticated;
GRANT UPDATE ON public.ordenes_examen TO authenticated;

CREATE POLICY examenes_medico_update ON public.examenes
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (medico_id = auth.uid())
  WITH CHECK ((medico_id = auth.uid()) AND (private.medico_atiende_paciente((paciente_id)::bigint) OR (EXISTS (
    SELECT 1 FROM public.pacientes pa WHERE ((pa.id = examenes.paciente_id) AND (pa.medico_id = auth.uid()))))));

DROP INDEX public.ux_examenes_catalogo_lab_nombre;
ALTER TABLE public.examenes DROP COLUMN catalogo_id;   -- arrastra examenes_catalogo_id_fkey e idx_examenes_catalogo

DO $chk$
DECLARE bad text := ''; x text; n int; r record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.examenes'::regclass AND attname = 'catalogo_id' AND NOT attisdropped) THEN
    bad := bad||'sigue examenes.catalogo_id; '; END IF;
  IF to_regclass('public.ux_examenes_catalogo_lab_nombre') IS NOT NULL OR to_regclass('public.idx_examenes_catalogo') IS NOT NULL THEN
    bad := bad||'quedan indices de la 332; '; END IF;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname, p.proname) IN (('public','crear_orden_examen_medico'), ('public','crear_orden_examen_walkin'),
                                      ('private','armar_items_orden_examen'), ('private','examenes_congelar_identidad'));
  IF n <> 0 THEN bad := bad||'quedan '||n||' funciones de la 332; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.examenes'::regclass AND tgname = 'trg_examenes_congelar_identidad') THEN
    bad := bad||'sigue el trigger; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.examenes', 'UPDATE') THEN bad := bad||'examenes sin UPDATE de tabla; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.examenes_catalogo', 'UPDATE') THEN bad := bad||'catalogo sin UPDATE de tabla; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.ordenes_examen', 'UPDATE') THEN bad := bad||'ordenes_examen sin UPDATE de tabla; '; END IF;
  SELECT count(*) INTO n FROM pg_attribute a, aclexplode(a.attacl) x2
   WHERE a.attrelid IN ('public.examenes'::regclass, 'public.examenes_catalogo'::regclass, 'public.ordenes_examen'::regclass)
     AND a.attacl IS NOT NULL;
  IF n <> 0 THEN bad := bad||'quedan '||n||' grants por columna; '; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'public' AND tablename = 'examenes' AND policyname = 'examenes_medico_update'
     AND cmd = 'UPDATE' AND permissive = 'PERMISSIVE' AND roles = '{authenticated}';
  IF n <> 1 THEN bad := bad||'examenes_medico_update='||n||'; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.liberar_examen_al_paciente(integer)', '7c980b20f713d0cf49e7235da30838e1'),
      ('public.liberar_orden_al_paciente(uuid)', '96a54d314911a439af77e426ebe46611'),
      ('public.revertir_liberacion_examen(integer)', '4a7f4912f3330543d2d7a47b2a06fbc6'),
      ('public.notificar_orden_lab(uuid)', '59fafc8572840548c27ad39a759cba47'),
      ('public.notificar_resultado_examen(integer)', '33a7a110c39574c5a40f7ca1495d2686'),
      ('public.paciente_examenes()', 'a14ea485045b28883d81a0dd9fe7cd83'),
      ('public.contexto_ia_paciente(bigint)', '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('private.puede_ver_examen(integer)', '2b8150875b99dfb5df9fdb3d8af62ae0'),
      ('public.registrar_examen_adjunto(integer,text,text)', '245fb6669aa3fb22f8e62ca40a8b3467')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK332 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
