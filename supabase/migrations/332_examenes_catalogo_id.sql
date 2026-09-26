-- ############################################################################################
-- 332 - P3: ordenes de examen con catalogo_id + RPCs de creacion (ADITIVA, fase 1 de 2)
-- ############################################################################################
-- Spec: tmp/p3_spec.md (25-sep-2026). Decisiones de Oscar: M.1 dos migraciones (esta es la
-- aditiva; la 333 revoca el INSERT directo DESPUES de publicar el front), M.2 la RPC del medico
-- notifica en un sub-bloque protegido, M.3 texto libre igual a un examen activo del catalogo ->
-- EX017, M.6 el catalogo solo se edita en activo/categoria, M.7 fuera el UPDATE de ordenes_examen
-- y la policy examenes_medico_update. Menores: las recomendaciones de la spec.
--
-- Antes (medido 25-sep): toda orden nacia por INSERT directo del cliente, en dos sentencias no
-- atomicas, guardando solo el nombre en examenes.tipo. Las policies de INSERT no validaban
-- laboratorio_id, clinica_id ni las copias de texto.
--
-- Esta migracion:
--   (a) examenes.catalogo_id uuid NULL -> examenes_catalogo(id) ON DELETE RESTRICT + indice.
--       NULL = examen fuera de catalogo (texto libre). examenes.tipo queda como snapshot del nombre.
--   (b) UNIQUE (laboratorio_id, lower(btrim(nombre))) en examenes_catalogo (0 duplicados hoy).
--   (c) Backfill: los 10 examenes con coincidencia EXACTA de nombre en el catalogo del mismo
--       laboratorio; los 4 de texto libre (4, 158, 254, 720) quedan NULL. Aborta si la tabla ya no
--       tiene exactamente los 14 examenes medidos.
--   (d) private.armar_items_orden_examen: validacion comun de items (EX008-EX017).
--   (e) public.crear_orden_examen_medico y public.crear_orden_examen_walkin: cabecera + items en una
--       sola transaccion; identidad, copias de texto, origen y estado derivados en el servidor; el
--       nombre de catalogo lo copia el servidor.
--   (f) Congelamiento: el cliente solo puede UPDATE estado/fecha_resultado/resultados/archivo_url de
--       examenes (grants por columna) y un trigger rechaza cambiar tipo o catalogo_id (EX022) para
--       cualquiera, incluidos los SECURITY DEFINER.
--   (g) Catalogo: el cliente solo puede UPDATE activo/categoria (no se renombra).
--   (h) M.7: sin UPDATE de ordenes_examen para el cliente; DROP examenes_medico_update (sin uso).
--
-- NO toca (va en la 333, despues del front): REVOKE INSERT de ordenes_examen/examenes, DROP de
-- ordenes_medico_insert/examenes_medico_insert, split de las policies ALL, TRUNCATE/TRIGGER/
-- REFERENCES de authenticated. Mientras tanto el front viejo sigue creando ordenes por INSERT.
-- NO toca las 9 funciones que leen/escriben examenes (el autochequeo lo verifica por md5).
--
-- Errcodes EX001-EX022 (familia nueva, EX021 sin uso: el renombre se cierra por grants).
-- Probes P866-P878. Rollback: 332_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------------- (a) columna
ALTER TABLE public.examenes
  ADD COLUMN catalogo_id uuid NULL
  CONSTRAINT examenes_catalogo_id_fkey REFERENCES public.examenes_catalogo(id) ON DELETE RESTRICT;
CREATE INDEX idx_examenes_catalogo ON public.examenes USING btree (catalogo_id);
COMMENT ON COLUMN public.examenes.catalogo_id IS
  'Examen de catalogo ordenado (mig 332). NULL = fuera de catalogo (texto libre). examenes.tipo es el snapshot del nombre.';

-- ----------------------------------------------------------------------------------- (b) UNIQUE
CREATE UNIQUE INDEX ux_examenes_catalogo_lab_nombre
  ON public.examenes_catalogo USING btree (laboratorio_id, lower(btrim(nombre)));

