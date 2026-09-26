-- ############################################################################################
-- 334 - P4 fase 1 de 3: notas clinicas con revisiones inmutables (expediente_notas)
-- ############################################################################################
-- Spec: docs/specs/P4-revisiones-inmutables-spec-2026-09-26.md (v2), seccion MIG 334. Decisiones
-- D1-D4, D9, D10, D12 y respuestas R1, R2, R4, R5 de Oscar; correcciones de revision C1-C5.
--
-- Antes (medido 26-sep): el front hace INSERT/UPDATE directo sobre expediente_notas; una nota se
-- podia reescribir despues de completada la cita, cambiar de paciente/cita/medico, y borrarse (con
-- CASCADE a signos_vitales). No habia historial.
--
-- Esta migracion:
--   (a) Columnas updated_at, updated_by, cerrada_at (se fija al completar la cita y NO se borra si
--       la cita vuelve atras), corregida_at (marca de correccion; R2: solo el dato).
--   (b) Backfill: updated_at = created_at; cerrada_at = now() para notas sin cita o con cita ya
--       completada (hoy 0 filas). Sin revisiones (D12).
--   (c) public.expediente_notas_revisiones: append-only, RLS + FORCE, una policy SELECT (autor,
--       tratantes, admin clinica, super_admin; el paciente no), la escribe solo el trigger.
--   (d) private.expediente_notas_guardia (BEFORE INSERT OR UPDATE):
--         INSERT: NT010 integridad nota<->cita (C2); created_at := now() (R5); nota sin cita o
--                 sobre cita ya completada nace cerrada (R1, C1).
--         UPDATE: NT007 congelados (paciente/cita/medico/created_at); NT009 campos de control;
--                 en el cierre imc congelado (C3); NT006 nota cerrada sin llave de correccion;
--                 revision con la fila previa si cambio el contenido (imc excluido, C3).
--   (e) private.cerrar_nota_al_completar (AFTER UPDATE OF estado ON citas): pone cerrada_at.
--   (f) private.revision_nota_inmutable: NT008 en UPDATE/DELETE de revisiones (para todos).
--   (g) public.corregir_nota_consulta: correccion con motivo del medico autor (NT001-NT005,
--       NT011; gate de cuenta: solo tiene_rol medico = perfiles.activo (315), C5 v3).
--   (h) exp_superadmin_all -> _select/_insert/_update, sin DELETE (D9).
--   (i) signos_vitales.consulta_id: ON DELETE CASCADE -> RESTRICT (D9; 0 filas ligadas).
--   (j) REVOKE DELETE, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN en expediente_notas (D9, D10, R4).
--
-- Llave de correccion: GUC local a la transaccion, atada al id de la fila y puesta solo por la RPC
-- o por el trigger de cierre (ezpay.nota_llave = 'corregir:<id>' | 'cerrar:<id>'; motivo en
-- ezpay.nota_motivo). El cliente no puede ejecutar set_config (pg_catalog no esta expuesto).
--
-- NO toca: exigir_nota_al_completar (PE001), cita_tiene_nota, calcular_imc_signos_vitales,
-- contexto_ia_paciente, obtener_contexto_visita, actualizar_estado_cita, exigir_empresa_activa
-- (precondicion y autochequeo por md5), exp_update_medico, exp_insert_medico ni las SELECT.
--
-- Errcodes NT001-NT011 (familia nueva). Probes P885-P896, P908-P911. Rollback: 334_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
DO $pre$
DECLARE bad text := ''; x text; r record; n int;
BEGIN
  -- funciones que la 334 no toca: md5 exacto
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
  -- helpers que usan las funciones y la policy nuevas
  FOR r IN SELECT f FROM unnest(ARRAY['private.tiene_rol(text[])','private.es_medico_de(bigint)',
      'private.medico_atiende_paciente(bigint)','private.medico_es_de_mi_clinica(uuid)']) f LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; END IF;
  END LOOP;
  -- nombres libres
  IF to_regclass('public.expediente_notas_revisiones') IS NOT NULL THEN bad := bad||'expediente_notas_revisiones ya existe; '; END IF;
  SELECT string_agg(p.oid::regprocedure::text, ',') INTO x FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname = 'public' AND p.proname = 'corregir_nota_consulta')
      OR (ns.nspname = 'private' AND p.proname IN ('expediente_notas_guardia','cerrar_nota_al_completar','revision_nota_inmutable'));
  IF x IS NOT NULL THEN bad := bad||'funciones ya existen: '||x||'; '; END IF;
  SELECT string_agg(attname, ',') INTO x FROM pg_attribute WHERE attrelid = 'public.expediente_notas'::regclass
     AND attname IN ('updated_at','updated_by','cerrada_at','corregida_at') AND NOT attisdropped;
  IF x IS NOT NULL THEN bad := bad||'columnas ya existen: '||x||'; '; END IF;
  SELECT string_agg(policyname, ',') INTO x FROM pg_policies WHERE schemaname = 'public'
     AND policyname IN ('exp_superadmin_select','exp_superadmin_insert','exp_superadmin_update','exp_rev_select');
  IF x IS NOT NULL THEN bad := bad||'policies ya existen: '||x||'; '; END IF;
  SELECT string_agg(tgname, ',') INTO x FROM pg_trigger
   WHERE tgname IN ('trg_expediente_notas_guardia','trg_cerrar_nota_al_completar','trg_exp_rev_inmutable');
  IF x IS NOT NULL THEN bad := bad||'triggers ya existen: '||x||'; '; END IF;
  -- estado previo que la 334 reemplaza
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas'
       AND policyname = 'exp_superadmin_all' AND cmd = 'ALL' AND roles::text = '{authenticated}'
       AND qual = 'private.tiene_rol(ARRAY[''super_admin''::text])' AND with_check = 'private.tiene_rol(ARRAY[''super_admin''::text])') THEN
    bad := bad||'exp_superadmin_all distinta de la medida; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'signos_vitales_consulta_id_fkey'
       AND conrelid = 'public.signos_vitales'::regclass AND confrelid = 'public.expediente_notas'::regclass AND confdeltype = 'c') THEN
    bad := bad||'signos_vitales_consulta_id_fkey no es la CASCADE medida; '; END IF;
  SELECT string_agg(tgname, ',' ORDER BY tgname) INTO x FROM pg_trigger WHERE tgrelid = 'public.expediente_notas'::regclass AND NOT tgisinternal;
  IF x IS DISTINCT FROM 'trg_calcular_imc_expediente' THEN bad := bad||'triggers de expediente_notas='||COALESCE(x,'-')||'; '; END IF;
  -- el guardia tiene que correr DESPUES del recalculo del IMC (orden alfabetico de triggers BEFORE ROW)
  IF NOT ('trg_calcular_imc_expediente' COLLATE "C" < 'trg_expediente_notas_guardia' COLLATE "C") THEN bad := bad||'orden de triggers; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.citas'::regclass AND tgname = 'trg_exigir_nota_al_completar' AND tgenabled = 'O') THEN
    bad := bad||'trg_exigir_nota_al_completar ausente; '; END IF;
  -- C2: toda nota con cita cumple la integridad nota<->cita (el guardia solo la chequea en el INSERT)
  SELECT count(*) INTO n FROM public.expediente_notas en LEFT JOIN public.citas c ON c.id = en.cita_id
   WHERE en.cita_id IS NOT NULL
     AND (c.id IS NULL OR c.medico_id IS DISTINCT FROM en.medico_id OR c.paciente_id IS DISTINCT FROM en.paciente_id::bigint);
  IF n <> 0 THEN bad := bad||n||' nota(s) que no corresponden a su cita; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG334 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- snapshot del contenido de las notas: la migracion no puede cambiar nada fuera de las columnas nuevas
