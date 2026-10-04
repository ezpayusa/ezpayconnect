-- ############################################################################################
-- 360 - campanas: cierre en el servidor (familia CAMPANAS). Se aplica DESPUES del merge del front (fronts A, B y C).
-- ############################################################################################
-- Recon del 4-oct-2026 (paso 0, solo lectura contra prod, con 358 y 359 aplicadas):
--   * Escrituras del front sobre las 3 tablas: el proveedor crea solicitudes SOLO en 'borrador' (useSolicitudesCampana:65,
--     unico caller el form), edita y borra con .eq('estado','borrador') (:141, :167), y paga por solicitar_pago_campana
--     (359). El super_admin rechaza solicitudes por "solicitudes_campana admin update" (SolicitudesCampanaPage:191), aprueba
--     por aprobar_solicitud_campana (358, DEFINER), y pausa/reactiva/elimina publicaciones (CampanasAdminContent:76/:86,
--     CampanasPublicitariasContent:161/:174) SOLO por la policy ALL "Admin ve campanas de su pais". El admin_pais no tiene
--     ninguna pantalla que escriba en estas tablas (AdminRoute lo confina a /admin-ezpay/pais/{id}).
--   * solicitudes_campana no tiene policy de DELETE para el proveedor: su "Eliminar" afectaba 0 filas.
-- Cambios (cada policy DROP + CREATE desde el texto vivo, cambiando SOLO lo indicado):
--   a pagos_proveedor "Proveedor crea pagos": + AND tipo <> 'campana' (el pago de campana es solo por solicitar_pago_campana).
--   b solicitudes_campana "Proveedor crea campañas": estado IN (borrador, enviada) -> estado = 'borrador' (a 'enviada' solo
--     se llega pagando por la RPC).
--   c solicitudes_campana "Proveedor actualiza sus campañas borrador": USING y WITH CHECK con estado = 'borrador' (antes
--     borrador/enviada/rechazada): el proveedor no edita una campana enviada ni la pasa de estado.
--   d solicitudes_campana NUEVA "Proveedor elimina sus campañas borrador" (DELETE): el mismo PROPIO y GESTOR de c, y estado =
--     'borrador'.
--   e campanas_publicitarias "Admin ve campanas de su pais": ALL -> SELECT (mismo USING). NUEVAS
--     "campanas_superadmin_update" (UPDATE, USING y WITH CHECK) y "campanas_superadmin_delete" (DELETE) con
--     COALESCE(private.tiene_rol(ARRAY['super_admin']), false): el super_admin conserva pausar/reactivar/eliminar; el
--     admin_pais pierde la escritura directa sobre las publicaciones de su pais.
--   f solicitudes_campana "Admin ve solicitudes de su pais": ALL -> SELECT (mismo USING). El super_admin sigue rechazando
--     por "solicitudes_campana admin update".
-- Probes: P983-P989. P980 y el caso 6 de P939 pasan solos de 'PENDIENTE mig 360' a OK (detectan el termino por catalogo).
-- Pendiente (lote 2): la pantalla de alta de house-ads (CampanasPublicitariasContent) quedo sin ruta con el front C.
-- Rollback: 360_rollback.sql (texto exacto previo de cada policy; borra las 3 nuevas). Va ANTES que 359_rollback.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname)
          FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass, 'public.pagos_proveedor'::regclass));
  IF md5(v) IS DISTINCT FROM 'e2885295ee6776570773c4be82fdb5b7' THEN bad := bad||'policies de partida de las 3 tablas (md5 '||md5(v)||'); '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones (la 359 tiene que estar viva) '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG360 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- a: sin INSERT directo de pagos de campana
DROP POLICY "Proveedor crea pagos" ON public.pagos_proveedor;
CREATE POLICY "Proveedor crea pagos" ON public.pagos_proveedor
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((empresa_id = private.mi_empresa_onboarding()) AND (private.mi_rol_onboarding() = ANY (ARRAY['admin'::text, 'editor'::text, 'finanzas'::text, 'marketing'::text, 'supervisor'::text])) AND (estado = 'pendiente'::text) AND (verificado_por IS NULL) AND (fecha_verificacion IS NULL) AND (pvc_id IS NULL) AND (tipo <> 'plan_visitador'::text) AND (tipo <> 'campana'::text));

-- ---------------------------------------------------------------------------- b: el proveedor crea solo en borrador
DROP POLICY "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = 'borrador'::text) AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false));

-- ---------------------------------------------------------------------------- c: el proveedor edita solo en borrador
DROP POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = 'borrador'::text))
  WITH CHECK (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = 'borrador'::text));

-- ---------------------------------------------------------------------------- d: el proveedor borra solo en borrador
CREATE POLICY "Proveedor elimina sus campañas borrador" ON public.solicitudes_campana
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = 'borrador'::text));

-- ---------------------------------------------------------------------------- e: publicaciones: admin_pais solo lee; super_admin escribe
DROP POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text) OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));
CREATE POLICY campanas_superadmin_update ON public.campanas_publicitarias
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false))
  WITH CHECK (COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false));
CREATE POLICY campanas_superadmin_delete ON public.campanas_publicitarias
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false));

-- ---------------------------------------------------------------------------- f: solicitudes: admin_pais solo lee
DROP POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text) OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname)
          FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass, 'public.pagos_proveedor'::regclass));
  IF md5(v) IS DISTINCT FROM 'e42777c562cf8e6897a24030bc304127' THEN bad := bad||'texto de las policies de las 3 tablas (md5 '||md5(v)||'); '; END IF;
  v := (SELECT string_agg(x.s, ',' ORDER BY x.s) FROM (SELECT c.relname||':'||pl.polcmd::text||'='||count(*) AS s FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass, 'public.pagos_proveedor'::regclass)
         GROUP BY c.relname, pl.polcmd) x);
  IF v IS DISTINCT FROM 'campanas_publicitarias:a=1,campanas_publicitarias:d=1,campanas_publicitarias:r=2,campanas_publicitarias:w=1,pagos_proveedor:*=1,pagos_proveedor:a=1,pagos_proveedor:r=1,solicitudes_campana:a=1,solicitudes_campana:d=1,solicitudes_campana:r=3,solicitudes_campana:w=2' THEN bad := bad||'conteo por tabla y cmd '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass) AND pl.polcmd = '*') THEN
    bad := bad||'quedan policies ALL en solicitudes_campana o campanas_publicitarias; ';
  END IF;
  IF position('(tipo <> ''campana''::text)' IN (SELECT pg_get_expr(pl.polwithcheck, pl.polrelid) FROM pg_policy pl WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos')) = 0 THEN
    bad := bad||'a: sin el termino de campana; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG360 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
