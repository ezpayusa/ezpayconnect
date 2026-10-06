-- ############################################################################################
-- 366 ROLLBACK - datos bancarios vuelven a la lectura amplia
-- ############################################################################################
-- Recrea con su texto EXACTO previo (objeto vivo del 5-oct-2026) cuentas_banco_read_pais (cuentas_bancarias_pais),
-- configuracion_sistema_select_authenticated y configuracion_sistema_select_anon (configuracion_sistema); borra
-- cuentas_banco_read_acotada, configuracion_sistema_select_anon_publicas, configuracion_sistema_select_authenticated_publicas
-- y private.pais_empresa_onboarding().
-- Efecto: cualquier perfil del pais vuelve a leer la cuenta de deposito (y el proveedor de una empresa pendiente deja de
-- verla); todo authenticated vuelve a leer las 21 claves y anon las 16 no bancarias.
-- Precondicion: la 366 esta viva (texto de las policies b1642cf5... 5, huella a99ac4be... 307, helper presente).
-- Autochequeo: policies 59f52a89... 5, huella 66bef0e5... 307, ACL de funciones c7f89c6d... 380.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 366)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname))||' '||count(*)
     FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid WHERE pl.polrelid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM 'b1642cf529b1d5c6ee3c4bb98c2b68a6 5' THEN bad := bad||'policies de las 2 tablas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'a99ac4becc3fba65a272569c293fdd26 307' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  IF to_regprocedure('private.pais_empresa_onboarding()') IS NULL THEN bad := bad||'private.pais_empresa_onboarding no existe; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK366 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

DROP POLICY cuentas_banco_read_acotada ON public.cuentas_bancarias_pais;
DROP POLICY configuracion_sistema_select_anon_publicas ON public.configuracion_sistema;
DROP POLICY configuracion_sistema_select_authenticated_publicas ON public.configuracion_sistema;

CREATE POLICY cuentas_banco_read_pais ON public.cuentas_bancarias_pais
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (pais_id = private.mi_pais());
CREATE POLICY configuracion_sistema_select_authenticated ON public.configuracion_sistema
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);
CREATE POLICY configuracion_sistema_select_anon ON public.configuracion_sistema
  AS PERMISSIVE FOR SELECT TO anon
  USING (clave <> ALL (ARRAY['banco'::text, 'cuenta_bancaria'::text, 'tipo_cuenta'::text, 'titular_cuenta'::text, 'email_pagos'::text]));

DROP FUNCTION private.pais_empresa_onboarding();

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname))||' '||count(*)
     FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid WHERE pl.polrelid IN ('public.cuentas_bancarias_pais'::regclass, 'public.configuracion_sistema'::regclass));
  IF v IS DISTINCT FROM '59f52a89a6434f2bc3185e535f22c124 5' THEN bad := bad||'policies de las 2 tablas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '66bef0e55ba9d2a98434376a9222b5c6 307' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'c7f89c6df3048083e3722d6eec7d1998 380' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK366 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
