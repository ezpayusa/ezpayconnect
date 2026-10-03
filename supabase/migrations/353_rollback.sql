-- ############################################################################################
-- 353_rollback - deshace la 353 (delivery: tablero, lote, errcodes DE, push al asignar)
-- ############################################################################################
-- * asignar_entrega / reasignar_entrega: replace() INVERSO sobre el prosrc vivo de la 353 (md5 verificado antes y
--   despues): vuelven exactamente a ff727cc7... / 2883d4d8... (P0001 con texto, sin notificacion).
-- * DROP de las 4 funciones nuevas.
-- * Las notificaciones ya emitidas (tipo entrega_asignada / entrega_quitada) quedan: son historial del usuario.
-- * Huellas finales = las previas a la 353: ACL de funciones b8189120ac3d1ffc8820e5ed8371c010 370, policies
--   700082376ca04bcbb59eb743fe79c5ee 309; relaciones, columnas, defaults y publicacion sin cambio.
-- Orden global: 353_rollback -> 352_rollback -> 351_rollback -> ...
-- ############################################################################################

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(n.nspname||'.'||p.proname, ',' ORDER BY n.nspname, p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('public','private')
           AND p.proname IN ('notificar_entregas_asignadas','tablero_repartidores','listar_repartidores_asignables','asignar_entregas_lote'));
  IF v IS DISTINCT FROM 'private.notificar_entregas_asignadas,public.asignar_entregas_lote,public.listar_repartidores_asignables,public.tablero_repartidores' THEN
    bad := bad||'funciones de la 353 '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  v := (SELECT string_agg(p.proname||'='||md5(p.prosrc), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('asignar_entrega','reasignar_entrega'));
  IF v IS DISTINCT FROM 'asignar_entrega=e4b71601daea948e93aca10eb33198bb,reasignar_entrega=2647876d8273953b7624961dc7528c10' THEN
    bad := bad||'cuerpos de la 353 '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '70a9dc38e222ca940d755103c7940c5a 374' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK353 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cuerpos originales (replace inverso)
DO $reemplazo$
DECLARE v_src text; v_new text; r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('asignar_entrega', 'e4b71601daea948e93aca10eb33198bb', 'ff727cc7d4fb59bcee517b5ad13c2b87',
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado'' USING ERRCODE = ''42501''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'' USING ERRCODE = ''DE001'';',
         'RAISE EXCEPTION ''Solo se asigna desde pendiente (estado=%)'', v_e.estado USING ERRCODE = ''DE002'';',
         'RAISE EXCEPTION ''Delivery inválido (no es delivery activo de la empresa)'' USING ERRCODE = ''DE003'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'' USING ERRCODE = ''DE004'';',
         '  PERFORM private.notificar_entregas_asignadas(p_delivery_id, ARRAY[p_entrega_id], NULL);'||E'\n'],
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'';',
         'RAISE EXCEPTION ''Solo se asigna desde pendiente (estado=%)'', v_e.estado;',
         'RAISE EXCEPTION ''Delivery inválido (no es delivery activo de la empresa)'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'';',
         '']),
      ('reasignar_entrega', '2647876d8273953b7624961dc7528c10', '2883d4d8ad8a691e567bc8e879f2bd23',
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado'' USING ERRCODE = ''42501''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'' USING ERRCODE = ''DE001'';',
         'RAISE EXCEPTION ''Entrega ya cobrada: no reasignable'' USING ERRCODE = ''DE005'';',
         'RAISE EXCEPTION ''No reasignable desde estado %'', v_e.estado USING ERRCODE = ''DE006'';',
         'RAISE EXCEPTION ''Delivery inválido'' USING ERRCODE = ''DE003'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'' USING ERRCODE = ''DE004'';',
         '  PERFORM private.notificar_entregas_asignadas(p_delivery_id, ARRAY[p_entrega_id], v_e.delivery_id);'||E'\n'],
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'';',
         'RAISE EXCEPTION ''Entrega ya cobrada: no reasignable'';',
         'RAISE EXCEPTION ''No reasignable desde estado %'', v_e.estado;',
         'RAISE EXCEPTION ''Delivery inválido'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'';',
         ''])
    ) t(fn, md5_actual, md5_original, desde, hacia)
  LOOP
    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = r.fn;
    IF md5(v_src) IS DISTINCT FROM r.md5_actual THEN
      RAISE EXCEPTION 'ROLLBACK353: % md5 de partida % (esperado %)', r.fn, md5(v_src), r.md5_actual;
    END IF;
    v_new := v_src;
    FOR i IN 1 .. array_length(r.desde, 1) LOOP
      IF (length(v_src) - length(replace(v_src, r.desde[i], ''))) / length(r.desde[i]) <> 1 THEN
        RAISE EXCEPTION 'ROLLBACK353: % fragmento % no aparece exactamente una vez', r.fn, i;
      END IF;
      v_new := replace(v_new, r.desde[i], r.hacia[i]);
    END LOOP;
    IF md5(v_new) IS DISTINCT FROM r.md5_original THEN
      RAISE EXCEPTION 'ROLLBACK353: % md5 restaurado % (esperado %)', r.fn, md5(v_new), r.md5_original;
    END IF;
    EXECUTE format('CREATE OR REPLACE FUNCTION public.%I(p_entrega_id bigint, p_delivery_id uuid) RETURNS jsonb '
                   'LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS %L', r.fn, v_new);
  END LOOP;
END $reemplazo$;

DROP FUNCTION public.asignar_entregas_lote(bigint[], uuid);
DROP FUNCTION public.listar_repartidores_asignables(bigint);
DROP FUNCTION public.tablero_repartidores(bigint);
DROP FUNCTION private.notificar_entregas_asignadas(uuid, bigint[], uuid);

-- ---------------------------------------------------------------------------- autochequeo (estado previo a la 353)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.proname||'='||md5(p.prosrc)||':'||p.prosecdef::text||':'||COALESCE(array_to_string(p.proconfig, ','), '-'), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('asignar_entrega','reasignar_entrega'));
  IF v IS DISTINCT FROM 'asignar_entrega=ff727cc7d4fb59bcee517b5ad13c2b87:true:search_path="",reasignar_entrega=2883d4d8ad8a691e567bc8e879f2bd23:true:search_path=""' THEN
    bad := bad||'cuerpos originales '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.prosrc ~ '''DE[0-9]{3}''');
  IF v IS NOT NULL THEN bad := bad||'quedan errcodes DE en: '||v||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b8189120ac3d1ffc8820e5ed8371c010 370' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK353 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
