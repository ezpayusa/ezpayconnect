-- =====================================================================================================================
-- MIG 395 — recetas: vínculo con la cita, folio persistido y control de alergias (H2, H20, H12 backend; textos PR de H13).
--
-- Por qué:
--   H2  — la receta no sabía de qué consulta salió: emitir_receta no recibía la cita. Ahora acepta p_cita_id (opcional) y
--         lo guarda en recetas.cita_id, validando que la cita sea de ese paciente, del médico que emite y que no esté
--         'solicitada', 'cancelada' ni 'no_show' (PR012).
--   H20 — el folio se armaba en 316:179 (cédula-correlativo-fecha) y se descartaba: solo viajaba en la respuesta. Ahora
--         se guarda en recetas.folio con el mismo valor, y la respuesta lo devuelve también como 'folio'.
--   H12 — nada impedía recetar un medicamento al que el paciente es alérgico. Si un término de pacientes.alergias
--         coincide con el medicamento, la emisión exige un motivo de confirmación por ítem (PR011) y deja una fila
--         append-only en receta_alertas_alergia (UPDATE/DELETE dan PR013). alergias_en_receta() deja al front avisar
--         antes de emitir, con el mismo gate que emitir_receta.
--   H13 — textos de error de emitir_receta en español neutro, con tilde y tuteo; los errcodes no cambian.
--
-- Qué hace (y nada más):
--   1. recetas.cita_id bigint REFERENCES citas(id) ON DELETE RESTRICT (nullable, con índice) y recetas.folio text
--      (nullable). Sin UNIQUE en folio: el correlativo es por médico y los médicos sin cédula comparten el prefijo
--      'SINCED' (hoy los 14 de prod), así que dos médicos chocan con su receta n.º 1 del mismo día. Sin GRANT de
--      columna: authenticated tiene SELECT DE TABLA sobre recetas (relacl authenticated=r, sin attacl), así que lee
--      las dos columnas nuevas, y no tiene INSERT ni UPDATE (solo las escribe emitir_receta).
--   2. private.terminos_alergia(text) (IMMUTABLE), private.coincidencia_alergia(bigint, bigint) (STABLE, INVOKER; la
--      llaman las dos DEFINER) y public.alergias_en_receta(bigint, bigint[]) (STABLE, DEFINER, máximo 50 ids; gate de
--      emitir_receta: PR001 sin sesión, PR002 no es médico, PR003 paciente, PR009 no lo atiende; más de 50 ids PR004).
--      Normalización: minúsculas, sin tildes (translate), todo lo que no es [a-z0-9] pasa a espacio. Los términos se
--      parten por , ; / salto de línea « »; se descartan los de menos de 4 caracteres y las negaciones «ninguna»,
--      «ninguno», «niega», «no refiere», «sin alergias», «desconocida», «n/a». Coincide si el término, o su singular
--      (sin -s o sin -es, de 4 caracteres o más), empieza una palabra de nombre_generico || ' ' || nombre_comercial.
--   3. public.receta_alertas_alergia (append-only): id IDENTITY; FKs RESTRICT a recetas, receta_items, pacientes,
--      perfiles (medico_id: recetas.medico_id no tiene FK y el gate de rol es por perfiles) y medicamentos; motivo de
--      5 a 500 caracteres. RLS con UNA policy SELECT TO authenticated (médico autor o super_admin). authenticated solo
--      SELECT, service_role S/I/U/D, anon y PUBLIC nada; la secuencia IDENTITY sin nada para authenticated/anon/PUBLIC
--      (P928). Trigger BEFORE UPDATE OR DELETE -> PR013.
--   4. emitir_receta: DROP de (bigint,text,jsonb) + CREATE de (bigint,text,jsonb,bigint DEFAULT NULL). Cuerpo = el de
--      la 316 más: PR012 (cita) antes de los ítems; PR011 (alergia sin motivo) dentro de la validación por ítem; las
--      dos ANTES de consumir el correlativo. recetas lleva cita_id y folio. Los ítems se insertan de a uno (mismos
--      valores que el INSERT … SELECT de la 316) para conocer el id de cada uno, y después va una fila de auditoría
--      por coincidencia confirmada. La respuesta suma 'folio' (= numero_formateado) sin quitar claves. Una llamada
--      con 3 argumentos (posicional o por nombre, como la del front) sigue resolviendo a esta función.
--   Los cuerpos de las funciones no llevan comentarios de línea completa: el runner del harness los quita antes de
--   enviar, y con ellos el md5(prosrc) de un dry-run inyectado no sería el del apply real.
--   Errcodes: PR011 alergia sin motivo, PR012 cita inválida, PR013 auditoría inmutable (PR001-PR010 en uso; PR010 es
--   del despacho, mig 329). MIG95 = guarda de la migración.
--
-- Estado ANTES, medido el 19-nov-2026 18:02 UTC (post-392):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... ba4eb8a509c74d2ff82d61193ec6c201 415
--   ACL de funciones (solo privilegios), public/private .......................... 8fef2a52615f811185465e5ea088d16e 415
--   ACL de relaciones de public ................................................... e80ed9f7e17759b9196a8f5ce91996d5 2435
--   ACL de secuencias de public ................................................... fdaa79023984e271fe2922f357fb7a98 232
--   policies public/private/storage ............................................... 83a71d544e684f90ace0f0dc834230cc 308
--   emitir_receta(bigint,text,jsonb): md5(prosrc) 74d7013aeea17659bbafb84d780d644b, DEFINER, search_path="",
--   ACL {postgres,authenticated,service_role}=X, una sola sobrecarga.
-- Huellas post-395: ver el dry-run (en el PR). Rollback: supabase/migrations/395_rollback.sql (va antes que 392_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/395_recetas_cita_folio_alergias.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- emitir_receta: una sola sobrecarga, la de la 316
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'emitir_receta') <> 1 THEN
    bad := bad||'emitir_receta no tiene exactamente una sobrecarga; ';
  END IF;
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.emitir_receta(bigint,text,jsonb)'));
  IF v IS DISTINCT FROM '74d7013aeea17659bbafb84d780d644b true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'emitir_receta distinta de la 316 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  -- lo nuevo no existe
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attname IN ('cita_id', 'folio') AND NOT a.attisdropped) THEN
    bad := bad||'recetas ya tiene cita_id o folio; ';
  END IF;
  IF to_regclass('public.receta_alertas_alergia') IS NOT NULL THEN bad := bad||'receta_alertas_alergia ya existe; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE (n.nspname, p.proname) IN (('public', 'alergias_en_receta'), ('private', 'terminos_alergia'),
                                               ('private', 'coincidencia_alergia'), ('private', 'receta_alertas_alergia_inmutable'))) THEN
    bad := bad||'alguna función nueva ya existe; ';
  END IF;
  -- tipos y privilegios de los que depende el diseño
  IF (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a WHERE a.attrelid = 'public.citas'::regclass AND a.attname = 'id') IS DISTINCT FROM 'bigint'
     OR (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attname = 'id') IS DISTINCT FROM 'bigint'
     OR (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a WHERE a.attrelid = 'public.pacientes'::regclass AND a.attname = 'alergias' AND NOT a.attisdropped) IS DISTINCT FROM 'text' THEN
    bad := bad||'tipos de citas.id / recetas.id / pacientes.alergias distintos de los medidos; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.recetas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
    bad := bad||'relacl o attacl de recetas distintos de los medidos; ';
  END IF;
  -- errcodes nuevos libres
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
              AND p.prosrc ~ '''PR01[123]''') THEN
    bad := bad||'PR011/PR012/PR013 ya en uso; ';
  END IF;

  -- huellas post-392 (19-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba4eb8a509c74d2ff82d61193ec6c201 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e80ed9f7e17759b9196a8f5ce91996d5 2435' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'fdaa79023984e271fe2922f357fb7a98 232' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '83a71d544e684f90ace0f0dc834230cc 308' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG95: precondición: %', bad USING ERRCODE = 'MIG95';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) recetas: cita_id y folio
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.recetas
  ADD COLUMN cita_id bigint CONSTRAINT recetas_cita_id_fkey REFERENCES public.citas(id) ON DELETE RESTRICT,
  ADD COLUMN folio text;
