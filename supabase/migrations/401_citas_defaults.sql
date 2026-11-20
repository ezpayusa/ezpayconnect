-- =====================================================================================================================
-- MIG 401 — citas: DEFAULT de estado, motivo y notas. Sin front.
--
-- Por qué (medido el 20-nov-2026 20:48:05 UTC, post-400):
--   citas.estado  DEFAULT '''agendada'''::text  -> el valor es la cadena 'agendada' CON las comillas adentro: un INSERT que
--                 omite estado viola citas_estado_valido (y estado es NOT NULL, así que no hay salida por NULL).
--   citas.motivo  DEFAULT 'NULL'::text          -> el texto de 4 letras «NULL», no un NULL.
--   citas.notas   DEFAULT 'NULL'::text          -> ídem.
--   Filas con el texto «NULL» literal: motivo en 3 (ids 27, 28, 29) y notas en 9 (27, 28, 29, 72, 1342-1346), de escritores
--   viejos que omitían las columnas. Estado fuera del CHECK: 0.
--
-- Escritores (re-confirmado el 20-nov sobre origin/main 239e6f4):
--   El único INSERT vivo es public.crear_cita (DEFINER, md5(prosrc) d6fbb644c4d486201eadd4d6c04be22f): manda motivo, notas y
--   estado explícitos, así que no depende de ningún DEFAULT. El front no inserta citas directo (mig 391) y ninguna edge las
--   inserta. El harness inserta como postgres con estado explícito (P929 y los fixtures lo dejan así; ya no hace falta para
--   el estado, pero no molesta).
--
-- Censo de DEFAULT rotos en public/private (texto con comillas incrustadas o el texto 'NULL'), medido el 20-nov: SOLO estas 3
-- columnas de citas. No hay otros casos.
--
-- Qué hace (y nada más):
--   1. citas.estado DEFAULT 'agendada' (está en citas_estado_valido); citas.motivo y citas.notas DROP DEFAULT (quedan NULL).
--   2. Datos: motivo/notas = 'NULL' (texto literal) -> NULL. Ningún trigger de citas dispara por esas columnas: los 4 de
--      UPDATE son UPDATE OF estado (trg_cerrar_nota_al_completar, trg_exigir_nota_al_completar, trg_otorgar_puntos_referido,
--      trg_reset_notif_cancel) y trg_historial_cita es AFTER INSERT. No hay guard de UPDATE en citas, la tabla no está en
--      ninguna publicación y la migración corre como postgres (dueño, RLS sin FORCE: la guarda lo exige).
--   3. Las huellas de funciones, ACL de funciones, ACL de relaciones, ACL de secuencias y policies NO se mueven (los DEFAULT
--      y los datos no entran en ninguna); el autochequeo las compara contra la entrada.
--   Guardas: el mensaje lleva el número completo (MIG401 / MIG401R); el SQLSTATE es MIG01 (un SQLSTATE tiene 5 caracteres;
--   convención MIG + los dos últimos dígitos, MIG01 no estaba en uso).
--
-- Estado ANTES = DESPUÉS en huellas (20-nov-2026 20:48:05 UTC, post-400):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... f1581e8802f3a06dc7d1737c6aad51dd 424
--   ACL de funciones (solo privilegios), public/private .......................... d026ae246b0262142684e187b7b8710f 424
--   ACL de relaciones de public ................................................... d17d651fdbe1b592147983a9b133dbcf 2442
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... dabf9556bae56bcb910de70405314ad8 310
-- Rollback: supabase/migrations/401_rollback.sql (va antes que 400_rollback; restaura los DEFAULT viejos, NO los datos).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/401_citas_defaults.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- la 400 está aplicada
  IF to_regprocedure('private.expediente_notas_fija_pais()') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND t.tgname = 'trg_expediente_notas_pais') THEN
    bad := bad||'la 400 no está aplicada; ';
  END IF;
  -- la 401 no está aplicada: los 3 DEFAULT exactamente como se midieron
  v := (SELECT string_agg(a.attname||'='||COALESCE(pg_get_expr(d.adbin, d.adrelid), '(sin default)'), ' ; ' ORDER BY a.attname)
          FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE a.attrelid = 'public.citas'::regclass AND a.attname IN ('estado', 'motivo', 'notas') AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'estado=''''''agendada''''''::text ; motivo=''NULL''::text ; notas=''NULL''::text' THEN
    bad := bad||'DEFAULT de citas distintos de los medidos (¿la 401 ya se aplicó?): '||COALESCE(v, '-')||'; ';
  END IF;
  -- columnas: estado text NOT NULL; motivo y notas text nullable
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod)||':'||a.attnotnull::text, ',' ORDER BY a.attname)
        FROM pg_attribute a WHERE a.attrelid = 'public.citas'::regclass AND a.attname IN ('estado', 'motivo', 'notas') AND NOT a.attisdropped)
     IS DISTINCT FROM 'estado:text:true,motivo:text:false,notas:text:false' THEN
    bad := bad||'tipo o NOT NULL de estado/motivo/notas distintos de los medidos; ';
  END IF;
  -- el CHECK de estado, tal cual, y admite 'agendada'
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido')
     IS DISTINCT FROM 'CHECK ((estado = ANY (ARRAY[''solicitada''::text, ''agendada''::text, ''confirmada''::text, ''en_espera''::text, ''en_curso''::text, ''completada''::text, ''cancelada''::text, ''no_show''::text])))' THEN
    bad := bad||'citas_estado_valido distinto del medido; ';
  END IF;
  -- triggers: ninguno dispara por motivo/notas (los de UPDATE son UPDATE OF estado; el de INSERT no mira UPDATE)
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgtype::text||' '||COALESCE((SELECT string_agg(a.attname, ',' ORDER BY a.attname) FROM pg_attribute a
                          WHERE a.attrelid = t.tgrelid AND a.attnum = ANY(t.tgattr::int2[])), '-'), ',' ORDER BY t.tgname COLLATE "C")
        FROM pg_trigger t WHERE t.tgrelid = 'public.citas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_cerrar_nota_al_completar O 17 estado,trg_exigir_nota_al_completar O 19 estado,trg_historial_cita O 5 -,'
                    ||'trg_otorgar_puntos_referido O 17 estado,trg_reset_notif_cancel O 19 estado' THEN
    bad := bad||'triggers de citas distintos de los medidos; ';
  END IF;
  IF (SELECT relforcerowsecurity FROM pg_class WHERE oid = 'public.citas'::regclass) THEN
    bad := bad||'citas tiene FORCE ROW LEVEL SECURITY; ';
  END IF;
  -- el único escritor (crear_cita) manda estado, motivo y notas explícitos: su cuerpo, el medido
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.proname = 'crear_cita' AND p.pronamespace = 'public'::regnamespace) IS DISTINCT FROM 'd6fbb644c4d486201eadd4d6c04be22f'
     OR (SELECT count(*) FROM pg_proc p WHERE p.proname = 'crear_cita') <> 1 THEN
    bad := bad||'crear_cita distinta de la medida; ';
  END IF;
  IF (SELECT count(*) FROM public.citas WHERE estado IS NULL OR estado NOT IN ('solicitada','agendada','confirmada','en_espera','en_curso','completada','cancelada','no_show')) <> 0 THEN
    bad := bad||'hay citas con estado fuera del CHECK; ';
  END IF;

  -- huellas post-400 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f1581e8802f3a06dc7d1737c6aad51dd 424' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'd026ae246b0262142684e187b7b8710f 424' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd17d651fdbe1b592147983a9b133dbcf 2442' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG401: precondición: %', bad USING ERRCODE = 'MIG01';
  END IF;

  -- para el autochequeo: las filas que se van a limpiar y una huella de las citas sin motivo/notas
  PERFORM set_config('mig401.motivo_null', (SELECT count(*)::text FROM public.citas WHERE motivo = 'NULL'), true);
  PERFORM set_config('mig401.notas_null', (SELECT count(*)::text FROM public.citas WHERE notas = 'NULL'), true);
  PERFORM set_config('mig401.resto', (SELECT count(*)||' '||COALESCE(md5(string_agg((to_jsonb(c) - 'motivo' - 'notas')::text, E'\n' ORDER BY c.id)), '-')
                                         ||' '||COALESCE(md5(string_agg(c.id::text||'|'||COALESCE(NULLIF(c.motivo, 'NULL'), '<null>')||'|'||COALESCE(NULLIF(c.notas, 'NULL'), '<null>'), E'\n' ORDER BY c.id)), '-')
                                         FROM public.citas c), true);
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) DEFAULT
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.citas ALTER COLUMN estado SET DEFAULT 'agendada';
ALTER TABLE public.citas ALTER COLUMN motivo DROP DEFAULT;
ALTER TABLE public.citas ALTER COLUMN notas DROP DEFAULT;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) DATOS: el texto 'NULL' literal pasa a NULL (ningún trigger dispara por motivo/notas; ver la precondición)
-- ---------------------------------------------------------------------------------------------------------------------
DO $datos$
DECLARE n bigint;
BEGIN
  UPDATE public.citas SET motivo = NULL WHERE motivo = 'NULL';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n::text IS DISTINCT FROM current_setting('mig401.motivo_null', true) THEN
    RAISE EXCEPTION 'MIG401: limpieza de motivo tocó % filas (esperadas %)', n, current_setting('mig401.motivo_null', true) USING ERRCODE = 'MIG01';
  END IF;
  UPDATE public.citas SET notas = NULL WHERE notas = 'NULL';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n::text IS DISTINCT FROM current_setting('mig401.notas_null', true) THEN
    RAISE EXCEPTION 'MIG401: limpieza de notas tocó % filas (esperadas %)', n, current_setting('mig401.notas_null', true) USING ERRCODE = 'MIG01';
  END IF;
END $datos$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(a.attname||'='||COALESCE(pg_get_expr(d.adbin, d.adrelid), '(sin default)'), ' ; ' ORDER BY a.attname)
          FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE a.attrelid = 'public.citas'::regclass AND a.attname IN ('estado', 'motivo', 'notas') AND NOT a.attisdropped);
  IF v IS DISTINCT FROM 'estado=''agendada''::text ; motivo=(sin default) ; notas=(sin default)' THEN
    bad := bad||'DEFAULT de citas = '||COALESCE(v, '-')||'; ';
  END IF;
  -- el DEFAULT nuevo de estado pasa el CHECK (se evalúa la expresión viva, no un literal escrito acá)
  EXECUTE 'SELECT ('||(SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                        WHERE d.adrelid = 'public.citas'::regclass AND a.attname = 'estado')||')::text' INTO v;
  IF v IS DISTINCT FROM 'agendada' THEN bad := bad||'el DEFAULT de estado evalúa a '||COALESCE(v, 'NULL')||'; '; END IF;
  IF (SELECT count(*) FROM public.citas WHERE motivo = 'NULL' OR notas = 'NULL') <> 0 THEN
    bad := bad||'quedan citas con el texto NULL literal; ';
  END IF;
  -- el resto de las columnas no cambió, y motivo/notas quedaron igual salvo 'NULL' -> NULL
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg((to_jsonb(c) - 'motivo' - 'notas')::text, E'\n' ORDER BY c.id)), '-')
             ||' '||COALESCE(md5(string_agg(c.id::text||'|'||COALESCE(c.motivo, '<null>')||'|'||COALESCE(c.notas, '<null>'), E'\n' ORDER BY c.id)), '-')
        FROM public.citas c) IS DISTINCT FROM current_setting('mig401.resto', true) THEN
    bad := bad||'cambiaron datos de citas fuera de la limpieza de motivo/notas; ';
  END IF;

  -- huellas: ninguna de las 5 se mueve
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f1581e8802f3a06dc7d1737c6aad51dd 424' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'd026ae246b0262142684e187b7b8710f 424' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd17d651fdbe1b592147983a9b133dbcf 2442' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG401: autochequeo: %', bad USING ERRCODE = 'MIG01';
  END IF;
END $autochequeo$;

COMMIT;
