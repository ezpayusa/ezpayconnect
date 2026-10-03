-- ############################################################################################
-- 351 ROLLBACK - quita la compra de plan de visitador por RPC y vuelve al esquema y a la huella de la 350
-- ############################################################################################
-- Precondicion = estado POST de la 351 SIN uso: aborta si ya hay datos que el rollback borraria. En ese caso
-- PARAR y decidir (no forzar):
--   * pagos con pvc_id fuera de los 2 del backfill (aprobaciones hechas por la RPC);
--   * pagos con snapshot (plan_visitas / plan_duracion_dias): solicitudes hechas por la RPC;
--   * configuraciones con visitas_incluidas / duracion_dias cargadas (catalogo por pais).
-- Autochequeo = estado PRE de la 351: columnas/constraints/indice/RPCs fuera, policy de INSERT y huella
-- d1aae5eba7362ec479a3995bf2d29827 309.
-- Orden global: 351_rollback -> 350_rollback -> 349_rollback -> ... -> 342_rollback.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST, sin uso)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(id::text||'->'||pvc_id::text, ',' ORDER BY id) FROM public.pagos_proveedor
         WHERE pvc_id IS NOT NULL
           AND (id, pvc_id) NOT IN (('fdc3578f-4418-462a-85d3-f94ae525017d'::uuid, 'b15708fe-6eac-4ed9-b678-501a6baa4d5f'::uuid),
                                    ('f07983a2-50ae-4158-8e21-04b6156e82e8'::uuid, '2db5f85a-a2f1-424d-b021-a0179ae2abce'::uuid)));
  IF v IS NOT NULL THEN bad := bad||'PARAR: pagos con pvc_id fuera del backfill: '||v||'; '; END IF;
  v := (SELECT count(*)::text FROM public.pagos_proveedor WHERE plan_visitas IS NOT NULL OR plan_duracion_dias IS NOT NULL);
  IF v <> '0' THEN bad := bad||'PARAR: '||v||' pagos con snapshot de plan; '; END IF;
  v := (SELECT count(*)::text FROM public.planes_configuracion WHERE visitas_incluidas IS NOT NULL OR duracion_dias IS NOT NULL);
  IF v <> '0' THEN bad := bad||'PARAR: '||v||' configuraciones con visitas/duracion cargadas; '; END IF;
  v := (SELECT pl.polroles::text||'|'||pl.polcmd::text||'|'||md5(pg_get_expr(pl.polwithcheck, pl.polrelid)) FROM pg_policy pl
         WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos');
  IF v IS DISTINCT FROM '{'||'authenticated'::regrole::oid||'}|a|3badf42f9babd6faa27eccfd3043a955' THEN bad := bad||'policy Proveedor crea pagos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('solicitar_compra_plan_visitador','aprobar_pago_plan_visitador'));
  IF v IS DISTINCT FROM 'aprobar_pago_plan_visitador,solicitar_compra_plan_visitador' THEN bad := bad||'RPCs '||COALESCE(v, 'no existen')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK351 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- reversa
DROP FUNCTION public.aprobar_pago_plan_visitador(uuid);
DROP FUNCTION public.solicitar_compra_plan_visitador(uuid, text);

ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor TO authenticated
  WITH CHECK ((empresa_id = private.mi_empresa_onboarding())
    AND (private.mi_rol_onboarding() = ANY (ARRAY['admin','editor','finanzas','marketing','supervisor'])));

DROP INDEX public.idx_pagos_prov_pvc;
ALTER TABLE public.pagos_proveedor
  DROP CONSTRAINT pagos_proveedor_estado_check,
  DROP COLUMN pvc_id,
  DROP COLUMN plan_visitas,
  DROP COLUMN plan_duracion_dias;
ALTER TABLE public.planes_configuracion
  DROP COLUMN visitas_incluidas,
  DROP COLUMN duracion_dias;

-- ---------------------------------------------------------------------------- autochequeo (estado PRE de la 351)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(c.relname||'.'||a.attname, ',') FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
         WHERE c.relnamespace = 'public'::regnamespace AND NOT a.attisdropped AND a.attnum > 0
           AND ((c.relname = 'planes_configuracion' AND a.attname IN ('visitas_incluidas','duracion_dias'))
             OR (c.relname = 'pagos_proveedor' AND a.attname IN ('pvc_id','plan_visitas','plan_duracion_dias'))));
  IF v IS NOT NULL THEN bad := bad||'columnas siguen: '||v||'; '; END IF;
  v := (SELECT string_agg(conname, ',') FROM pg_constraint WHERE connamespace = 'public'::regnamespace
         AND conname IN ('planes_configuracion_visitas_incluidas_check','planes_configuracion_duracion_dias_check',
                         'pagos_proveedor_pvc_id_fkey','pagos_proveedor_plan_visitas_check','pagos_proveedor_plan_duracion_dias_check',
                         'pagos_proveedor_estado_check'));
  IF v IS NOT NULL THEN bad := bad||'constraints siguen: '||v||'; '; END IF;
  IF to_regclass('public.idx_pagos_prov_pvc') IS NOT NULL THEN bad := bad||'indice sigue; '; END IF;
  v := (SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('solicitar_compra_plan_visitador','aprobar_pago_plan_visitador'));
  IF v IS NOT NULL THEN bad := bad||'RPCs siguen: '||v||'; '; END IF;
  v := (SELECT pl.polroles::text||'|'||pl.polcmd::text||'|'||pg_get_expr(pl.polwithcheck, pl.polrelid) FROM pg_policy pl
         WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos');
  IF v IS DISTINCT FROM '{'||'authenticated'::regrole::oid||'}|a|((empresa_id = private.mi_empresa_onboarding()) AND (private.mi_rol_onboarding() = ANY (ARRAY[''admin''::text, ''editor''::text, ''finanzas''::text, ''marketing''::text, ''supervisor''::text])))' THEN
    bad := bad||'policy Proveedor crea pagos: '||COALESCE(v, 'NO EXISTE')||'; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'd1aae5eba7362ec479a3995bf2d29827 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK351 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