CREATE TEMP TABLE _snap334 ON COMMIT DROP AS
SELECT md5(COALESCE(string_agg(to_jsonb(n)::text, '|' ORDER BY n.id), '')) AS notas FROM public.expediente_notas n;

-- ------------------------------------------------------------------------------- (a) columnas
ALTER TABLE public.expediente_notas
  ADD COLUMN updated_at   timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN updated_by   uuid NULL,
  ADD COLUMN cerrada_at   timestamptz NULL,
  ADD COLUMN corregida_at timestamptz NULL;
COMMENT ON COLUMN public.expediente_notas.updated_at IS 'Ultimo UPDATE (mig 334; lo fija el trigger guardia).';
COMMENT ON COLUMN public.expediente_notas.updated_by IS 'auth.uid() del ultimo UPDATE (mig 334). NULL = sistema.';
COMMENT ON COLUMN public.expediente_notas.cerrada_at IS
  'Cierre de la nota (mig 334): al completar la cita, o al nacer si no tiene cita o su cita ya estaba completada. No se borra si la cita vuelve atras. Cerrada = solo se corrige por corregir_nota_consulta.';
COMMENT ON COLUMN public.expediente_notas.corregida_at IS 'Ultima correccion con motivo (mig 334, corregir_nota_consulta).';

