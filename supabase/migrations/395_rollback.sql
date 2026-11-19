-- =====================================================================================================================
-- ROLLBACK DE LA MIG 395 — vuelve al estado post-392 exacto.
--   - emitir_receta vuelve al cuerpo EXACTO de la 316 (md5(prosrc) 74d7013aeea17659bbafb84d780d644b), con su firma de 3
--     argumentos, su COMMENT (md5 4a6e942c8fa707f62fb70f6dee5487fd) y su ACL {postgres, authenticated, service_role}=X.
--   - Suelta public.alergias_en_receta, private.coincidencia_alergia, private.terminos_alergia,
--     private.receta_alertas_alergia_inmutable, la tabla public.receta_alertas_alergia (con su trigger, su policy y su
--     secuencia IDENTITY) y las columnas recetas.cita_id (con su FK e índice) y recetas.folio.
--
-- PROTECCIÓN DE DATOS: aborta (MIG95) si receta_alertas_alergia tiene filas o si hay recetas con cita_id o folio no
-- nulos, porque el rollback los BORRA. Para forzarlo a sabiendas (se pierden la auditoría de alergias confirmadas y el
-- vínculo receta-cita y el folio guardados), descomentar la línea
--     -- SET LOCAL app.rollback_395_forzar = 'si';
-- que está justo después de BEGIN. Ningún otro valor ni otra forma de setearlo cuenta.
--
-- Orden: va ANTES que 392_rollback (la precondición de 392_rollback exige las huellas post-392 que este archivo
-- devuelve). Su precondición exige las huellas post-395 exactas: si después de la 395 se aplicó otra migración, primero
-- va su rollback.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/395_rollback.sql
-- =====================================================================================================================

BEGIN;
-- SET LOCAL app.rollback_395_forzar = 'si';

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN: estado post-395 exacto + protección de datos
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; n_alertas bigint; n_cita bigint; n_folio bigint; forzar boolean;
BEGIN
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.emitir_receta(bigint,text,jsonb,bigint)'));
  IF v IS DISTINCT FROM '9b65b54d314c61d1db6f4f8998234f6b true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'emitir_receta distinta de la 395 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'emitir_receta') <> 1 THEN
    bad := bad||'emitir_receta no tiene exactamente una sobrecarga; ';
  END IF;
  IF to_regclass('public.receta_alertas_alergia') IS NULL THEN bad := bad||'receta_alertas_alergia no existe; '; END IF;

  -- huellas post-395 (dry-run del 19-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'd20a117271a2a187c6f461b1af1d8014 419' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '311350dbe0717e9737372034623b434b 419' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG95: precondición del rollback: %', bad USING ERRCODE = 'MIG95';
  END IF;

  -- protección de datos (después del chequeo estructural: si la tabla no existe, ya abortó arriba)
  EXECUTE 'SELECT count(*) FROM public.receta_alertas_alergia' INTO n_alertas;
  EXECUTE 'SELECT count(*) FILTER (WHERE cita_id IS NOT NULL), count(*) FILTER (WHERE folio IS NOT NULL) FROM public.recetas' INTO n_cita, n_folio;
  forzar := current_setting('app.rollback_395_forzar', true) IS NOT DISTINCT FROM 'si';
  IF (n_alertas > 0 OR n_cita > 0 OR n_folio > 0) AND NOT forzar THEN
    RAISE EXCEPTION 'MIG95: el rollback borraría datos (receta_alertas_alergia % filas; recetas con cita_id %; con folio %). Para forzarlo, descomentar SET LOCAL app.rollback_395_forzar = ''si'' (ver cabecera).',
      n_alertas, n_cita, n_folio USING ERRCODE = 'MIG95';
  END IF;
  IF forzar THEN
    RAISE WARNING 'MIG95: rollback FORZADO: se pierden % alertas de alergia, % vínculos receta-cita y % folios', n_alertas, n_cita, n_folio;
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Lo nuevo: tabla, funciones de alergias
-- ---------------------------------------------------------------------------------------------------------------------
DROP TABLE public.receta_alertas_alergia;
DROP FUNCTION private.receta_alertas_alergia_inmutable();
DROP FUNCTION public.alergias_en_receta(bigint, bigint[]);
DROP FUNCTION private.coincidencia_alergia(bigint, bigint);
DROP FUNCTION private.terminos_alergia(text);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) emitir_receta: el cuerpo EXACTO de la 316 (copiado de 316_pertenencia_en_emitir_receta.sql, solo CREATE en vez de
--    CREATE OR REPLACE porque la de 4 argumentos se suelta antes)
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION public.emitir_receta(bigint, text, jsonb, bigint);