CREATE INDEX recetas_cita_id_idx ON public.recetas (cita_id);
COMMENT ON COLUMN public.recetas.cita_id IS 'Mig 395: cita de la que sale la receta (opcional). Solo la escribe emitir_receta (PR012).';
COMMENT ON COLUMN public.recetas.folio IS 'Mig 395: folio cédula-correlativo-fecha armado al emitir (antes solo viajaba en la respuesta). Sin UNIQUE: los médicos sin cédula comparten el prefijo SINCED.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Alergias: términos, coincidencia y consulta previa
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION private.terminos_alergia(p_texto text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT COALESCE(array_agg(DISTINCT z.t ORDER BY z.t), ARRAY[]::text[])
    FROM (SELECT btrim(regexp_replace(x.p, '[^a-z0-9]+', ' ', 'g')) AS t
            FROM regexp_split_to_table(
                   translate(lower(btrim(COALESCE(p_texto, ''))),
                             'ÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇáàäâéèëêíìïîóòöôúùüûñç',
                             'aaaaeeeeiiiioooouuuuncaaaaeeeeiiiioooouuuunc'),
                   E'[,;/\\n\\r«»]') AS x(p)) z
   WHERE char_length(z.t) >= 4
     AND z.t NOT IN ('ninguna', 'ninguno', 'niega', 'no refiere', 'sin alergias', 'desconocida', 'n/a')
$function$;

CREATE FUNCTION private.coincidencia_alergia(p_paciente_id bigint, p_medicamento_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT t.termino
    FROM public.pacientes pa
    JOIN public.medicamentos m ON m.id = p_medicamento_id
    CROSS JOIN LATERAL unnest(private.terminos_alergia(pa.alergias)) AS t(termino)
    CROSS JOIN LATERAL (SELECT ' '||btrim(regexp_replace(
                          translate(lower(COALESCE(m.nombre_generico, '')||' '||COALESCE(m.nombre_comercial, '')),
                                    'ÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇáàäâéèëêíìïîóòöôúùüûñç',
                                    'aaaaeeeeiiiioooouuuuncaaaaeeeeiiiioooouuuunc'),
                          '[^a-z0-9]+', ' ', 'g')) AS texto) AS nm
   WHERE pa.id = p_paciente_id
     AND EXISTS (SELECT 1
                   FROM unnest(ARRAY[t.termino,
                                     CASE WHEN t.termino LIKE '%es' THEN left(t.termino, -2) END,
                                     CASE WHEN t.termino LIKE '%s' THEN left(t.termino, -1) END]) AS c(cand)
                  WHERE char_length(c.cand) >= 4
                    AND position(' '||c.cand IN nm.texto) > 0)
   ORDER BY t.termino
   LIMIT 1
$function$;

CREATE FUNCTION public.alergias_en_receta(p_paciente_id bigint, p_medicamento_ids bigint[])
 RETURNS TABLE(medicamento_id bigint, alergia text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PR001';
  END IF;
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'Solo un médico puede emitir recetas' USING ERRCODE = 'PR002';
  END IF;
  IF p_paciente_id IS NULL THEN
    RAISE EXCEPTION 'Paciente requerido' USING ERRCODE = 'PR003';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pacientes WHERE id = p_paciente_id) THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'PR003';
  END IF;
  IF NOT (
       private.medico_atiende_paciente(p_paciente_id)
    OR EXISTS (SELECT 1 FROM public.pacientes pa
                WHERE pa.id = p_paciente_id AND pa.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No atiendes a este paciente' USING ERRCODE = 'PR009';
  END IF;
  IF p_medicamento_ids IS NULL THEN
    RETURN;
  END IF;
  IF cardinality(p_medicamento_ids) > 50 THEN
    RAISE EXCEPTION 'El formato de los medicamentos no es válido' USING ERRCODE = 'PR004';
  END IF;
  RETURN QUERY
    SELECT d.id, c.termino
      FROM (SELECT DISTINCT x.id FROM unnest(p_medicamento_ids) AS x(id) WHERE x.id IS NOT NULL) AS d
      CROSS JOIN LATERAL (SELECT private.coincidencia_alergia(p_paciente_id, d.id) AS termino) AS c
     WHERE c.termino IS NOT NULL
     ORDER BY d.id;
END;
$function$;

COMMENT ON FUNCTION public.alergias_en_receta(bigint, bigint[]) IS
  'Mig 395: medicamentos (de hasta 50 ids) que coinciden con una alergia registrada del paciente, con el término. Mismo gate que emitir_receta (PR001, PR002, PR003, PR009); más de 50 ids PR004.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) Auditoría de alergias confirmadas (append-only)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE public.receta_alertas_alergia (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receta_id         bigint      NOT NULL CONSTRAINT receta_alertas_alergia_receta_id_fkey      REFERENCES public.recetas(id)      ON DELETE RESTRICT,
  receta_item_id    bigint      NOT NULL CONSTRAINT receta_alertas_alergia_receta_item_id_fkey REFERENCES public.receta_items(id) ON DELETE RESTRICT,
  paciente_id       bigint      NOT NULL CONSTRAINT receta_alertas_alergia_paciente_id_fkey    REFERENCES public.pacientes(id)    ON DELETE RESTRICT,
  medico_id         uuid        NOT NULL CONSTRAINT receta_alertas_alergia_medico_id_fkey      REFERENCES public.perfiles(id)     ON DELETE RESTRICT,
  medicamento_id    bigint      NOT NULL CONSTRAINT receta_alertas_alergia_medicamento_id_fkey REFERENCES public.medicamentos(id) ON DELETE RESTRICT,
  termino_alergia   text        NOT NULL,
  alergias_snapshot text        NOT NULL,
  motivo            text        NOT NULL CONSTRAINT receta_alertas_alergia_motivo_check CHECK (char_length(motivo) BETWEEN 5 AND 500),
  confirmada_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX receta_alertas_alergia_receta_id_idx ON public.receta_alertas_alergia (receta_id);
COMMENT ON TABLE public.receta_alertas_alergia IS
  'Mig 395 (H12). Append-only: una fila por ítem de receta emitido pese a coincidir con una alergia registrada, con el motivo que confirmó el médico. La escribe solo emitir_receta; UPDATE y DELETE dan PR013 para todos.';

ALTER TABLE public.receta_alertas_alergia ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.receta_alertas_alergia FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.receta_alertas_alergia TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.receta_alertas_alergia TO service_role;

-- la secuencia IDENTITY: nada para authenticated/anon/PUBLIC (P928; el INSERT por IDENTITY no chequea privilegios)
DO $secuencia$
DECLARE v_seq text := pg_get_serial_sequence('public.receta_alertas_alergia', 'id');
BEGIN
  IF v_seq IS NULL THEN RAISE EXCEPTION 'MIG95: receta_alertas_alergia.id sin secuencia IDENTITY' USING ERRCODE = 'MIG95'; END IF;
  EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated', v_seq);
END $secuencia$;

CREATE POLICY receta_alertas_alergia_select ON public.receta_alertas_alergia
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((medico_id = auth.uid()) OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false));

CREATE FUNCTION private.receta_alertas_alergia_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Las alertas de alergia de una receta no se modifican ni se borran (intento de %)', TG_OP USING ERRCODE = 'PR013';
END;
$function$;

CREATE TRIGGER trg_receta_alertas_alergia_inmutable
  BEFORE UPDATE OR DELETE ON public.receta_alertas_alergia
  FOR EACH ROW EXECUTE FUNCTION private.receta_alertas_alergia_inmutable();

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) emitir_receta con cita, folio y alergias
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION public.emitir_receta(bigint, text, jsonb);

CREATE FUNCTION public.emitir_receta(p_paciente_id bigint, p_instrucciones_generales text, p_items jsonb, p_cita_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid        uuid;
  v_num        bigint;
  v_receta_id  bigint;
  v_pais_id    uuid;
  v_nombre     text;
  v_cedula     text;
  v_n_items    int;
  v_item       jsonb;
  v_med_id     bigint;
  v_categoria  text;
  v_acuse      text;
  v_regulado   boolean;
  v_activo     boolean;
  v_ord        bigint;
  v_med_nombre text;
  v_alergias   text;
  v_termino    text;
  v_motivo     text;
  v_alertas    jsonb := '[]'::jsonb;
  v_item_id    bigint;
  v_item_ids   bigint[] := ARRAY[]::bigint[];
  v_folio      text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PR001';
  END IF;
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'Solo un médico puede emitir recetas' USING ERRCODE = 'PR002';
  END IF;
  IF p_paciente_id IS NULL THEN
    RAISE EXCEPTION 'Paciente requerido' USING ERRCODE = 'PR003';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pacientes WHERE id = p_paciente_id) THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'PR003';
  END IF;
  IF NOT (
       private.medico_atiende_paciente(p_paciente_id)
    OR EXISTS (SELECT 1 FROM public.pacientes pa
                WHERE pa.id = p_paciente_id AND pa.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No atiendes a este paciente' USING ERRCODE = 'PR009';
  END IF;
  IF p_cita_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.citas ci
        WHERE ci.id = p_cita_id AND ci.paciente_id = p_paciente_id AND ci.medico_id = v_uid
          AND ci.estado IS NOT NULL AND ci.estado NOT IN ('solicitada', 'cancelada', 'no_show')
  ) THEN
    RAISE EXCEPTION 'La cita indicada no es válida para esta receta' USING ERRCODE = 'PR012';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'El formato de los medicamentos no es válido' USING ERRCODE = 'PR004';
  END IF;
  v_n_items := jsonb_array_length(p_items);
  IF v_n_items = 0 THEN
    RAISE EXCEPTION 'La receta debe tener al menos un medicamento' USING ERRCODE = 'PR004';
  END IF;
  v_alergias := (SELECT pa.alergias FROM public.pacientes pa WHERE pa.id = p_paciente_id);
  FOR v_item, v_ord IN SELECT t.e, t.o FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, o)
  LOOP
    v_med_id := NULLIF(v_item->>'medicamento_id', '')::bigint;
    IF v_med_id IS NULL THEN
      RAISE EXCEPTION 'El medicamento "%" no está en el catálogo',
        COALESCE(v_item->>'nombre_medicamento', '?') USING ERRCODE = 'PR005';
    END IF;
    SELECT m.categoria_regulatoria, m.activo, m.nombre_generico INTO v_categoria, v_activo, v_med_nombre
      FROM public.medicamentos m WHERE m.id = v_med_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El medicamento "%" no está en el catálogo',
        COALESCE(v_item->>'nombre_medicamento', v_med_id::text) USING ERRCODE = 'PR005';
    END IF;
    IF NOT COALESCE(v_activo, false) THEN
      RAISE EXCEPTION 'El medicamento "%" no está activo en el catálogo',
        COALESCE(v_item->>'nombre_medicamento', v_med_id::text) USING ERRCODE = 'PR008';
    END IF;
    IF COALESCE(NULLIF(trim(v_item->>'dosis'), ''), '') = '' THEN
      RAISE EXCEPTION 'Dosis requerida en "%"', COALESCE(v_item->>'nombre_medicamento','?') USING ERRCODE = 'PR006';
    END IF;
    IF COALESCE(NULLIF(trim(v_item->>'frecuencia'), ''), '') = '' THEN
      RAISE EXCEPTION 'Frecuencia requerida en "%"', COALESCE(v_item->>'nombre_medicamento','?') USING ERRCODE = 'PR006';
    END IF;
    v_regulado := (SELECT c.requiere_acuse FROM public.medicamentos_categorias c WHERE c.codigo = v_categoria);
    v_acuse    := NULLIF(trim(COALESCE(v_item->>'acuse_iniciales','')), '');
    IF COALESCE(v_regulado, false) AND v_acuse IS NULL THEN
      RAISE EXCEPTION 'El medicamento "%" es % y requiere tus iniciales',
        COALESCE(v_item->>'nombre_medicamento','?'), v_categoria USING ERRCODE = 'PR007';
    END IF;
    v_termino := private.coincidencia_alergia(p_paciente_id, v_med_id);
    IF v_termino IS NOT NULL THEN
      v_motivo := btrim(COALESCE(v_item->>'alergia_confirmacion_motivo', ''), E' \t\r\n');
      IF char_length(v_motivo) NOT BETWEEN 5 AND 500 THEN
        RAISE EXCEPTION 'El medicamento "%" coincide con la alergia registrada "%". Confirma la prescripción con un motivo.',
          COALESCE(v_med_nombre, v_item->>'nombre_medicamento', v_med_id::text), v_termino USING ERRCODE = 'PR011';
      END IF;
      v_alertas := v_alertas || jsonb_build_object('ord', v_ord, 'medicamento_id', v_med_id, 'termino', v_termino, 'motivo', v_motivo);
    END IF;
  END LOOP;
  SELECT COALESCE(pf.nombre_completo, pf.nombre), pf.pais_id
    INTO v_nombre, v_pais_id
    FROM public.perfiles pf WHERE pf.id = v_uid;
  SELECT md.cedula_profesional INTO v_cedula
    FROM public.medicos md WHERE md.id = v_uid;
  IF v_cedula IS NULL THEN
    RAISE WARNING 'emitir_receta: medico % sin cedula_profesional (folio degradado)', v_uid;
  END IF;
  INSERT INTO public.medico_correlativos (medico_id, ultimo_numero)
  VALUES (v_uid, 1)
  ON CONFLICT (medico_id) DO UPDATE
    SET ultimo_numero = public.medico_correlativos.ultimo_numero + 1,
        updated_at    = now()
  RETURNING ultimo_numero INTO v_num;
  v_folio := COALESCE(v_cedula, 'SINCED') || '-' || lpad(v_num::text, 6, '0') || '-' || to_char(now(), 'YYYYMMDD');
  INSERT INTO public.recetas (paciente_id, instrucciones_generales, medico_id, estado, pais_id, numero_correlativo, cita_id, folio)
  VALUES (p_paciente_id, NULLIF(trim(COALESCE(p_instrucciones_generales,'')), ''), v_uid, 'activa', v_pais_id, v_num, p_cita_id, v_folio)
  RETURNING id INTO v_receta_id;
  FOR v_item, v_ord IN SELECT t.e, t.o FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, o)
  LOOP
    INSERT INTO public.receta_items
      (receta_id, medicamento_id, nombre_medicamento, dosis, frecuencia, duracion,
       instrucciones, cantidad, farmacia_id, precio_unitario, stock_actual,
       acuse_iniciales, acuse_at, acuse_categoria)
    VALUES (
      v_receta_id,
      (v_item->>'medicamento_id')::bigint,
      v_item->>'nombre_medicamento',
      v_item->>'dosis',
      v_item->>'frecuencia',
      NULLIF(v_item->>'duracion',''),
      NULLIF(v_item->>'instrucciones',''),
      COALESCE(NULLIF(v_item->>'cantidad','')::int, 1),
      NULLIF(v_item->>'farmacia_id','')::int,
      NULLIF(v_item->>'precio_unitario','')::numeric,
      NULLIF(v_item->>'stock_actual','')::int,
      NULLIF(trim(COALESCE(v_item->>'acuse_iniciales','')), ''),
      CASE WHEN NULLIF(trim(COALESCE(v_item->>'acuse_iniciales','')), '') IS NOT NULL THEN now() END,
      (SELECT m.categoria_regulatoria FROM public.medicamentos m WHERE m.id = (v_item->>'medicamento_id')::bigint))
    RETURNING id INTO v_item_id;
    v_item_ids := v_item_ids || v_item_id;
  END LOOP;
  INSERT INTO public.receta_alertas_alergia
    (receta_id, receta_item_id, paciente_id, medico_id, medicamento_id, termino_alergia, alergias_snapshot, motivo)
  SELECT v_receta_id, v_item_ids[(a->>'ord')::int], p_paciente_id, v_uid, (a->>'medicamento_id')::bigint,
         a->>'termino', v_alergias, a->>'motivo'
    FROM jsonb_array_elements(v_alertas) a;
  INSERT INTO public.recetas_avanzadas
    (receta_base_id, paciente_id, medico_id, firma_digital, estado_dispensacion, emitida_at)
  VALUES
    (v_receta_id, p_paciente_id::text, v_uid::text,
     'FIRMADO-' || COALESCE(v_nombre, 'Medico') || '-' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
     'pendiente', now());
  RETURN jsonb_build_object(
    'receta_id',          v_receta_id,
    'numero_correlativo', v_num,
    'numero_formateado',  v_folio,
    'folio',              v_folio
  );
END;
$function$;

COMMENT ON FUNCTION public.emitir_receta(bigint, text, jsonb, bigint) IS
  'Emite una receta. Gates: PR001 sesion, PR002 rol medico, PR003 paciente existe, PR009 PERTENENCIA (mig 316: medico_atiende_paciente OR pacientes.medico_id=auth.uid), PR012 cita (mig 395: del paciente, del medico, no solicitada/cancelada/no_show), PR004-PR008 items, PR011 alergia sin motivo (mig 395). Todo antes de consumir el correlativo. Persiste cita_id y folio, y audita en receta_alertas_alergia cada alergia confirmada.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 5) ACL de las funciones nuevas o recreadas
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.emitir_receta(bigint, text, jsonb, bigint)    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emitir_receta(bigint, text, jsonb, bigint) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.alergias_en_receta(bigint, bigint[])          FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.alergias_en_receta(bigint, bigint[])       TO authenticated, service_role;
REVOKE ALL ON FUNCTION private.terminos_alergia(text)                       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.coincidencia_alergia(bigint, bigint)         FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.receta_alertas_alergia_inmutable()           FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- emitir_receta: una sola sobrecarga, con la firma exacta
  IF (SELECT string_agg(pg_get_function_identity_arguments(p.oid), ' || ') FROM pg_proc p
       WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'emitir_receta')
     IS DISTINCT FROM 'p_paciente_id bigint, p_instrucciones_generales text, p_items jsonb, p_cita_id bigint' THEN
    bad := bad||'sobrecargas de emitir_receta: '||COALESCE((SELECT string_agg(pg_get_function_identity_arguments(p.oid), ' || ') FROM pg_proc p
       WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'emitir_receta'), '-')||'; ';
  END IF;
  IF (SELECT pg_get_function_arguments(p.oid) FROM pg_proc p WHERE p.oid = to_regprocedure('public.emitir_receta(bigint,text,jsonb,bigint)'))
     IS DISTINCT FROM 'p_paciente_id bigint, p_instrucciones_generales text, p_items jsonb, p_cita_id bigint DEFAULT NULL::bigint' THEN
    bad := bad||'p_cita_id sin DEFAULT NULL; ';
  END IF;
  -- las 5 funciones: DEFINER / volatilidad / search_path vacío / ACL exacta
  FOR r IN SELECT * FROM (VALUES
      ('public.emitir_receta(bigint,text,jsonb,bigint)', 'true v {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.alergias_en_receta(bigint,bigint[])',      'true s {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.terminos_alergia(text)',                  'false i {"search_path=\"\""} {postgres=X/postgres}'),
      ('private.coincidencia_alergia(bigint,bigint)',     'false s {"search_path=\"\""} {postgres=X/postgres}'),
      ('private.receta_alertas_alergia_inmutable()',      'false v {"search_path=\"\""} {postgres=X/postgres}')) AS t(firma, esperado)
  LOOP
    v := (SELECT p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||r.firma||' = '||COALESCE(v, 'no existe')||'; '; END IF;
  END LOOP;

  -- recetas: columnas nuevas, FK RESTRICT, índice; authenticated sin INSERT/UPDATE en ellas; SELECT de tabla intacto
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod)||':'||(NOT a.attnotnull)::text, ',' ORDER BY a.attname)
        FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attname IN ('cita_id', 'folio') AND NOT a.attisdropped)
     IS DISTINCT FROM 'cita_id:bigint:true,folio:text:true' THEN
    bad := bad||'columnas cita_id/folio de recetas; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.recetas'::regclass AND c.conname = 'recetas_cita_id_fkey'
                  AND c.contype = 'f' AND c.confrelid = 'public.citas'::regclass AND c.confdeltype = 'r'
                  AND pg_get_constraintdef(c.oid) = 'FOREIGN KEY (cita_id) REFERENCES citas(id) ON DELETE RESTRICT') THEN
    bad := bad||'FK recetas_cita_id_fkey; ';
  END IF;
  IF (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'recetas_cita_id_idx')
     IS DISTINCT FROM 'CREATE INDEX recetas_cita_id_idx ON public.recetas USING btree (cita_id)' THEN
    bad := bad||'índice recetas_cita_id_idx; ';
  END IF;
  IF has_column_privilege('authenticated', 'public.recetas', 'cita_id', 'INSERT') OR has_column_privilege('authenticated', 'public.recetas', 'cita_id', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.recetas', 'folio', 'INSERT') OR has_column_privilege('authenticated', 'public.recetas', 'folio', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.recetas', 'cita_id', 'SELECT') OR NOT has_column_privilege('authenticated', 'public.recetas', 'folio', 'SELECT') THEN
    bad := bad||'privilegios de authenticated sobre cita_id/folio; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.recetas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
    bad := bad||'relacl/attacl de recetas cambió; ';
  END IF;

  -- receta_alertas_alergia: RLS, relacl exacta, sin attacl, una policy SELECT, trigger, FKs RESTRICT, secuencia
  IF (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'public.receta_alertas_alergia'::regclass) IS DISTINCT FROM true THEN
    bad := bad||'receta_alertas_alergia sin RLS; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.receta_alertas_alergia'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwd/postgres}' THEN
    bad := bad||'relacl de receta_alertas_alergia '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.receta_alertas_alergia'::regclass), '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.receta_alertas_alergia'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
    bad := bad||'receta_alertas_alergia con privilegios por columna; ';
  END IF;
  IF (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
            ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n')
        FROM pg_policy pl WHERE pl.polrelid = 'public.receta_alertas_alergia'::regclass)
     IS DISTINCT FROM 'receta_alertas_alergia_select|r|true|{authenticated}|((medico_id = auth.uid()) OR COALESCE(private.tiene_rol(ARRAY[''super_admin''::text]), false))|-' THEN
    bad := bad||'policies de receta_alertas_alergia; ';
  END IF;
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgfoid::regprocedure::text||' '||t.tgtype::text, ',')
        FROM pg_trigger t WHERE t.tgrelid = 'public.receta_alertas_alergia'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_receta_alertas_alergia_inmutable O private.receta_alertas_alergia_inmutable() 27' THEN
    bad := bad||'trigger de receta_alertas_alergia; ';
  END IF;
  IF (SELECT count(*) FROM pg_constraint c WHERE c.conrelid = 'public.receta_alertas_alergia'::regclass AND c.contype = 'f' AND c.confdeltype = 'r') <> 5
     OR EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.receta_alertas_alergia'::regclass AND c.contype = 'f' AND c.confdeltype <> 'r')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.receta_alertas_alergia'::regclass AND c.conname = 'receta_alertas_alergia_motivo_check') THEN
    bad := bad||'constraints de receta_alertas_alergia; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = pg_get_serial_sequence('public.receta_alertas_alergia', 'id')::regclass)
     IS DISTINCT FROM '{postgres=rwU/postgres,service_role=rwU/postgres}' THEN
    bad := bad||'ACL de la secuencia IDENTITY; ';
  END IF;
  -- grants de tabla por rol (regla de GRANTs explícitos / P800)
  IF has_table_privilege('anon', 'public.receta_alertas_alergia', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
     OR NOT has_table_privilege('authenticated', 'public.receta_alertas_alergia', 'SELECT')
     OR has_table_privilege('authenticated', 'public.receta_alertas_alergia', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
     OR NOT (has_table_privilege('service_role', 'public.receta_alertas_alergia', 'SELECT') AND has_table_privilege('service_role', 'public.receta_alertas_alergia', 'INSERT')
             AND has_table_privilege('service_role', 'public.receta_alertas_alergia', 'UPDATE') AND has_table_privilege('service_role', 'public.receta_alertas_alergia', 'DELETE')) THEN
    bad := bad||'grants de receta_alertas_alergia por rol; ';
  END IF;

  -- P800 (j)/(k): ninguna función de public/private con EXECUTE para PUBLIC; anon solo en catalogo_planes_visitador_publico
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR (a.grantee = 'anon'::regrole AND f.oid <> 'public.catalogo_planes_visitador_publico()'::regprocedure)));
  IF v IS NOT NULL THEN bad := bad||'EXECUTE para PUBLIC/anon: '||v||'; '; END IF;
  -- P800 (l): las funciones de la policy nueva las ejecuta authenticated
  IF NOT has_function_privilege('authenticated', 'private.tiene_rol(text[])', 'EXECUTE') OR NOT has_function_privilege('authenticated', 'auth.uid()', 'EXECUTE') THEN
    bad := bad||'authenticated no ejecuta las funciones de la policy nueva; ';
  END IF;
  -- P930: ninguna escritura de authenticated sobre las relaciones tocadas
  IF has_any_column_privilege('authenticated', 'public.recetas', 'INSERT') OR has_any_column_privilege('authenticated', 'public.recetas', 'UPDATE')
     OR has_any_column_privilege('authenticated', 'public.receta_alertas_alergia', 'INSERT') OR has_any_column_privilege('authenticated', 'public.receta_alertas_alergia', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.recetas', 'DELETE') THEN
    bad := bad||'escritura de authenticated en recetas o receta_alertas_alergia; ';
  END IF;
  -- P931: ninguna DEFINER de public/private sin search_path fijo
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%'));
  IF v IS NOT NULL THEN bad := bad||'DEFINER sin search_path: '||v||'; '; END IF;
  -- P934: ninguna policy {public} en las tablas tocadas
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid IN ('public.recetas'::regclass, 'public.receta_alertas_alergia'::regclass) AND 0 = ANY (pl.polroles)) THEN
    bad := bad||'policy TO public en recetas o receta_alertas_alergia; ';
  END IF;

  -- conteos que mueve la migración (las huellas exactas las mide el dry-run)
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 419 THEN
    bad := bad||'no quedaron 419 funciones en public/private; ';
  END IF;
  IF (SELECT count(*) FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) <> 309 THEN
    bad := bad||'no quedaron 309 policies; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG95: autochequeo: %', bad USING ERRCODE = 'MIG95';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