-- --------------------------------------------------------------------------------- (c) backfill
DO $bf$
DECLARE v_ids integer[]; n int; v_bad text;
BEGIN
  SELECT array_agg(id ORDER BY id) INTO v_ids FROM public.examenes;
  IF v_ids IS DISTINCT FROM ARRAY[1,2,3,4,157,158,250,251,252,253,254,718,719,720] THEN
    RAISE EXCEPTION 'MIG332: examenes cambio desde el snapshot del 25-sep (ids=%): re-medir el backfill', v_ids;
  END IF;

  UPDATE public.examenes e
     SET catalogo_id = c.id
    FROM public.examenes_catalogo c
   WHERE c.laboratorio_id = e.laboratorio_id
     AND c.nombre = e.tipo
     AND e.catalogo_id IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 10 THEN RAISE EXCEPTION 'MIG332: el backfill toco % filas, se esperaban 10', n; END IF;

  SELECT string_agg(e.id::text || '=' || COALESCE(e.catalogo_id::text, 'NULL'), ', ' ORDER BY e.id) INTO v_bad
    FROM public.examenes e
   WHERE e.catalogo_id IS DISTINCT FROM CASE
       WHEN e.id IN (1, 250, 718)   THEN '27a2af0f-e201-4a1d-900a-cb27851d9577'::uuid
       WHEN e.id IN (2, 252)        THEN '43a1a45c-82f7-403a-a663-1ab7fc8b3732'::uuid
       WHEN e.id IN (3, 253)        THEN '4f32f195-e4de-4282-8303-8ec8bafecec1'::uuid
       WHEN e.id IN (157, 251, 719) THEN '7c980fb6-5048-4905-a682-9d6e9feb55ed'::uuid
       ELSE NULL END;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'MIG332: backfill distinto del esperado: %', v_bad; END IF;
END $bf$;

-- ---------------------------------------------------------------------- (d) helper de items
CREATE FUNCTION private.armar_items_orden_examen(p_laboratorio_id uuid, p_items jsonb)
 RETURNS TABLE(out_ord integer, out_tipo text, out_catalogo_id uuid)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_n        int;
  v_i        int;
  v_el       jsonb;
  v_cat      uuid;
  v_nombre   text;
  v_activo   boolean;
  v_nom      text;
  v_clave    text;
  v_vistos_c uuid[] := '{}';
  v_vistos_n text[] := '{}';