CREATE FUNCTION public.emitir_receta(p_paciente_id bigint, p_instrucciones_generales text, p_items jsonb)
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
BEGIN
  -- ===== (1) GATE. Antes de consumir numero. Fallo aqui => nada se toca. =====
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesion' USING ERRCODE = 'PR001';
  END IF;
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo un medico puede emitir recetas' USING ERRCODE = 'PR002';
  END IF;
  IF p_paciente_id IS NULL THEN
    RAISE EXCEPTION 'Paciente requerido' USING ERRCODE = 'PR003';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pacientes WHERE id = p_paciente_id) THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'PR003';
  END IF;
  -- (1b) GATE DE PERTENENCIA (mig 316, PR009). Antes: emitir_receta solo exigia
  -- tiene_rol(['medico']), sin relacion medico-paciente, asi que por RPC directo un medico podia
  -- recetar a CUALQUIER paciente_id (saltandose el selector de la UI). Con el hueco de
  -- auto-asignacion de rol 'medico' (policy "Insertar propio perfil"), lo alcanzaba cualquiera.
  --
  -- PREDICADO A, dos brazos, que ESPEJAN EXACTAMENTE la visibilidad RLS de public.pacientes para
  -- el rol medico:
  --   medico_atiende_paciente(id)  == policy pacientes_select_medico_cita (tiene cita con el)
  --   pacientes.medico_id=auth.uid == policy Pacientes_select (es su medico registrado)
  -- Medido: para el medico real este conjunto es identico al que ve por RLS.
  --
  -- DELIBERADAMENTE MAS ESTRICTO que gate_accion_phi, que usa pertenencia de CLINICA
  -- (private.paciente_en_clinica_de: cualquier paciente de la clinica, aun sin cita). Una receta
  -- es un documento DISPENSABLE; el gate de emitirla no debe ser mas laxo que lo que el medico ve.
  -- Si algun dia se unifican, se unifica AMPLIANDO la RLS de pacientes primero, no relajando este
  -- gate.
  IF NOT (
       private.medico_atiende_paciente(p_paciente_id)
    OR EXISTS (SELECT 1 FROM public.pacientes pa
                WHERE pa.id = p_paciente_id AND pa.medico_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'No autorizado: no atendes a este paciente' USING ERRCODE = 'PR009';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Items debe ser un arreglo' USING ERRCODE = 'PR004';
  END IF;
  v_n_items := jsonb_array_length(p_items);
  IF v_n_items = 0 THEN
    RAISE EXCEPTION 'La receta debe tener al menos un medicamento' USING ERRCODE = 'PR004';
  END IF;
  -- ===== (2) VALIDACION POR ITEM. medicamento_id OBLIGATORIO + acuse de regulados. =====
  -- Fail-safe: categoria NULL = sin_clasificar = NO regulado => no exige acuse (decision A1).
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_med_id := NULLIF(v_item->>'medicamento_id', '')::bigint;
    IF v_med_id IS NULL THEN
      RAISE EXCEPTION 'Todo medicamento debe venir del catalogo (medicamento_id ausente en "%")',
        COALESCE(v_item->>'nombre_medicamento', '?') USING ERRCODE = 'PR005';
    END IF;
    SELECT m.categoria_regulatoria, m.activo INTO v_categoria, v_activo
      FROM public.medicamentos m WHERE m.id = v_med_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Medicamento % no existe en el catalogo', v_med_id USING ERRCODE = 'PR005';
    END IF;
    -- (u) fail-safe: NULL se trata como NO activo.
    IF NOT COALESCE(v_activo, false) THEN
      RAISE EXCEPTION 'El medicamento "%" no esta activo en el catalogo',
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
      RAISE EXCEPTION 'El medicamento "%" es % y requiere el acuse (iniciales) del medico',
        COALESCE(v_item->>'nombre_medicamento','?'), v_categoria USING ERRCODE = 'PR007';
    END IF;
  END LOOP;
  -- ===== (3) DATOS DEL MEDICO. pais_id server-side: no se confia en el cliente. =====
  SELECT COALESCE(pf.nombre_completo, pf.nombre), pf.pais_id
    INTO v_nombre, v_pais_id
    FROM public.perfiles pf WHERE pf.id = v_uid;
  SELECT md.cedula_profesional INTO v_cedula
    FROM public.medicos md WHERE md.id = v_uid;
  -- Decision (C): la cedula NO bloquea la emision. El folio se compone al LEER
  -- y se auto-repara cuando se cargue. El gate va en el alta del medico.
  IF v_cedula IS NULL THEN
    RAISE WARNING 'emitir_receta: medico % sin cedula_profesional (folio degradado)', v_uid;
  END IF;
  -- ===== (4) BUMP GAPLESS. Una sentencia. Toma el lock de fila y resuelve el alta. =====
  INSERT INTO public.medico_correlativos (medico_id, ultimo_numero)
  VALUES (v_uid, 1)
  ON CONFLICT (medico_id) DO UPDATE
    SET ultimo_numero = public.medico_correlativos.ultimo_numero + 1,
        updated_at    = now()
  RETURNING ultimo_numero INTO v_num;
  -- ===== (5) INSERT recetas. Dispara trg_historial_receta. =====
  INSERT INTO public.recetas (paciente_id, instrucciones_generales, medico_id, estado, pais_id, numero_correlativo)
  VALUES (p_paciente_id, NULLIF(trim(COALESCE(p_instrucciones_generales,'')), ''), v_uid, 'activa', v_pais_id, v_num)
  RETURNING id INTO v_receta_id;
  -- ===== (6) INSERT receta_items + acuse persistido (b1). =====
  INSERT INTO public.receta_items
    (receta_id, medicamento_id, nombre_medicamento, dosis, frecuencia, duracion,
     instrucciones, cantidad, farmacia_id, precio_unitario, stock_actual,
     acuse_iniciales, acuse_at, acuse_categoria)
  SELECT
    v_receta_id,
    (it->>'medicamento_id')::bigint,
    it->>'nombre_medicamento',
    it->>'dosis',
    it->>'frecuencia',
    NULLIF(it->>'duracion',''),
    NULLIF(it->>'instrucciones',''),
    COALESCE(NULLIF(it->>'cantidad','')::int, 1),
    NULLIF(it->>'farmacia_id','')::int,
    NULLIF(it->>'precio_unitario','')::numeric,
    NULLIF(it->>'stock_actual','')::int,
    NULLIF(trim(COALESCE(it->>'acuse_iniciales','')), ''),
    CASE WHEN NULLIF(trim(COALESCE(it->>'acuse_iniciales','')), '') IS NOT NULL THEN now() END,
    (SELECT m.categoria_regulatoria FROM public.medicamentos m WHERE m.id = (it->>'medicamento_id')::bigint)
  FROM jsonb_array_elements(p_items) it;
  -- ===== (7) CORRECCION (1): la fila despachable nace ACA, no en un boton escondido. =====
  -- dispatch_token y dispatch_token_expira_at salen de sus DEFAULT de columna.
  -- La edge ya no firma: su upsert tiene ignoreDuplicates y quedaria en no-op.
  INSERT INTO public.recetas_avanzadas
    (receta_base_id, paciente_id, medico_id, firma_digital, estado_dispensacion, emitida_at)
  VALUES
    (v_receta_id, p_paciente_id::text, v_uid::text,
     'FIRMADO-' || COALESCE(v_nombre, 'Medico') || '-' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
     'pendiente', now());
  RETURN jsonb_build_object(
    'receta_id',          v_receta_id,
    'numero_correlativo', v_num,
    'numero_formateado',  COALESCE(v_cedula, 'SINCED') || '-' || lpad(v_num::text, 6, '0') || '-' || to_char(now(), 'YYYYMMDD')
  );
END;
$function$;

COMMENT ON FUNCTION public.emitir_receta(bigint, text, jsonb) IS
  'Emite una receta. Gates: PR001 sesion, PR002 rol medico, PR003 paciente existe, PR009 PERTENENCIA (mig 316, predicado A de 2 brazos): espeja la visibilidad RLS de public.pacientes para el rol medico (medico_atiende_paciente OR pacientes.medico_id=auth.uid). Deliberadamente MAS estricto que gate_accion_phi (que usa pertenencia de clinica): una receta es dispensable, el gate no debe ser mas laxo que la RLS. Cierra el RPC directo a paciente ajeno.';
REVOKE ALL ON FUNCTION public.emitir_receta(bigint, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emitir_receta(bigint, text, jsonb) TO authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) recetas: fuera cita_id (con su FK e índice) y folio
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.recetas DROP COLUMN folio, DROP COLUMN cita_id;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) AUTOCHEQUEO: emitir_receta de la 316 y huellas post-392 exactas
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(COALESCE(obj_description(p.oid, 'pg_proc'), ''))
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.emitir_receta(bigint,text,jsonb)'));
  IF v IS DISTINCT FROM '74d7013aeea17659bbafb84d780d644b true v {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} 4a6e942c8fa707f62fb70f6dee5487fd' THEN
    bad := bad||'emitir_receta no volvió a la 316 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'emitir_receta') <> 1 THEN
    bad := bad||'emitir_receta no tiene exactamente una sobrecarga; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.recetas'::regclass AND a.attname IN ('cita_id', 'folio') AND NOT a.attisdropped)
     OR to_regclass('public.receta_alertas_alergia') IS NOT NULL OR to_regclass('public.recetas_cita_id_idx') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE (n.nspname, p.proname) IN (('public', 'alergias_en_receta'), ('private', 'terminos_alergia'),
                                                  ('private', 'coincidencia_alergia'), ('private', 'receta_alertas_alergia_inmutable'))) THEN
    bad := bad||'quedan objetos de la 395; ';
  END IF;

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
    RAISE EXCEPTION 'MIG95: autochequeo del rollback: %', bad USING ERRCODE = 'MIG95';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
