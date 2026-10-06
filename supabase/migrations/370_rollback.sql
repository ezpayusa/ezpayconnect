-- ############################################################################################
-- 370 ROLLBACK - EXECUTE de funciones: vuelven PUBLIC (38) y anon (21) tal cual el censo del 6-oct-2026
-- ############################################################################################
-- Restaura EXACTO con listas LITERALES generadas del censo de prod del 6-oct-2026 (no por catalogo): las 38 funciones de
-- public/private que tenian EXECUTE para PUBLIC reciben GRANT ... TO PUBLIC y las 21 legacy de public que tenian anon
-- explicito reciben GRANT ... TO anon (catalogo_planes_visitador_publico no se toca: la 370 no le saco anon).
-- Las 15 de private que tenian proacl NULL no vuelven a NULL: quedan con {postgres=X/postgres,=X/postgres}, que es el mismo
-- conjunto de privilegios que acldefault (dueno + PUBLIC, grantor postgres); la huella usa aclexplode(COALESCE(proacl,
-- acldefault)) y por eso vuelve a coincidir (medido en el dry-run C). Lo que difiere es solo proacl IS NULL (15 -> 0).
-- El GRANT documental de la 370 a authenticated/service_role sobre las 10 era un no-op y no se revierte.
-- El GRANT de private.entrega_visible(uuid, integer, uuid) a authenticated SI se revierte: vuelve a {postgres=X/postgres}
-- (y con eso vuelve el 42501 de entrega_evidencias para authenticated que la 370 cerro).
-- ORDEN: 370_rollback va ANTES que 369_rollback (369_rollback mira la ACL de funciones y la espera en e5c9770e... 384) y
-- ANTES que 350_rollback y 349_rollback: con la 370 viva, devolver esas policies a TO public le da a anon 42501 de FUNCION
-- (get_auth_user_pais_id) en configuracion_sistema y otras 8 tablas (medido en el dry-run A con P935/P936).
-- Precondicion: la 370 esta viva (huella 4878afd5... 384). Autochequeo: huella e5c9770e... 384; policies y ACL de
-- relaciones sin cambio.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 370)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4878afd5e7fa74667b466d6994d565ff 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'
' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK370 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- las 38 que tenian PUBLIC
GRANT EXECUTE ON FUNCTION private.es_staff_calendario_clinica(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_jornada_pais() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_pais_prospecto() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_pais_visita_comercial() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_reporte_exige_checkin() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_supervisor_asesor() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.medclaslog_solo_append() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.puede_aprobar_visitas() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.receta_items_modalidad_uniforme() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.reset_notificado_cancelacion() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.reset_notificado_envio() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.resolver_medicamento_id(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.safe_uuid(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_farmed_resolver_medid() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_gate_capacidad_productos() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_gate_capacidad_publicidad() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_guard_tema_columns() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.actualizar_stock_dispensacion() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_clinica_de_medico(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.calcular_imc_signos_vitales() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.calcular_limite_cancelacion(date) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_user_pais_id() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_user_rol() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_empresa_id_proveedor() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_empresa_id_session() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.limpiar_cache_biblioteca_expirada() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.mi_clinica_id() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.mi_empresa_proveedor() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.mi_rol_proveedor() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.perfiles_guard_rol_update() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.puede_ver_conversacion(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_fecha_limite_cancelacion() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.supervisa_cuenta_proveedor(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.trg_gate_head_start_lab() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.trg_medicos_lab_enrolador_inmutable() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_set_updated_at() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_config_timestamp() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO PUBLIC;

-- ---------------------------------------------------------------------------- las 21 legacy que tenian anon explicito
GRANT EXECUTE ON FUNCTION public.actualizar_stock_dispensacion() TO anon;
GRANT EXECUTE ON FUNCTION public.admin_clinica_de_medico(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.calcular_imc_signos_vitales() TO anon;
GRANT EXECUTE ON FUNCTION public.calcular_limite_cancelacion(date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_pais_id() TO anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_rol() TO anon;
GRANT EXECUTE ON FUNCTION public.get_empresa_id_proveedor() TO anon;
GRANT EXECUTE ON FUNCTION public.get_empresa_id_session() TO anon;
GRANT EXECUTE ON FUNCTION public.limpiar_cache_biblioteca_expirada() TO anon;
GRANT EXECUTE ON FUNCTION public.mi_clinica_id() TO anon;
GRANT EXECUTE ON FUNCTION public.mi_empresa_proveedor() TO anon;
GRANT EXECUTE ON FUNCTION public.mi_rol_proveedor() TO anon;
GRANT EXECUTE ON FUNCTION public.perfiles_guard_rol_update() TO anon;
GRANT EXECUTE ON FUNCTION public.puede_ver_conversacion(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.set_fecha_limite_cancelacion() TO anon;
GRANT EXECUTE ON FUNCTION public.supervisa_cuenta_proveedor(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.trg_gate_head_start_lab() TO anon;
GRANT EXECUTE ON FUNCTION public.trg_medicos_lab_enrolador_inmutable() TO anon;
GRANT EXECUTE ON FUNCTION public.trigger_set_updated_at() TO anon;
GRANT EXECUTE ON FUNCTION public.update_config_timestamp() TO anon;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO anon;

-- ---------------------------------------------------------------------------- entrega_visible vuelve a {postgres=X/postgres}
REVOKE EXECUTE ON FUNCTION private.entrega_visible(uuid, integer, uuid) FROM authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'e5c9770e31312d34601dc45f0c545173 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT proacl::text FROM pg_proc WHERE oid = 'private.entrega_visible(uuid,integer,uuid)'::regprocedure);
  IF v IS DISTINCT FROM '{postgres=X/postgres}' THEN bad := bad||'entrega_visible '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'
' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK370 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