BEGIN
  -- (332) Validacion comun de items de una orden de examen. La usan crear_orden_examen_medico y
  -- crear_orden_examen_walkin. Cada item trae EXACTAMENTE una clave: {"catalogo_id": uuid} (el
  -- nombre lo copia el servidor del catalogo) o {"nombre": texto} (fuera de catalogo).
  -- p_laboratorio_id NULL = orden sin laboratorio: solo admite texto libre (EX013).
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Seleccione o escriba al menos un examen' USING ERRCODE = 'EX008';
  END IF;
  v_n := jsonb_array_length(p_items);
  IF v_n > 30 THEN
    RAISE EXCEPTION 'Una orden admite como máximo 30 exámenes' USING ERRCODE = 'EX009';
  END IF;

  FOR v_i IN 0 .. v_n - 1 LOOP
    v_el := p_items -> v_i;
    IF jsonb_typeof(v_el) <> 'object'
       OR (v_el ? 'catalogo_id') = (v_el ? 'nombre')
       OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_el) k WHERE k NOT IN ('catalogo_id', 'nombre')) THEN
      RAISE EXCEPTION 'Examen mal formado en la orden' USING ERRCODE = 'EX010';
    END IF;

    IF v_el ? 'catalogo_id' THEN
      IF jsonb_typeof(v_el -> 'catalogo_id') <> 'string' THEN
        RAISE EXCEPTION 'Examen mal formado en la orden' USING ERRCODE = 'EX010';
      END IF;
      BEGIN
        v_cat := (v_el ->> 'catalogo_id')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Examen mal formado en la orden' USING ERRCODE = 'EX010';
      END;
      IF p_laboratorio_id IS NULL THEN
        RAISE EXCEPTION 'Una orden sin laboratorio solo admite exámenes escritos a mano' USING ERRCODE = 'EX013';
      END IF;
      -- mismo codigo para "no existe" y "es de otro laboratorio": no filtra filas ajenas
      SELECT c.nombre, c.activo INTO v_nombre, v_activo
        FROM public.examenes_catalogo c
       WHERE c.id = v_cat AND c.laboratorio_id = p_laboratorio_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'El examen seleccionado no pertenece al catálogo de este laboratorio' USING ERRCODE = 'EX011';
      END IF;
      IF NOT v_activo THEN
        RAISE EXCEPTION 'El examen seleccionado ya no está disponible en el catálogo' USING ERRCODE = 'EX012';
      END IF;
      IF v_cat = ANY (v_vistos_c) THEN
        RAISE EXCEPTION 'Hay exámenes repetidos en la orden' USING ERRCODE = 'EX014';
      END IF;
      v_vistos_c := v_vistos_c || v_cat;
      out_ord := v_i + 1; out_tipo := v_nombre; out_catalogo_id := v_cat;
      RETURN NEXT;
    ELSE
      IF jsonb_typeof(v_el -> 'nombre') <> 'string' THEN
        RAISE EXCEPTION 'Examen mal formado en la orden' USING ERRCODE = 'EX010';
      END IF;
      v_nom := btrim(v_el ->> 'nombre');
      IF v_nom = '' THEN
        RAISE EXCEPTION 'El nombre del examen no puede estar vacío' USING ERRCODE = 'EX015';
      END IF;
      IF length(v_nom) > 200 THEN
        RAISE EXCEPTION 'El nombre del examen es demasiado largo (máximo 200)' USING ERRCODE = 'EX016';
      END IF;
      v_clave := lower(v_nom);
      -- M.3: si esta en el catalogo ACTIVO del laboratorio, se elige de la lista (misma normalizacion
      -- que el UNIQUE del catalogo: lower(btrim())).
      IF p_laboratorio_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.examenes_catalogo c
            WHERE c.laboratorio_id = p_laboratorio_id AND c.activo AND lower(btrim(c.nombre)) = v_clave) THEN
        RAISE EXCEPTION 'Ese examen está en el catálogo: selecciónelo de la lista' USING ERRCODE = 'EX017';
      END IF;
      IF v_clave = ANY (v_vistos_n) THEN
        RAISE EXCEPTION 'Hay exámenes repetidos en la orden' USING ERRCODE = 'EX014';
      END IF;
      v_vistos_n := v_vistos_n || v_clave;
      out_ord := v_i + 1; out_tipo := v_nom; out_catalogo_id := NULL;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$;

