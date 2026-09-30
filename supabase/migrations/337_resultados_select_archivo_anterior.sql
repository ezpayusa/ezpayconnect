-- ############################################################################################
-- 337 - resultados_scoped_select: el equipo clinico lee el archivo ANTERIOR de una correccion
-- ############################################################################################
-- Hallazgo del front de P4 (PR #11): el historial de revisiones muestra "Ver archivo anterior", pero
-- la policy de SELECT del bucket resultados-examenes solo autoriza por
--   (1) la carpeta del laboratorio (split_part(name,'/',1) = mi_empresa_proveedor()),
--   (2) examenes.archivo_url (el archivo VIGENTE) con private.puede_ver_examen, y
--   (3) examen_adjuntos con private.puede_ver_examen.
-- examen_revisiones.archivo_url_anterior no esta en ninguna: el medico no puede firmar la URL del
-- archivo que la correccion reemplazo (createSignedUrl exige SELECT sobre el objeto). El lab si,
-- por su carpeta.
--
-- Arreglo: DROP + CREATE de resultados_scoped_select con las 3 ramas TEXTUALMENTE iguales y una 4a:
--   EXISTS en examen_revisiones con la misma normalizacion que la rama de examenes (una fila puede
--   guardar la URL completa) y private.puede_ver_historial_examen(r.examen_id): medico del examen,
--   medico que atiende al paciente, admin de la clinica, lab duenio y super_admin. El paciente NO
--   (R3): puede_ver_historial_examen es puede_ver_examen sin la rama del paciente.
--
-- Solo lectura: INSERT y DELETE no se tocan (el DELETE ya respeta el historial via
-- path_resultado_referenciado), sigue sin haber policy de UPDATE y el bucket sigue privado.
-- Sin errcodes nuevos. Probes P912 (acceso al archivo anterior por actor) y P913 (catalogo post-337).
-- Rollback: 337_rollback.sql (qual exacto anterior).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- qual PRE de la policy medido en prod el 29-sep-2026 (pg_policies, search_path por defecto)
DO $pre$
DECLARE bad text := ''; x text; r record;
BEGIN
  SELECT md5(qual)||' '||cmd||' '||roles::text||' '||permissive INTO x
    FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_select';
  IF x IS DISTINCT FROM '03860503aa6f2f1b535e1f0c7acc588f SELECT {authenticated} PERMISSIVE' THEN
    bad := bad||'resultados_scoped_select: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('private.puede_ver_historial_examen(integer)',  '348b7dbf2a9bee5d34be80df243e6a90'),
      ('private.puede_ver_examen(integer)',            '166ad35298bfd3080e8b97a4b2ba9033'),
      ('private.path_resultado_referenciado(text)',    '08ce53df597b8102d35f0ee1636a8b28')) v(f, m) LOOP
    SELECT md5(pg_get_functiondef(to_regprocedure(r.f))) INTO x;
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF to_regclass('public.examen_revisiones') IS NULL THEN bad := bad||'examen_revisiones no existe; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG337 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- qual PRE de las 3 policies del bucket: el autochequeo exige insert/delete iguales y el select
-- como prefijo textual del nuevo
CREATE TEMP TABLE _pol337 ON COMMIT DROP AS
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'storage' AND tablename = 'objects'
   AND (policyname LIKE 'resultados%' OR COALESCE(qual, '')||COALESCE(with_check, '') LIKE '%resultados-examenes%');

-- ------------------------------------------------------------------------------- la policy
DROP POLICY resultados_scoped_select ON storage.objects;

CREATE POLICY resultados_scoped_select ON storage.objects
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    bucket_id = 'resultados-examenes'::text
    AND (
      split_part(name, '/'::text, 1) = (public.mi_empresa_proveedor())::text
      OR EXISTS (SELECT 1 FROM public.examenes e
                  WHERE COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/'::text, 2), ''::text), e.archivo_url) = objects.name
                    AND private.puede_ver_examen(e.id))
      OR EXISTS (SELECT 1 FROM public.examen_adjuntos a
                  WHERE a.storage_path = objects.name
                    AND private.puede_ver_examen(a.examen_id))
      OR EXISTS (SELECT 1 FROM public.examen_revisiones r
                  WHERE COALESCE(NULLIF(split_part(r.archivo_url_anterior, '/resultados-examenes/'::text, 2), ''::text), r.archivo_url_anterior) = objects.name
                    AND private.puede_ver_historial_examen(r.examen_id))
    )
  );

