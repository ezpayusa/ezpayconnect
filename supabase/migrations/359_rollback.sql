-- ############################################################################################
-- 359 ROLLBACK - saca las RPC de cobro de campana del servidor
-- ############################################################################################
-- DROP de public.solicitar_pago_campana(uuid,text), public.cotizar_campana(uuid) y
-- private.precio_plan_publicidad(uuid,integer). No toca policies: la 359 es solo aditiva (el cierre del INSERT directo de
-- pagos tipo 'campana' es la 360, que tiene su propio rollback y debe revertirse ANTES que este).
-- Los pagos creados por solicitar_pago_campana mientras la 359 estuvo viva NO se tocan.
-- Ojo: un front que ya llame a solicitar_pago_campana / cotizar_campana deja de andar con este rollback (404 de RPC).
-- Precondicion: la 359 esta viva (las 3 funciones con sus md5) y la policy "Proveedor crea pagos" NO tiene el termino de
-- la 360 (si lo tiene, primero 360_rollback: sin la RPC y con la policy cerrada no habria forma de pagar una campana).
-- Probes: con este rollback aplicado, P975-P979, P981 y P982 dan ROJO.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 359)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'='||md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('private.precio_plan_publicidad(uuid,integer)'), to_regprocedure('public.cotizar_campana(uuid)'), to_regprocedure('public.solicitar_pago_campana(uuid,text)')));
  IF v IS DISTINCT FROM 'cotizar_campana(uuid)=6323c55ac2d9010dfd2dad8ffc573cdf,private.precio_plan_publicidad(uuid,integer)=949e707c6682951dd6a09128ed59f9eb,solicitar_pago_campana(uuid,text)=49a10261bb1ad8c5ac49722afb295a15' THEN
    bad := bad||'funciones de la 359 '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT pg_get_expr(pl.polwithcheck, pl.polrelid) FROM pg_policy pl WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos');
  IF v IS NULL OR position('(tipo <> ''campana''::text)' IN v) > 0 THEN bad := bad||'la policy tiene el termino de la 360 (correr 360_rollback primero); '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK359 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

DROP FUNCTION public.solicitar_pago_campana(uuid, text);
DROP FUNCTION public.cotizar_campana(uuid);
DROP FUNCTION private.precio_plan_publicidad(uuid, integer);

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('private.precio_plan_publicidad(uuid,integer)') IS NOT NULL OR to_regprocedure('public.cotizar_campana(uuid)') IS NOT NULL
     OR to_regprocedure('public.solicitar_pago_campana(uuid,text)') IS NOT NULL THEN
    bad := bad||'alguna funcion sigue; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK359 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