-- ------------------------------------------------------------------------------- (b) backfill
-- el trigger del IMC recalcula en todo UPDATE: se apaga solo para el backfill, que no debe tocar
-- el contenido (una fila legacy con imc distinto de la formula cambiaria en silencio)
ALTER TABLE public.expediente_notas DISABLE TRIGGER trg_calcular_imc_expediente;
UPDATE public.expediente_notas SET updated_at = created_at;
UPDATE public.expediente_notas SET cerrada_at = now()
 WHERE cita_id IS NULL OR cita_id IN (SELECT c.id FROM public.citas c WHERE c.estado = 'completada');
ALTER TABLE public.expediente_notas ENABLE TRIGGER trg_calcular_imc_expediente;

-- -------------------------------------------------------------------- (c) tabla de revisiones
CREATE TABLE public.expediente_notas_revisiones (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nota_id          integer NOT NULL CONSTRAINT expediente_notas_revisiones_nota_id_fkey
                     REFERENCES public.expediente_notas(id) ON DELETE RESTRICT,
  paciente_id      integer NOT NULL,
  medico_id        uuid    NOT NULL,
  revision         integer NOT NULL,
  tipo             text    NOT NULL CONSTRAINT expediente_notas_revisiones_tipo_check CHECK (tipo IN ('edicion','correccion')),
  motivo           text    NULL CONSTRAINT expediente_notas_revisiones_motivo_check
                     CHECK (tipo = 'edicion' OR (motivo IS NOT NULL AND btrim(motivo) <> '')),
  version_anterior jsonb   NOT NULL,
  editado_por      uuid    NULL,
  editado_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT expediente_notas_revisiones_nota_revision_key UNIQUE (nota_id, revision)
);
CREATE INDEX idx_exp_rev_paciente ON public.expediente_notas_revisiones USING btree (paciente_id);
COMMENT ON TABLE public.expediente_notas_revisiones IS
  'Historial append-only de expediente_notas (mig 334): una fila por cambio de contenido con la version ANTERIOR completa. La escribe solo private.expediente_notas_guardia; UPDATE/DELETE -> NT008 para todos.';

ALTER TABLE public.expediente_notas_revisiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expediente_notas_revisiones FORCE ROW LEVEL SECURITY;

CREATE POLICY exp_rev_select ON public.expediente_notas_revisiones
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((medico_id = auth.uid())
         OR private.es_medico_de((paciente_id)::bigint)
         OR private.medico_atiende_paciente((paciente_id)::bigint)
         OR COALESCE(private.medico_es_de_mi_clinica(medico_id), false)
         OR private.tiene_rol(ARRAY['super_admin'::text]));

