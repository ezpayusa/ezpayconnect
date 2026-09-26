-- ############################################################################################
-- 334 ROLLBACK - vuelve expediente_notas / signos_vitales / citas al estado pre-334
-- ############################################################################################
-- Quita: los 3 triggers, las 3 funciones privadas, la RPC corregir_nota_consulta, la tabla
-- expediente_notas_revisiones, las columnas updated_at/updated_by/cerrada_at/corregida_at y las
-- policies exp_superadmin_select/_insert/_update. Restaura: exp_superadmin_all (texto exacto), la
-- FK de signos_vitales.consulta_id con ON DELETE CASCADE y DELETE/TRUNCATE/TRIGGER/REFERENCES/
-- MAINTAIN de authenticated en expediente_notas.
--
-- NO RESTAURA (costo de volver atras): las revisiones acumuladas se pierden con el DROP de la tabla,
-- y las notas corregidas quedan con su ultima version. Si hay revisiones, exportarlas ANTES.
-- ############################################################################################

BEGIN;

DROP TRIGGER trg_cerrar_nota_al_completar ON public.citas;
DROP TRIGGER trg_expediente_notas_guardia ON public.expediente_notas;
DROP TRIGGER trg_exp_rev_inmutable ON public.expediente_notas_revisiones;

DROP FUNCTION public.corregir_nota_consulta(integer, text, text, text, text, text, text, text);
DROP TABLE public.expediente_notas_revisiones;
DROP FUNCTION private.expediente_notas_guardia();
DROP FUNCTION private.cerrar_nota_al_completar();
DROP FUNCTION private.revision_nota_inmutable();

ALTER TABLE public.expediente_notas
  DROP COLUMN updated_at,
  DROP COLUMN updated_by,
  DROP COLUMN cerrada_at,
  DROP COLUMN corregida_at;

DROP POLICY exp_superadmin_select ON public.expediente_notas;
DROP POLICY exp_superadmin_insert ON public.expediente_notas;
DROP POLICY exp_superadmin_update ON public.expediente_notas;
CREATE POLICY exp_superadmin_all ON public.expediente_notas
  AS PERMISSIVE FOR ALL TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));

ALTER TABLE public.signos_vitales DROP CONSTRAINT signos_vitales_consulta_id_fkey;
ALTER TABLE public.signos_vitales ADD CONSTRAINT signos_vitales_consulta_id_fkey
  FOREIGN KEY (consulta_id) REFERENCES public.expediente_notas(id) ON DELETE CASCADE;

GRANT DELETE, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON public.expediente_notas TO authenticated;

DO $chk$
DECLARE bad text := ''; x text; r record;
BEGIN
  -- objetos de la 334, ausentes
  IF to_regclass('public.expediente_notas_revisiones') IS NOT NULL THEN bad := bad||'tabla de revisiones sigue; '; END IF;
  SELECT string_agg(p.oid::regprocedure::text, ',') INTO x FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname = 'public' AND p.proname = 'corregir_nota_consulta')
      OR (ns.nspname = 'private' AND p.proname IN ('expediente_notas_guardia','cerrar_nota_al_completar','revision_nota_inmutable'));
  IF x IS NOT NULL THEN bad := bad||'funciones siguen: '||x||'; '; END IF;
  SELECT string_agg(attname, ',') INTO x FROM pg_attribute WHERE attrelid = 'public.expediente_notas'::regclass
     AND attname IN ('updated_at','updated_by','cerrada_at','corregida_at') AND NOT attisdropped;
  IF x IS NOT NULL THEN bad := bad||'columnas siguen: '||x||'; '; END IF;
  -- triggers: los previos, exactos
  SELECT string_agg(tgname, ',' ORDER BY tgname COLLATE "C") INTO x FROM pg_trigger WHERE tgrelid = 'public.expediente_notas'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_calcular_imc_expediente' THEN bad := bad||'triggers notas='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(tgname, ',' ORDER BY tgname COLLATE "C") INTO x FROM pg_trigger WHERE tgrelid = 'public.citas'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_exigir_nota_al_completar,trg_historial_cita,trg_otorgar_puntos_referido,trg_reset_notif_cancel' THEN
    bad := bad||'triggers citas='||COALESCE(x,'-')||'; '; END IF;
  -- policies: el conjunto previo y exp_superadmin_all con su texto
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas';
  IF x IS DISTINCT FROM 'Admin clinica ve expediente de su clinica:SELECT,exp_insert_medico:INSERT,exp_select_medico:SELECT,exp_select_paciente:SELECT,exp_superadmin_all:ALL,exp_update_medico:UPDATE' THEN
    bad := bad||'policies notas='||COALESCE(x,'-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas'
       AND policyname = 'exp_superadmin_all' AND cmd = 'ALL' AND roles::text = '{authenticated}'
       AND qual = 'private.tiene_rol(ARRAY[''super_admin''::text])' AND with_check = 'private.tiene_rol(ARRAY[''super_admin''::text])') THEN
    bad := bad||'exp_superadmin_all distinta; '; END IF;
  -- grants: la ACL previa exacta
  SELECT relacl::text INTO x FROM pg_class WHERE oid = 'public.expediente_notas'::regclass;
  IF x IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL notas='||COALESCE(x,'-')||'; '; END IF;
  -- FK de signos vitales, CASCADE
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'signos_vitales_consulta_id_fkey' AND conrelid = 'public.signos_vitales'::regclass
       AND confrelid = 'public.expediente_notas'::regclass AND confdeltype = 'c') THEN bad := bad||'FK signos no CASCADE; '; END IF;
  -- las 7 funciones que la 334 no toca
  FOR r IN SELECT * FROM (VALUES
      ('private.exigir_nota_al_completar()',          '102adac580dfb08ed65158f065a98b3e'),
      ('private.cita_tiene_nota(bigint)',             '6ea1318eddf06bb33db2545c9ab2233a'),
      ('public.calcular_imc_signos_vitales()',        '1b9ad49a5cd1464c54d9a211e5763532'),
      ('public.contexto_ia_paciente(bigint)',         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097'),
      ('public.actualizar_estado_cita(bigint,text)',  '3ff6976362482995bd17cb2322bcc082'),
      ('private.exigir_empresa_activa()',             'd62cc5a3c6edf0aaf48488e59a8d1e9b')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK334 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
