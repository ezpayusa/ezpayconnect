-- ############################################################################################
-- 360 ROLLBACK - las policies de campanas vuelven a como estaban antes de la 360
-- ############################################################################################
-- Restaura el texto EXACTO previo (tomado del objeto vivo el 4-oct-2026) de "Proveedor crea pagos" (pagos_proveedor),
-- "Proveedor crea campañas", "Proveedor actualiza sus campañas borrador" y "Admin ve solicitudes de su pais"
-- (solicitudes_campana) y "Admin ve campanas de su pais" (campanas_publicitarias), y borra las 3 policies nuevas
-- ("Proveedor elimina sus campañas borrador", campanas_superadmin_update, campanas_superadmin_delete).
-- Efecto: el proveedor vuelve a poder pagar una campana por INSERT directo (con el monto que mande), crear en 'enviada',
-- editar enviadas/rechazadas y no poder borrar; el admin_pais vuelve a escribir en campanas y solicitudes de su pais.
-- Va ANTES que 359_rollback (que exige la policy de pagos sin el termino de campana).
-- Precondicion: la 360 esta viva (md5 del texto de las policies de las 3 tablas). Autochequeo: md5 de partida y huella
-- de policies b2a47be7... 308.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 360)
DO $precondicion$
DECLARE v text;
BEGIN
  v := (SELECT string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname)
          FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass, 'public.pagos_proveedor'::regclass));
  IF md5(v) IS DISTINCT FROM 'e42777c562cf8e6897a24030bc304127' THEN
    RAISE EXCEPTION 'ROLLBACK360 PRECONDICION FALLA: las policies de las 3 tablas no son las de la 360 (md5 %)', md5(v);
  END IF;
END $precondicion$;

DROP POLICY "Proveedor elimina sus campañas borrador" ON public.solicitudes_campana;
DROP POLICY campanas_superadmin_update ON public.campanas_publicitarias;
DROP POLICY campanas_superadmin_delete ON public.campanas_publicitarias;

DROP POLICY "Proveedor crea pagos" ON public.pagos_proveedor;
CREATE POLICY "Proveedor crea pagos" ON public.pagos_proveedor
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((empresa_id = private.mi_empresa_onboarding()) AND (private.mi_rol_onboarding() = ANY (ARRAY['admin'::text, 'editor'::text, 'finanzas'::text, 'marketing'::text, 'supervisor'::text])) AND (estado = 'pendiente'::text) AND (verificado_por IS NULL) AND (fecha_verificacion IS NULL) AND (pvc_id IS NULL) AND (tipo <> 'plan_visitador'::text));

DROP POLICY "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text])) AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false));

DROP POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text])))
  WITH CHECK (COALESCE((empresa_id = public.mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text, 'editor'::text]))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text])));

DROP POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text) OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

DROP POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text) OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY c.relname, pl.polname)
          FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE pl.polrelid IN ('public.solicitudes_campana'::regclass, 'public.campanas_publicitarias'::regclass, 'public.pagos_proveedor'::regclass));
  IF md5(v) IS DISTINCT FROM 'e2885295ee6776570773c4be82fdb5b7' THEN bad := bad||'texto de las policies de las 3 tablas (md5 '||md5(v)||'); '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK360 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