-- ------------------------------------------------------------------------- (e) RPC del medico
CREATE FUNCTION public.crear_orden_examen_medico(p_paciente_id bigint, p_laboratorio_id uuid, p_items jsonb, p_instrucciones text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid         uuid;
  v_pac_nombre  text;
  v_pac_apell   text;
  v_instr       text;
  v_clin        uuid;
  v_clin_nombre text;
  v_med_nombre  text;
  v_nombre_pac  text;
  v_orden       uuid;
  v_tipos       text[];
  v_cats        uuid[];
  v_ids         integer[];
BEGIN
  -- (332) Unica via (desde la 333) para que un medico ordene examenes. Cabecera + items en una sola
  -- transaccion. Del cliente vienen solo: paciente (validado), laboratorio (validado, NULL = sin
  -- asignar), items e instrucciones. Todo lo demas se deriva aca.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicie sesión' USING ERRCODE = 'EX001';
  END IF;
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo un médico puede ordenar exámenes' USING ERRCODE = 'EX002';
  END IF;
  IF p_paciente_id IS NULL THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'EX003';
  END IF;
  SELECT pa.nombre, pa.apellido INTO v_pac_nombre, v_pac_apell FROM public.pacientes pa WHERE pa.id = p_paciente_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'EX003';
  END IF;
  -- Pertenencia: el mismo predicado de ordenes_medico_insert / emitir_receta (PR009).
  IF NOT COALESCE(
       private.medico_atiende_paciente(p_paciente_id)
    OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = p_paciente_id AND pa.medico_id = v_uid), false) THEN
    RAISE EXCEPTION 'No autorizado: no atiende a este paciente' USING ERRCODE = 'EX004';
  END IF;
  -- Laboratorio: el mismo universo que ofrece laboratorios_para_medico() (tipo, estado, pais).
  IF p_laboratorio_id IS NOT NULL AND NOT COALESCE(EXISTS (
       SELECT 1 FROM public.empresas_proveedoras e
        WHERE e.id = p_laboratorio_id AND e.tipo = 'laboratorio_clinico' AND e.estado = 'activa'
          AND e.pais_id = private.mi_pais()), false) THEN
    RAISE EXCEPTION 'Laboratorio no disponible para esta orden' USING ERRCODE = 'EX005';
  END IF;
  v_instr := NULLIF(btrim(p_instrucciones), '');
  IF length(v_instr) > 2000 THEN
    RAISE EXCEPTION 'Las instrucciones son demasiado largas (máximo 2000)' USING ERRCODE = 'EX020';
  END IF;

  -- items validados (EX008-EX017); si alguno falla todavia no se escribio nada
  SELECT array_agg(t.out_tipo ORDER BY t.out_ord), array_agg(t.out_catalogo_id ORDER BY t.out_ord)
    INTO v_tipos, v_cats
    FROM private.armar_items_orden_examen(p_laboratorio_id, p_items) t;

  -- derivados en el servidor
  SELECT m.clinica_id INTO v_clin FROM public.obtener_clinica_principal_medico(v_uid) m LIMIT 1;
  IF v_clin IS NOT NULL THEN
    SELECT c.nombre INTO v_clin_nombre FROM public.clinicas c WHERE c.id = v_clin;
  END IF;
  SELECT p.nombre_completo INTO v_med_nombre FROM public.perfiles p WHERE p.id = v_uid;
  v_nombre_pac := NULLIF(btrim(COALESCE(v_pac_nombre, '') || ' ' || COALESCE(v_pac_apell, '')), '');

  INSERT INTO public.ordenes_examen (laboratorio_id, clinica_id, medico_id, paciente_id, origen, prioridad,
                                     instrucciones, paciente_nombre, medico_nombre, clinica_nombre)
  VALUES (p_laboratorio_id, v_clin, v_uid, p_paciente_id, 'medico', 'normal',
          v_instr, v_nombre_pac, v_med_nombre, v_clin_nombre)
  RETURNING id INTO v_orden;

  WITH ins AS (
    INSERT INTO public.examenes (orden_id, paciente_id, medico_id, tipo, catalogo_id, descripcion, estado, prioridad,
                                 laboratorio_id, clinica_id, origen, paciente_nombre, medico_nombre, clinica_nombre)
    SELECT v_orden, p_paciente_id::integer, v_uid, i.tipo, i.cat, v_instr, 'pendiente', 'normal',
           p_laboratorio_id, v_clin, 'medico', v_nombre_pac, v_med_nombre, v_clin_nombre
      FROM unnest(v_tipos, v_cats) WITH ORDINALITY AS i(tipo, cat, ord) ORDER BY i.ord
    RETURNING id
  )
  SELECT array_agg(id ORDER BY id) INTO v_ids FROM ins;

  -- M.2: notificacion best-effort. El sub-bloque es un savepoint: si notificar_orden_lab falla se
  -- deshacen solo sus escrituras y la orden queda. Su gate (medico de la orden = auth.uid()) pasa
  -- porque auth.uid() sale del JWT, no de current_user.
  BEGIN
    PERFORM public.notificar_orden_lab(v_orden);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'crear_orden_examen_medico: notificar_orden_lab fallo para la orden % (% %)', v_orden, SQLSTATE, SQLERRM;
  END;

  RETURN jsonb_build_object('orden_id', v_orden, 'examen_ids', to_jsonb(v_ids), 'n_items', cardinality(v_ids));
END;
$function$;