-- ------------------------------------------------------------------------------ autochequeo
DO $chk$
DECLARE bad text := ''; x text; v_pre text; v_post text; r record;
BEGIN
  SELECT cmd||' '||roles::text||' '||permissive, qual INTO x, v_post
    FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_select';
  IF x IS DISTINCT FROM 'SELECT {authenticated} PERMISSIVE' THEN bad := bad||'select cmd/roles/permissive: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  -- md5 del qual post-337 (medido en el dry-run del 29-sep-2026; P913 lo fija igual)
  IF md5(v_post) IS DISTINCT FROM '9f07449decf102173f65ff67c44f04bb' THEN bad := bad||'select md5 '||COALESCE(md5(v_post), 'NULL')||'; '; END IF;
  IF position('examen_revisiones' in COALESCE(v_post, '')) = 0 OR position('puede_ver_historial_examen' in COALESCE(v_post, '')) = 0 THEN
    bad := bad||'select sin la rama de examen_revisiones; '; END IF;
  -- las 3 ramas previas textualmente iguales: el qual PRE sin sus 2 parentesis de cierre es prefijo del nuevo
  SELECT qual INTO v_pre FROM _pol337 WHERE policyname = 'resultados_scoped_select';
  IF v_pre IS NULL OR left(COALESCE(v_post, ''), length(v_pre) - 2) IS DISTINCT FROM left(v_pre, length(v_pre) - 2)
     OR substr(v_post, length(v_pre) - 1, 4) IS DISTINCT FROM ' OR ' THEN
    bad := bad||'select: las ramas previas no quedaron textualmente iguales; '; END IF;
  -- insert y delete intactos
  FOR r IN SELECT p.policyname, md5(COALESCE(p.qual, '')||'|'||COALESCE(p.with_check, '')) AS m,
                  (SELECT md5(COALESCE(o.qual, '')||'|'||COALESCE(o.with_check, '')) FROM _pol337 o WHERE o.policyname = p.policyname) AS m0
             FROM pg_policies p
            WHERE p.schemaname = 'storage' AND p.tablename = 'objects' AND p.policyname IN ('resultados_scoped_insert', 'resultados_scoped_delete') LOOP
    IF r.m IS DISTINCT FROM r.m0 THEN bad := bad||r.policyname||' cambio; '; END IF;
  END LOOP;
  -- set de policies del bucket = {delete, insert, select}, sin UPDATE
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND (policyname LIKE 'resultados%' OR COALESCE(qual, '')||COALESCE(with_check, '') LIKE '%resultados-examenes%');
  IF x IS DISTINCT FROM 'resultados_scoped_delete:DELETE,resultados_scoped_insert:INSERT,resultados_scoped_select:SELECT' THEN
    bad := bad||'set de policies del bucket: '||COALESCE(x, '-')||'; '; END IF;
  -- helpers intactos
  FOR r IN SELECT * FROM (VALUES
      ('private.puede_ver_historial_examen(integer)',  '348b7dbf2a9bee5d34be80df243e6a90'),
      ('private.puede_ver_examen(integer)',            '166ad35298bfd3080e8b97a4b2ba9033'),
      ('private.path_resultado_referenciado(text)',    '08ce53df597b8102d35f0ee1636a8b28')) v(f, m) LOOP
    SELECT md5(pg_get_functiondef(to_regprocedure(r.f))) INTO x;
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- bucket privado
  IF (SELECT public FROM storage.buckets WHERE id = 'resultados-examenes') IS DISTINCT FROM false THEN
    bad := bad||'bucket resultados-examenes no es privado; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG337 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
