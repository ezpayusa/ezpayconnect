-- ############################################################################################
-- 377_rollback - borra solicitudes_alta_medico y sus 4 RPCs (solicitar/cancelar/rechazar/listar)
-- ############################################################################################
-- Precondicion: estado post-377 (tabla con su ACL exacta, md5(prosrc) de las 4 funciones) y la tabla VACIA: si hay
--   solicitudes cargadas el rollback aborta (no se borran datos de negocio en un rollback; decidir antes que hacer
--   con ellas). Las notificaciones ya enviadas (tipos solicitud_alta_medico / solicitud_alta_rechazada) no se tocan:
--   no tienen FK a la tabla.
-- Autochequeo: la tabla y las 4 funciones no existen, PV018-PV023 sin uso, y las huellas globales vuelven a las
--   previas a la 377 (medidas en prod el 20-oct-2026): funciones (cuerpo, DEFINER, config, ACL)
--   58ec02c714546c1d5a0f2a90e5aa2509/392, ACL de funciones 9c59aeca.../392, policies 8a8dc5cf.../309, ACL de
--   relaciones de public 1889d1d8.../2393.
-- Orden global: 377_rollback -> 376_rollback -> 375_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text; n bigint;
BEGIN
  IF to_regclass('public.solicitudes_alta_medico') IS NULL THEN
    RAISE EXCEPTION 'MIG377_ROLLBACK_PRE FALLA:la tabla solicitudes_alta_medico no existe; ';
  END IF;
  -- bloquea la tabla antes de contar: nadie inserta entre el conteo y el DROP
  EXECUTE 'LOCK TABLE public.solicitudes_alta_medico IN ACCESS EXCLUSIVE MODE';
  EXECUTE 'SELECT count(*) FROM public.solicitudes_alta_medico' INTO n;
  IF n <> 0 THEN bad := bad||'la tabla tiene '||n||' filas; '; END IF;

  v := (SELECT c.relacl::text FROM pg_class c WHERE c.oid = to_regclass('public.solicitudes_alta_medico'));
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwd/postgres}' THEN
    bad := bad||'ACL de la tabla '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'),
                         to_regprocedure('public.cancelar_solicitud_alta(uuid)'),
                         to_regprocedure('public.rechazar_solicitud_alta(uuid,text)'),
                         to_regprocedure('public.listar_solicitudes_alta(text)')));
  IF v IS DISTINCT FROM '34ff13a23b4681dddd44118b7b2dc1e1,90b37826b44f1b7e18813f9916867286,a028473675bea99b8b4bc89108b5ac47,4979da5532a3ddd08a466929bbfe27c7' THEN
    bad := bad||'md5 de las 4 funciones '||COALESCE(v, '-')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p
       WHERE p.proname IN ('solicitar_alta_medico', 'cancelar_solicitud_alta', 'rechazar_solicitud_alta', 'listar_solicitudes_alta')) <> 4 THEN
    bad := bad||'sobrecargas de las funciones de la 377; ';
  END IF;
  -- nada fuera de la 377 depende de la tabla (vistas, FKs entrantes)
  v := (SELECT string_agg(DISTINCT d.classid::regclass::text||':'||d.objid, ', ') FROM pg_depend d
         WHERE d.refobjid = 'public.solicitudes_alta_medico'::regclass AND d.deptype = 'n'
           AND d.classid IN ('pg_rewrite'::regclass)
           AND NOT EXISTS (SELECT 1 FROM pg_rewrite r WHERE r.oid = d.objid AND r.ev_class = 'public.solicitudes_alta_medico'::regclass));
  IF v IS NOT NULL THEN bad := bad||'vistas que dependen de la tabla ['||v||']; '; END IF;
  v := (SELECT string_agg(c.conrelid::regclass::text||'.'||c.conname, ', ') FROM pg_constraint c
         WHERE c.confrelid = 'public.solicitudes_alta_medico'::regclass AND c.conrelid <> c.confrelid);
  IF v IS NOT NULL THEN bad := bad||'FKs entrantes ['||v||']; '; END IF;

  -- resto de las funciones = huella previa a la 377
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN ('public.solicitar_alta_medico(text,text,text,uuid,text,text,boolean)'::regprocedure,
                             'public.cancelar_solicitud_alta(uuid)'::regprocedure,
                             'public.rechazar_solicitud_alta(uuid,text)'::regprocedure,
                             'public.listar_solicitudes_alta(text)'::regprocedure));
  IF v IS DISTINCT FROM '58ec02c714546c1d5a0f2a90e5aa2509 392' THEN bad := bad||'huella del resto de las funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG377_ROLLBACK_PRE FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: borrar
DROP FUNCTION public.solicitar_alta_medico(text, text, text, uuid, text, text, boolean);
DROP FUNCTION public.cancelar_solicitud_alta(uuid);
DROP FUNCTION public.rechazar_solicitud_alta(uuid, text);
DROP FUNCTION public.listar_solicitudes_alta(text);
DROP TABLE public.solicitudes_alta_medico;  -- arrastra sus policies, indices y constraints (sin CASCADE)

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regclass('public.solicitudes_alta_medico') IS NOT NULL THEN bad := bad||'la tabla sigue existiendo; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.proname IN ('solicitar_alta_medico', 'cancelar_solicitud_alta', 'rechazar_solicitud_alta', 'listar_solicitudes_alta'));
  IF v IS NOT NULL THEN bad := bad||'funciones que siguen existiendo ['||v||']; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc ~ 'PV0(1[89]|2[0-3])');
  IF v IS NOT NULL THEN bad := bad||'PV018-PV023 en ['||v||']; '; END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '58ec02c714546c1d5a0f2a90e5aa2509 392' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG377_ROLLBACK_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