-- ------------------------------------------------------------------------ (e) RPC del walk-in
CREATE FUNCTION public.crear_orden_examen_walkin(p_items jsonb, p_paciente_nombre text, p_paciente_documento text DEFAULT NULL::text, p_paciente_telefono text DEFAULT NULL::text, p_instrucciones text DEFAULT NULL::text, p_prioridad text DEFAULT 'normal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid   uuid;
  v_lab   uuid;
  v_nom   text;
  v_doc   text;
  v_tel   text;
  v_prio  text;
  v_instr text;
  v_orden uuid;
  v_tipos text[];
  v_cats  uuid[];
  v_ids   integer[];
BEGIN
  -- (332) Unica via (desde la 333) para registrar un paciente sin cita en el laboratorio. El
  -- laboratorio es el del llamante; los datos del paciente son texto del cliente (no hay
  -- paciente_id). Sin notificacion: notificar_orden_lab exige medico y paciente (PT003).
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicie sesión' USING ERRCODE = 'EX001';
  END IF;
  PERFORM private.exigir_empresa_activa();   -- 42501 si la cuenta o la empresa no estan activas (M4)
  v_lab := public.mi_empresa_proveedor();
  IF v_lab IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.empresas_proveedoras e WHERE e.id = v_lab AND e.tipo = 'laboratorio_clinico') THEN
    RAISE EXCEPTION 'No autorizado: su cuenta no pertenece a un laboratorio clínico activo' USING ERRCODE = 'EX006';
  END IF;
  IF NOT COALESCE(private.tiene_permiso('walkin_registrar'), false) THEN
    RAISE EXCEPTION 'No autorizado: no tiene permiso para registrar pacientes sin cita' USING ERRCODE = 'EX007';
  END IF;

  v_nom := btrim(p_paciente_nombre);
  v_doc := NULLIF(btrim(p_paciente_documento), '');
  v_tel := NULLIF(btrim(p_paciente_telefono), '');
  IF v_nom IS NULL OR v_nom = '' OR length(v_nom) > 200
     OR length(v_doc) > 50 OR length(v_tel) > 30 THEN
    RAISE EXCEPTION 'Datos del paciente inválidos (nombre obligatorio, máximo 200; documento máximo 50; teléfono máximo 30)'
      USING ERRCODE = 'EX018';
  END IF;
  v_prio := COALESCE(NULLIF(btrim(p_prioridad), ''), 'normal');
  IF v_prio NOT IN ('normal', 'urgente') THEN
    RAISE EXCEPTION 'Prioridad inválida (normal o urgente)' USING ERRCODE = 'EX019';
  END IF;
  v_instr := NULLIF(btrim(p_instrucciones), '');
  IF length(v_instr) > 2000 THEN
    RAISE EXCEPTION 'Las instrucciones son demasiado largas (máximo 2000)' USING ERRCODE = 'EX020';
  END IF;

  SELECT array_agg(t.out_tipo ORDER BY t.out_ord), array_agg(t.out_catalogo_id ORDER BY t.out_ord)
    INTO v_tipos, v_cats
    FROM private.armar_items_orden_examen(v_lab, p_items) t;

  INSERT INTO public.ordenes_examen (laboratorio_id, origen, prioridad, instrucciones,
                                     paciente_nombre, paciente_documento, paciente_telefono)
  VALUES (v_lab, 'walk_in', v_prio, v_instr, v_nom, v_doc, v_tel)
  RETURNING id INTO v_orden;

  WITH ins AS (
    INSERT INTO public.examenes (orden_id, laboratorio_id, tipo, catalogo_id, descripcion, prioridad, origen, estado,
                                 paciente_nombre, paciente_documento, paciente_telefono)
    SELECT v_orden, v_lab, i.tipo, i.cat, v_instr, v_prio, 'walk_in', 'recibida', v_nom, v_doc, v_tel
      FROM unnest(v_tipos, v_cats) WITH ORDINALITY AS i(tipo, cat, ord) ORDER BY i.ord
    RETURNING id
  )
  SELECT array_agg(id ORDER BY id) INTO v_ids FROM ins;

  RETURN jsonb_build_object('orden_id', v_orden, 'examen_ids', to_jsonb(v_ids), 'n_items', cardinality(v_ids));
END;
$function$;

