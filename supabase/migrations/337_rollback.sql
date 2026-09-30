-- ############################################################################################
-- 337 ROLLBACK - resultados_scoped_select vuelve al qual exacto previo a la 337 (3 ramas)
-- ############################################################################################
-- Precondicion: el qual vivo es el post-337. Autochequeo: el qual restaurado tiene el md5 PRE
-- medido en prod el 29-sep-2026 (03860503...) e insert/delete no cambiaron.
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE x text;
BEGIN
  SELECT md5(qual)||' '||cmd||' '||roles::text||' '||permissive INTO x
    FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_select';
  IF x IS DISTINCT FROM '9f07449decf102173f65ff67c44f04bb SELECT {authenticated} PERMISSIVE' THEN
    RAISE EXCEPTION 'MIG337 ROLLBACK PRECONDICION FALLA: resultados_scoped_select %', COALESCE(x, 'NO EXISTE'); END IF;
END $pre$;

CREATE TEMP TABLE _pol337rb ON COMMIT DROP AS
SELECT policyname, md5(COALESCE(qual, '')||'|'||COALESCE(with_check, '')) AS m
  FROM pg_policies
 WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname IN ('resultados_scoped_insert', 'resultados_scoped_delete');

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
    )
  );

DO $chk$
DECLARE bad text := ''; x text; r record;
BEGIN
  SELECT md5(qual)||' '||cmd||' '||roles::text||' '||permissive INTO x
    FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'resultados_scoped_select';
  IF x IS DISTINCT FROM '03860503aa6f2f1b535e1f0c7acc588f SELECT {authenticated} PERMISSIVE' THEN
    bad := bad||'resultados_scoped_select: '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  FOR r IN SELECT p.policyname, md5(COALESCE(p.qual, '')||'|'||COALESCE(p.with_check, '')) AS m,
                  (SELECT o.m FROM _pol337rb o WHERE o.policyname = p.policyname) AS m0
             FROM pg_policies p
            WHERE p.schemaname = 'storage' AND p.tablename = 'objects' AND p.policyname IN ('resultados_scoped_insert', 'resultados_scoped_delete') LOOP
    IF r.m IS DISTINCT FROM r.m0 THEN bad := bad||r.policyname||' cambio; '; END IF;
  END LOOP;
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname COLLATE "C") INTO x
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND (policyname LIKE 'resultados%' OR COALESCE(qual, '')||COALESCE(with_check, '') LIKE '%resultados-examenes%');
  IF x IS DISTINCT FROM 'resultados_scoped_delete:DELETE,resultados_scoped_insert:INSERT,resultados_scoped_select:SELECT' THEN
    bad := bad||'set de policies del bucket: '||COALESCE(x, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG337 ROLLBACK AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