-- los default privileges de postgres en public dan arwdDxtm a authenticated y service_role: se
-- parte de cero y se otorga exactamente lo de la regla del 30-oct
REVOKE ALL ON TABLE public.expediente_notas_revisiones FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.expediente_notas_revisiones TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.expediente_notas_revisiones TO service_role;
REVOKE ALL ON SEQUENCE public.expediente_notas_revisiones_id_seq FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------ (d) guardia
CREATE FUNCTION private.expediente_notas_guardia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_llave      text := COALESCE(current_setting('ezpay.nota_llave', true), '');
  v_c_existe   boolean;
  v_c_medico   uuid;
  v_c_paciente bigint;
  v_c_estado   text;
  v_corr       boolean;
  v_rev        integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- C2: la nota tiene que corresponder a su cita (mismo medico y mismo paciente). FOR SHARE: un
    -- cambio concurrente de la cita espera, y si la completa se ve aca (C1).
    IF NEW.cita_id IS NOT NULL THEN
      SELECT true, c.medico_id, c.paciente_id, c.estado
        INTO v_c_existe, v_c_medico, v_c_paciente, v_c_estado
        FROM public.citas c WHERE c.id = NEW.cita_id
         FOR SHARE;
      IF NOT COALESCE(v_c_existe, false)
         OR v_c_medico IS DISTINCT FROM NEW.medico_id
         OR v_c_paciente IS DISTINCT FROM NEW.paciente_id::bigint THEN
        RAISE EXCEPTION 'La nota no corresponde a la cita' USING ERRCODE = 'NT010';
      END IF;
    END IF;
    NEW.created_at   := now();                 -- R5: no se fecha hacia atras
    NEW.updated_at   := NEW.created_at;
    NEW.updated_by   := auth.uid();
    NEW.corregida_at := NULL;
    -- R1: sin cita nace cerrada. C1: sobre cita ya completada, tambien (el cierre no la veria).
    NEW.cerrada_at   := CASE WHEN NEW.cita_id IS NULL OR v_c_estado = 'completada' THEN now() ELSE NULL END;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NEW.paciente_id IS DISTINCT FROM OLD.paciente_id OR NEW.cita_id IS DISTINCT FROM OLD.cita_id
     OR NEW.medico_id IS DISTINCT FROM OLD.medico_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'La nota no permite cambiar paciente, cita, médico ni fecha de creación' USING ERRCODE = 'NT007';
  END IF;

  IF (NEW.cerrada_at IS DISTINCT FROM OLD.cerrada_at AND v_llave IS DISTINCT FROM 'cerrar:'||OLD.id)
     OR (NEW.corregida_at IS DISTINCT FROM OLD.corregida_at AND v_llave IS DISTINCT FROM 'corregir:'||OLD.id) THEN
    RAISE EXCEPTION 'Campo de control de la nota reservado al sistema' USING ERRCODE = 'NT009';
  END IF;

  -- C3: el cierre solo pone la fecha de cierre; no recalcula el IMC ni cambia nada mas
  IF v_llave = 'cerrar:'||OLD.id THEN
    NEW.imc := OLD.imc;
    IF (to_jsonb(NEW) - ARRAY['cerrada_at','updated_at','updated_by'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['cerrada_at','updated_at','updated_by']) THEN
      RAISE EXCEPTION 'Campo de control de la nota reservado al sistema' USING ERRCODE = 'NT009';
    END IF;
  END IF;

  IF OLD.cerrada_at IS NOT NULL AND v_llave IS DISTINCT FROM 'corregir:'||OLD.id THEN
    RAISE EXCEPTION 'La nota está cerrada: solo se puede corregir con motivo' USING ERRCODE = 'NT006';
  END IF;

  -- revision con la fila previa completa si cambio el contenido (imc excluido: es derivado, C3)
  IF (to_jsonb(OLD) - ARRAY['updated_at','updated_by','cerrada_at','corregida_at','imc'])
     IS DISTINCT FROM (to_jsonb(NEW) - ARRAY['updated_at','updated_by','cerrada_at','corregida_at','imc']) THEN
    v_corr := (v_llave = 'corregir:'||OLD.id);
    SELECT COALESCE(max(r.revision), 0) + 1 INTO v_rev
      FROM public.expediente_notas_revisiones r WHERE r.nota_id = OLD.id;
    INSERT INTO public.expediente_notas_revisiones
      (nota_id, paciente_id, medico_id, revision, tipo, motivo, version_anterior, editado_por)
    VALUES
      (OLD.id, OLD.paciente_id, OLD.medico_id, v_rev,
       CASE WHEN v_corr THEN 'correccion' ELSE 'edicion' END,
       CASE WHEN v_corr THEN NULLIF(current_setting('ezpay.nota_motivo', true), '') ELSE NULL END,
       to_jsonb(OLD), auth.uid());
  END IF;

  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  RETURN NEW;
END
$function$;
COMMENT ON FUNCTION private.expediente_notas_guardia() IS
  'Mig 334. BEFORE INSERT OR UPDATE de expediente_notas, para todos (postgres incluido): NT010 integridad nota-cita en el INSERT; NT007 congelados; NT009 campos de control; NT006 nota cerrada sin llave corregir:<id>; revision append-only con la fila previa si cambia el contenido (imc excluido).';

-- ------------------------------------------------------------------------------ (e) cierre
CREATE FUNCTION private.cerrar_nota_al_completar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_nota integer;
BEGIN
  -- a lo sumo una nota por cita (UNIQUE expediente_notas_una_por_cita)
  SELECT n.id INTO v_nota FROM public.expediente_notas n WHERE n.cita_id = NEW.id AND n.cerrada_at IS NULL;
  IF v_nota IS NOT NULL THEN
    PERFORM set_config('ezpay.nota_llave', 'cerrar:'||v_nota, true);
    UPDATE public.expediente_notas SET cerrada_at = now() WHERE id = v_nota;
    PERFORM set_config('ezpay.nota_llave', '', true);
  END IF;
  RETURN NULL;
END
$function$;
COMMENT ON FUNCTION private.cerrar_nota_al_completar() IS
  'Mig 334. AFTER UPDATE OF estado ON citas al pasar a completada: cierra la nota de la cita (cerrada_at) con la llave cerrar:<id>. No reabre nada si la cita vuelve atras.';

-- ---------------------------------------------------------------------- (f) inmutabilidad
CREATE FUNCTION private.revision_nota_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Las revisiones de la nota son inmutables' USING ERRCODE = 'NT008';
END
$function$;
COMMENT ON FUNCTION private.revision_nota_inmutable() IS
  'Mig 334. BEFORE UPDATE OR DELETE de expediente_notas_revisiones: NT008 para todos.';

-- --------------------------------------------------------------------------- (g) la RPC
CREATE FUNCTION public.corregir_nota_consulta(
  p_nota_id integer, p_motivo text,
  p_motivo_consulta text, p_subjetivo text, p_objetivo text, p_analisis text, p_plan text, p_diagnostico text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_nota   public.expediente_notas%ROWTYPE;
  v_motivo text;
  v_corr   timestamptz;
  v_rev    integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicie sesión' USING ERRCODE = 'NT001';
  END IF;
  -- C5: el gate de cuenta del medico es solo tiene_rol (mig 315: perfiles.activo IS TRUE). El
  -- estado de una empresa proveedora no afecta acciones clinicas del medico (doble rol).
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo un médico con cuenta activa puede corregir notas' USING ERRCODE = 'NT011';
  END IF;

  SELECT * INTO v_nota FROM public.expediente_notas n WHERE n.id = p_nota_id FOR UPDATE;
  IF NOT FOUND OR v_nota.medico_id IS DISTINCT FROM v_uid THEN
    -- mismo codigo para "no existe": no se revela la existencia
    RAISE EXCEPTION 'No autorizado: solo el médico autor puede corregir la nota' USING ERRCODE = 'NT002';
  END IF;
  IF v_nota.cerrada_at IS NULL THEN
    RAISE EXCEPTION 'La nota todavía no está cerrada: guárdela normalmente' USING ERRCODE = 'NT003';
  END IF;
  v_motivo := btrim(p_motivo);
  IF v_motivo IS NULL OR v_motivo = '' OR length(v_motivo) > 500 THEN
    RAISE EXCEPTION 'El motivo de la corrección es obligatorio (máximo 500 caracteres)' USING ERRCODE = 'NT004';
  END IF;
  IF p_motivo_consulta IS NOT DISTINCT FROM v_nota.motivo_consulta
     AND p_subjetivo   IS NOT DISTINCT FROM v_nota.subjetivo
     AND p_objetivo    IS NOT DISTINCT FROM v_nota.objetivo
     AND p_analisis    IS NOT DISTINCT FROM v_nota.analisis
     AND p_plan        IS NOT DISTINCT FROM v_nota.plan
     AND p_diagnostico IS NOT DISTINCT FROM v_nota.diagnostico THEN
    RAISE EXCEPTION 'La corrección no cambia ningún campo de la nota' USING ERRCODE = 'NT005';
  END IF;

  PERFORM set_config('ezpay.nota_llave', 'corregir:'||p_nota_id, true);
  PERFORM set_config('ezpay.nota_motivo', v_motivo, true);
  UPDATE public.expediente_notas
     SET motivo_consulta = p_motivo_consulta,
         subjetivo       = p_subjetivo,
         objetivo        = p_objetivo,
         analisis        = p_analisis,
         plan            = p_plan,
         diagnostico     = p_diagnostico,
         corregida_at    = now()
   WHERE id = p_nota_id
   RETURNING corregida_at INTO v_corr;
  PERFORM set_config('ezpay.nota_llave', '', true);
  PERFORM set_config('ezpay.nota_motivo', '', true);

  SELECT max(r.revision) INTO v_rev FROM public.expediente_notas_revisiones r WHERE r.nota_id = p_nota_id;
  RETURN jsonb_build_object('nota_id', p_nota_id, 'revision', v_rev, 'corregida_at', v_corr);
END
$function$;
COMMENT ON FUNCTION public.corregir_nota_consulta(integer, text, text, text, text, text, text, text) IS
  'Mig 334. Correccion con motivo de una nota CERRADA por su medico autor. Gates: NT001 sesion, NT011 rol medico activo, NT002 autor (o no existe), NT003 no cerrada, NT004 motivo, NT005 sin cambios. Los 6 textos son la version nueva completa.';

-- EXECUTE: la RPC solo a authenticated; las privadas solo a postgres (los default privileges
-- otorgan X a authenticated y service_role, y la creacion a PUBLIC)
REVOKE ALL ON FUNCTION public.corregir_nota_consulta(integer, text, text, text, text, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.corregir_nota_consulta(integer, text, text, text, text, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION private.expediente_notas_guardia() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.cerrar_nota_al_completar() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.revision_nota_inmutable() FROM PUBLIC, anon, authenticated, service_role;

-- ------------------------------------------------------------------------------ triggers
CREATE TRIGGER trg_expediente_notas_guardia
  BEFORE INSERT OR UPDATE ON public.expediente_notas
  FOR EACH ROW EXECUTE FUNCTION private.expediente_notas_guardia();
CREATE TRIGGER trg_cerrar_nota_al_completar
  AFTER UPDATE OF estado ON public.citas
  FOR EACH ROW WHEN (NEW.estado = 'completada' AND OLD.estado IS DISTINCT FROM 'completada')
  EXECUTE FUNCTION private.cerrar_nota_al_completar();
CREATE TRIGGER trg_exp_rev_inmutable
  BEFORE UPDATE OR DELETE ON public.expediente_notas_revisiones
  FOR EACH ROW EXECUTE FUNCTION private.revision_nota_inmutable();

-- ------------------------------------------------------------- (h) split de exp_superadmin_all
DROP POLICY exp_superadmin_all ON public.expediente_notas;
CREATE POLICY exp_superadmin_select ON public.expediente_notas
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY exp_superadmin_insert ON public.expediente_notas
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY exp_superadmin_update ON public.expediente_notas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));

-- ------------------------------------------------------------------ (i) FK de signos vitales
ALTER TABLE public.signos_vitales DROP CONSTRAINT signos_vitales_consulta_id_fkey;
ALTER TABLE public.signos_vitales ADD CONSTRAINT signos_vitales_consulta_id_fkey
  FOREIGN KEY (consulta_id) REFERENCES public.expediente_notas(id) ON DELETE RESTRICT;

-- ------------------------------------------------------------------------------ (j) REVOKE
REVOKE DELETE, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON public.expediente_notas FROM authenticated, anon, PUBLIC;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; n int; r record;
BEGIN
  -- (a) columnas
  SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod)||':'||CASE WHEN a.attnotnull THEN 'NN' ELSE 'N' END, ',' ORDER BY a.attname)
    INTO x FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND NOT a.attisdropped
     AND a.attname IN ('updated_at','updated_by','cerrada_at','corregida_at');
  IF x IS DISTINCT FROM 'cerrada_at:timestamp with time zone:N,corregida_at:timestamp with time zone:N,updated_at:timestamp with time zone:NN,updated_by:uuid:N' THEN
    bad := bad||'columnas='||COALESCE(x,'-')||'; '; END IF;
  -- (c) tabla de revisiones: RLS + FORCE, una policy SELECT, FK RESTRICT, UNIQUE, CHECKs
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.expediente_notas_revisiones'::regclass AND relrowsecurity AND relforcerowsecurity) THEN
    bad := bad||'revisiones sin RLS/FORCE; '; END IF;
  SELECT string_agg(policyname||':'||cmd||':'||roles::text, ',') INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas_revisiones';
  IF x IS DISTINCT FROM 'exp_rev_select:SELECT:{authenticated}' THEN bad := bad||'policies revisiones='||COALESCE(x,'-')||'; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'expediente_notas_revisiones_nota_id_fkey' AND contype = 'f'
       AND confrelid = 'public.expediente_notas'::regclass AND confdeltype = 'r') THEN bad := bad||'FK revisiones no RESTRICT; '; END IF;
  SELECT string_agg(conname||':'||contype::text, ',' ORDER BY conname COLLATE "C") INTO x FROM pg_constraint
   WHERE conrelid = 'public.expediente_notas_revisiones'::regclass AND contype IN ('c','u','p');
  IF x IS DISTINCT FROM 'expediente_notas_revisiones_motivo_check:c,expediente_notas_revisiones_nota_revision_key:u,expediente_notas_revisiones_pkey:p,expediente_notas_revisiones_tipo_check:c' THEN
    bad := bad||'constraints revisiones='||COALESCE(x,'-')||'; '; END IF;
  -- grants exactos de la tabla nueva (sin contar al owner)
  SELECT string_agg(g, ',' ORDER BY g COLLATE "C") INTO x
    FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type AS g
            FROM pg_class c, aclexplode(c.relacl) a
           WHERE c.oid = 'public.expediente_notas_revisiones'::regclass AND a.grantee <> c.relowner) z;
  IF x IS DISTINCT FROM 'authenticated:SELECT,service_role:DELETE,service_role:INSERT,service_role:SELECT,service_role:UPDATE' THEN
    bad := bad||'grants revisiones='||COALESCE(x,'-')||'; '; END IF;
  SELECT count(*) INTO n FROM pg_class c, aclexplode(c.relacl) a
   WHERE c.oid = 'public.expediente_notas_revisiones_id_seq'::regclass AND pg_get_userbyid(a.grantee) IN ('authenticated','anon');
  IF n <> 0 OR EXISTS (SELECT 1 FROM pg_class c, aclexplode(c.relacl) a WHERE c.oid = 'public.expediente_notas_revisiones_id_seq'::regclass AND a.grantee = 0) THEN
    bad := bad||'secuencia de revisiones con grants a authenticated/anon/PUBLIC; '; END IF;
  -- triggers: tipo (bits de tgtype), funcion y habilitados
  FOR r IN SELECT * FROM (VALUES
      ('trg_expediente_notas_guardia', 'public.expediente_notas',            23, 'private.expediente_notas_guardia()'),
      ('trg_cerrar_nota_al_completar', 'public.citas',                       17, 'private.cerrar_nota_al_completar()'),
      ('trg_exp_rev_inmutable',        'public.expediente_notas_revisiones', 27, 'private.revision_nota_inmutable()'),
      ('trg_exigir_nota_al_completar', 'public.citas',                       19, 'private.exigir_nota_al_completar()'),
      ('trg_calcular_imc_expediente',  'public.expediente_notas',            23, 'public.calcular_imc_signos_vitales()')) v(tg, tb, ty, fn) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = r.tg AND t.tgrelid = r.tb::regclass AND t.tgtype = r.ty
         AND t.tgfoid = to_regprocedure(r.fn) AND t.tgenabled = 'O') THEN bad := bad||'trigger '||r.tg||'; '; END IF;
  END LOOP;
  SELECT pg_get_triggerdef(t.oid) INTO x FROM pg_trigger t WHERE t.tgname = 'trg_cerrar_nota_al_completar';
  IF COALESCE(x, '') NOT LIKE '%AFTER UPDATE OF estado ON public.citas FOR EACH ROW WHEN (((new.estado = ''completada''::text) AND (old.estado IS DISTINCT FROM ''completada''::text)))%' THEN
    bad := bad||'WHEN del cierre='||COALESCE(x,'-')||'; '; END IF;
  -- funciones: DEFINER, search_path vacio, EXECUTE exacto
  FOR r IN SELECT * FROM (VALUES
      ('public.corregir_nota_consulta(integer,text,text,text,text,text,text,text)', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.expediente_notas_guardia()',  '{postgres=X/postgres}'),
      ('private.cerrar_nota_al_completar()',  '{postgres=X/postgres}'),
      ('private.revision_nota_inmutable()',   '{postgres=X/postgres}')) v(f, acl) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.f) AND p.prosecdef
         AND p.proconfig = ARRAY['search_path=""'] AND p.proacl::text = r.acl) THEN
      SELECT COALESCE(p.prosecdef::text,'-')||' '||COALESCE(p.proconfig::text,'-')||' '||COALESCE(p.proacl::text,'-') INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
      bad := bad||r.f||' ('||COALESCE(x,'NO EXISTE')||'); '; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc WHERE proname = 'corregir_nota_consulta';
  IF n <> 1 THEN bad := bad||n||' firmas de corregir_nota_consulta; '; END IF;
  -- (h) policies de expediente_notas: conjunto exacto, sin ALL ni DELETE; las del super_admin
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'expediente_notas';
  IF x IS DISTINCT FROM 'Admin clinica ve expediente de su clinica:SELECT,exp_insert_medico:INSERT,exp_select_medico:SELECT,exp_select_paciente:SELECT,exp_superadmin_insert:INSERT,exp_superadmin_select:SELECT,exp_superadmin_update:UPDATE,exp_update_medico:UPDATE' THEN
    bad := bad||'policies notas='||COALESCE(x,'-')||'; '; END IF;
  FOR r IN SELECT policyname, cmd, roles::text AS roles, qual, with_check FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'expediente_notas' AND policyname LIKE 'exp\_superadmin\_%' LOOP
    IF r.roles <> '{authenticated}'
       OR (r.cmd = 'SELECT' AND (r.qual IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])' OR r.with_check IS NOT NULL))
       OR (r.cmd = 'INSERT' AND (r.qual IS NOT NULL OR r.with_check IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])'))
       OR (r.cmd = 'UPDATE' AND (r.qual IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])' OR r.with_check IS DISTINCT FROM r.qual)) THEN
      bad := bad||r.policyname||' ('||r.roles||' '||COALESCE(r.qual,'-')||' / '||COALESCE(r.with_check,'-')||'); '; END IF;
  END LOOP;
  -- (j) grants de expediente_notas
  SELECT string_agg(p, ',' ORDER BY p) INTO x FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
   WHERE has_table_privilege('authenticated', 'public.expediente_notas', p);
  IF x IS DISTINCT FROM 'INSERT,SELECT,UPDATE' THEN bad := bad||'authenticated en notas='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(p, ',' ORDER BY p) INTO x FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p
   WHERE has_table_privilege('anon', 'public.expediente_notas', p);
  IF x IS NOT NULL THEN bad := bad||'anon en notas='||x||'; '; END IF;
  SELECT count(*) INTO n FROM pg_class c, aclexplode(c.relacl) a WHERE c.oid = 'public.expediente_notas'::regclass AND a.grantee = 0;
  IF n <> 0 THEN bad := bad||'PUBLIC en notas; '; END IF;
  -- (i) FK de signos vitales
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'signos_vitales_consulta_id_fkey' AND conrelid = 'public.signos_vitales'::regclass
       AND confrelid = 'public.expediente_notas'::regclass AND confdeltype = 'r') THEN bad := bad||'FK signos no RESTRICT; '; END IF;
  -- funciones que no se tocan
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
  -- (b) datos
  SELECT count(*) INTO n FROM public.expediente_notas en JOIN public.citas c ON c.id = en.cita_id
   WHERE c.estado = 'completada' AND en.cerrada_at IS NULL;
  IF n <> 0 THEN bad := bad||n||' nota(s) de cita completada sin cerrar; '; END IF;
  SELECT count(*) INTO n FROM public.expediente_notas WHERE cita_id IS NULL AND cerrada_at IS NULL;
  IF n <> 0 THEN bad := bad||n||' nota(s) sin cita sin cerrar; '; END IF;
  SELECT count(*) INTO n FROM public.expediente_notas en LEFT JOIN public.citas c ON c.id = en.cita_id
   WHERE en.cita_id IS NOT NULL
     AND (c.id IS NULL OR c.medico_id IS DISTINCT FROM en.medico_id OR c.paciente_id IS DISTINCT FROM en.paciente_id::bigint);
  IF n <> 0 THEN bad := bad||n||' nota(s) que no corresponden a su cita; '; END IF;
  SELECT count(*) INTO n FROM public.expediente_notas WHERE updated_at IS DISTINCT FROM created_at OR updated_by IS NOT NULL OR corregida_at IS NOT NULL;
  IF n <> 0 THEN bad := bad||n||' nota(s) con backfill distinto; '; END IF;
  SELECT count(*) INTO n FROM public.expediente_notas_revisiones;
  IF n <> 0 THEN bad := bad||n||' revision(es) creadas por la migracion (D12: ninguna); '; END IF;
  SELECT md5(COALESCE(string_agg((to_jsonb(en) - ARRAY['updated_at','updated_by','cerrada_at','corregida_at'])::text, '|' ORDER BY en.id), ''))
    INTO x FROM public.expediente_notas en;
  IF x IS DISTINCT FROM (SELECT s.notas FROM _snap334 s) THEN bad := bad||'el contenido de las notas cambio; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG334 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