-- EXECUTE: las RPCs solo para authenticated; el helper solo para postgres (lo llaman las RPCs).
REVOKE ALL ON FUNCTION private.armar_items_orden_examen(uuid, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.crear_orden_examen_medico(bigint, uuid, jsonb, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.crear_orden_examen_walkin(jsonb, text, text, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crear_orden_examen_medico(bigint, uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crear_orden_examen_walkin(jsonb, text, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------- (f) congelamiento
-- Grants por columna: de examenes el cliente solo actualiza lo que hoy usan cambiarEstado y
-- subirResultado (useLaboratorio.ts). Liberar/revertir son SECURITY DEFINER (owner postgres).
REVOKE UPDATE ON public.examenes FROM authenticated;
GRANT UPDATE (estado, fecha_resultado, resultados, archivo_url) ON public.examenes TO authenticated;

CREATE FUNCTION private.examenes_congelar_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- (332) tipo es el snapshot del nombre ordenado y catalogo_id su concepto: no cambian despues
  -- del INSERT, para nadie (tampoco SECURITY DEFINER ni postgres).
  IF NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.catalogo_id IS DISTINCT FROM OLD.catalogo_id THEN
    RAISE EXCEPTION 'El examen de una orden no se puede cambiar una vez creado' USING ERRCODE = 'EX022';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.examenes_congelar_identidad() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_examenes_congelar_identidad
  BEFORE UPDATE OF tipo, catalogo_id ON public.examenes
  FOR EACH ROW EXECUTE FUNCTION private.examenes_congelar_identidad();

-- ------------------------------------------------------------------------- (g) catalogo
REVOKE UPDATE ON public.examenes_catalogo FROM authenticated;
GRANT UPDATE (activo, categoria) ON public.examenes_catalogo TO authenticated;

-- ------------------------------------------------------------------------------ (h) M.7
REVOKE UPDATE ON public.ordenes_examen FROM authenticated;
DROP POLICY examenes_medico_update ON public.examenes;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; n int; r record;
BEGIN
  -- (a) columna, FK RESTRICT, indice
  SELECT format_type(a.atttypid, a.atttypmod) || CASE WHEN a.attnotnull THEN ' NN' ELSE '' END INTO x
    FROM pg_attribute a WHERE a.attrelid = 'public.examenes'::regclass AND a.attname = 'catalogo_id' AND NOT a.attisdropped;
  IF x IS DISTINCT FROM 'uuid' THEN bad := bad||'columna catalogo_id='||COALESCE(x,'NO EXISTE')||'; '; END IF;
  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.examenes'::regclass AND conname = 'examenes_catalogo_id_fkey' AND contype = 'f'
     AND confrelid = 'public.examenes_catalogo'::regclass AND confdeltype = 'r';
  IF n <> 1 THEN bad := bad||'FK RESTRICT='||n||'; '; END IF;
  IF to_regclass('public.idx_examenes_catalogo') IS NULL THEN bad := bad||'falta idx_examenes_catalogo; '; END IF;
  -- (b) UNIQUE
  SELECT count(*) INTO n FROM pg_index i WHERE i.indexrelid = to_regclass('public.ux_examenes_catalogo_lab_nombre') AND i.indisunique;
  IF n <> 1 THEN bad := bad||'falta UNIQUE del catalogo; '; END IF;
  -- (c) backfill 10/4
  SELECT count(*) INTO n FROM public.examenes WHERE catalogo_id IS NOT NULL;
  IF n <> 10 THEN bad := bad||'backfill con catalogo_id='||n||'; '; END IF;
  SELECT count(*) INTO n FROM public.examenes WHERE catalogo_id IS NULL AND id IN (4, 158, 254, 720);
  IF n <> 4 THEN bad := bad||'backfill NULL de texto libre='||n||'; '; END IF;
  -- (d)(e) funciones nuevas
  FOR r IN SELECT p.oid, p.oid::regprocedure::text AS f, p.prosecdef, p.proconfig::text AS cfg,
                  COALESCE((SELECT string_agg(CASE WHEN x2.grantee = 0 THEN 'PUBLIC' ELSE x2.grantee::regrole::text END, ',' ORDER BY CASE WHEN x2.grantee = 0 THEN 'PUBLIC' ELSE x2.grantee::regrole::text END)
                              FROM aclexplode(p.proacl) x2 WHERE x2.privilege_type = 'EXECUTE'), '') AS ex
             FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
            WHERE (ns.nspname, p.proname) IN (('public','crear_orden_examen_medico'), ('public','crear_orden_examen_walkin'),
                                               ('private','armar_items_orden_examen'), ('private','examenes_congelar_identidad')) LOOP
    IF NOT r.prosecdef THEN bad := bad||r.f||' no es SECURITY DEFINER; '; END IF;
    IF r.cfg IS DISTINCT FROM '{"search_path=\"\""}' THEN bad := bad||r.f||' search_path '||COALESCE(r.cfg,'NULL')||'; '; END IF;
    IF r.f LIKE 'crear_orden_examen_%' AND r.ex <> 'authenticated,postgres' THEN bad := bad||r.f||' EXECUTE='||r.ex||'; '; END IF;
    IF r.f LIKE 'private.%' AND r.ex <> 'postgres' THEN bad := bad||r.f||' EXECUTE='||r.ex||'; '; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc p WHERE p.oid IN (
    to_regprocedure('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)'),
    to_regprocedure('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)'),
    to_regprocedure('private.armar_items_orden_examen(uuid,jsonb)'),
    to_regprocedure('private.examenes_congelar_identidad()'));
  IF n <> 4 THEN bad := bad||'funciones nuevas con la firma esperada='||n||'; '; END IF;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE (ns.nspname, p.proname) IN (('public','crear_orden_examen_medico'), ('public','crear_orden_examen_walkin'),
                                      ('private','armar_items_orden_examen'), ('private','examenes_congelar_identidad'));
  IF n <> 4 THEN bad := bad||'firmas de las funciones nuevas='||n||'; '; END IF;
  -- (f) trigger + grants por columna
  SELECT count(*) INTO n FROM pg_trigger WHERE tgrelid = 'public.examenes'::regclass AND tgname = 'trg_examenes_congelar_identidad'
     AND tgfoid = 'private.examenes_congelar_identidad()'::regprocedure AND tgenabled = 'O';
  IF n <> 1 THEN bad := bad||'trigger de congelamiento='||n||'; '; END IF;
  IF has_table_privilege('authenticated', 'public.examenes', 'UPDATE') THEN bad := bad||'examenes: UPDATE de tabla; '; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO x FROM pg_attribute a
   WHERE a.attrelid = 'public.examenes'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.examenes', a.attname, 'UPDATE');
  IF x IS DISTINCT FROM 'archivo_url,estado,fecha_resultado,resultados' THEN bad := bad||'examenes UPDATE por columna='||COALESCE(x,'-')||'; '; END IF;
  -- (g) catalogo
  IF has_table_privilege('authenticated', 'public.examenes_catalogo', 'UPDATE') THEN bad := bad||'catalogo: UPDATE de tabla; '; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO x FROM pg_attribute a
   WHERE a.attrelid = 'public.examenes_catalogo'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.examenes_catalogo', a.attname, 'UPDATE');
  IF x IS DISTINCT FROM 'activo,categoria' THEN bad := bad||'catalogo UPDATE por columna='||COALESCE(x,'-')||'; '; END IF;
  -- (h) M.7
  IF has_table_privilege('authenticated', 'public.ordenes_examen', 'UPDATE') THEN bad := bad||'ordenes_examen: UPDATE de tabla; '; END IF;
  SELECT count(*) INTO n FROM pg_attribute a WHERE a.attrelid = 'public.ordenes_examen'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.ordenes_examen', a.attname, 'UPDATE');
  IF n <> 0 THEN bad := bad||'ordenes_examen UPDATE por columna='||n||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'examenes' AND policyname = 'examenes_medico_update') THEN
    bad := bad||'sigue examenes_medico_update; '; END IF;
  -- lo que NO toca la 332: INSERT directo todavia vivo (el front viejo sigue funcionando)
  IF NOT has_table_privilege('authenticated', 'public.examenes', 'INSERT') OR NOT has_table_privilege('authenticated', 'public.ordenes_examen', 'INSERT') THEN
    bad := bad||'se perdio el INSERT de tabla (es de la 333); '; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'public'
     AND ((tablename = 'examenes' AND policyname = 'examenes_medico_insert') OR (tablename = 'ordenes_examen' AND policyname = 'ordenes_medico_insert'));
  IF n <> 2 THEN bad := bad||'policies de INSERT presentes='||n||' (son de la 333); '; END IF;
  -- las 9 funciones previas, sin cambios
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG332 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
