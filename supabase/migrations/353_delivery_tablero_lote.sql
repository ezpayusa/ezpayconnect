-- ############################################################################################
-- 353 - delivery (lote demo 1): tablero de repartidores, asignacion en tanda, errcodes DE y push al asignar
-- ############################################################################################
-- Recon del 3-oct-2026 sobre d6b9a32 (solo lectura contra prod):
--   * asignar_entrega / reasignar_entrega (DEFINER, search_path='', EXECUTE authenticated+service_role) levantan
--     todo como P0001 con texto; gate private.tiene_permiso('entregas_gestionar') (farmacia: admin,
--     gerente_farmacia, supervisor; sin overrides). Ningun llamador en el front.
--   * No hay forma de listar repartidores sin backend: cuentas_proveedor solo deja leer la empresa al admin
--     (gerente ve su fila, supervisor solo visitadores).
--   * Push transaccional = INSERT en public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url) +
--     PERFORM private.push_notificar('notificaciones', id) -> net.http_post a la edge enviar-push-notificacion
--     (secreto compartido; re-deriva destinatario y contenido de la fila; claim idempotente push_enviado).
--     pg_net encola en una tabla: si la transaccion hace ROLLBACK, el push no sale.
--   * public.notificaciones ya esta en supabase_realtime y su SELECT es (auth.uid() = usuario_id) o super_admin:
--     el repartidor solo recibe por realtime sus propias filas. entregas NO esta en la publicacion (no se agrega).
--   * Prefijo DE libre (0 funciones con 'DE[0-9]{3}').
-- Cambios:
--   A  private.notificar_entregas_asignadas(p_delivery uuid, p_entrega_ids bigint[], p_anterior uuid) -> void:
--      UNA notificacion por llamada al repartidor ("Tenes N entregas nuevas", tipo entrega_asignada,
--      accion_url /repartidor) y, si p_anterior es otro, UNA al anterior (tipo entrega_quitada). Cada fila con su
--      push best-effort. Sin datos del paciente. EXECUTE solo postgres (la llaman las RPCs DEFINER).
--   B  public.tablero_repartidores(p_farmacia_id bigint DEFAULT NULL): por repartidor activo (rol delivery) de la
--      empresa en sucursales visibles: carga actual y del dia (UTC). Gate entregas_ver y rol <> delivery.
--   C  public.listar_repartidores_asignables(p_entrega_id bigint): los que asignar_entrega aceptaria para esa
--      entrega (misma empresa, delivery, activo, misma sucursal), con su carga. Gate entregas_gestionar.
--   D  public.asignar_entregas_lote(p_entrega_ids bigint[], p_delivery_id uuid) -> jsonb: atomica, mismas reglas
--      que asignar_entrega por entrega, 1..50 ids sin repetidos; la primera que falla aborta todo y viaja en DETAIL.
--   E  asignar_entrega / reasignar_entrega: cuerpo armado con replace() sobre el prosrc vivo (md5 verificado antes
--      y despues): solo agregan USING ERRCODE a cada RAISE y una llamada a A antes del RETURN final.
-- Errcodes (familia DE, delivery; el front distingue el modulo por el prefijo):
--   42501 sin permiso (gate de cada RPC)
--   DE001 la entrega no existe o no es visible (otra empresa o sucursal fuera de alcance)
--   DE002 la entrega no esta pendiente (asignar, lote)
--   DE003 el repartidor no es delivery activo de la empresa
--   DE004 el repartidor no es de la sucursal de la entrega
--   DE005 la entrega ya esta cobrada: no se reasigna
--   DE006 la entrega no se puede reasignar desde su estado (solo asignada, en_camino, fallida)
--   DE007 lote vacio   DE008 lote de mas de 50   DE009 lote con ids repetidos o NULL
--   DE010+ libres.
-- Tablero: entregadas_hoy por entregado_at y fallidas_hoy por updated_at (no hay fallida_at), con hoy en UTC
-- (el mismo CURRENT_DATE del servidor).
-- Huellas: policies 700082376ca04bcbb59eb743fe79c5ee 309, ACL de relaciones, grants por columna, pg_default_acl y
-- publicacion supabase_realtime sin cambio; ACL de funciones public/private b8189120ac3d1ffc8820e5ed8371c010 370 ->
-- (ver autochequeo) 374.
-- Probes: P940 (gates por rol), P941 (lote atomico + DE007-DE009 + 1 notificacion), P942 (asignar/reasignar:
-- errcodes + notificaciones al nuevo y al anterior + tablero), P943 (catalogo: DEFINER, search_path, ACL, sin
-- columnas de pacientes).
-- Rollback: 353_rollback.sql (restaura los dos cuerpos originales por replace inverso y borra las 4 funciones).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(n.nspname||'.'||p.proname, ',') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('public','private')
           AND p.proname IN ('notificar_entregas_asignadas','tablero_repartidores','listar_repartidores_asignables','asignar_entregas_lote'));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existen: '||v||'; '; END IF;
  v := (SELECT string_agg(p.proname||'='||md5(p.prosrc), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('asignar_entrega','reasignar_entrega'));
  IF v IS DISTINCT FROM 'asignar_entrega=ff727cc7d4fb59bcee517b5ad13c2b87,reasignar_entrega=2883d4d8ad8a691e567bc8e879f2bd23' THEN
    bad := bad||'cuerpos de partida '||COALESCE(v, 'no existen')||'; ';
  END IF;
  v := (SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.prosrc ~ '''DE[0-9]{3}''');
  IF v IS NOT NULL THEN bad := bad||'prefijo DE en uso: '||v||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b8189120ac3d1ffc8820e5ed8371c010 370' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG353 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A. notificacion al repartidor
CREATE FUNCTION private.notificar_entregas_asignadas(p_delivery uuid, p_entrega_ids bigint[], p_anterior uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE v_n integer := COALESCE(cardinality(p_entrega_ids), 0); v_nid uuid;
BEGIN
  IF p_delivery IS NULL OR v_n = 0 THEN RETURN; END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
  VALUES (p_delivery, 'entrega_asignada',
          CASE WHEN v_n = 1 THEN 'Tenés 1 entrega nueva' ELSE 'Tenés '||v_n||' entregas nuevas' END,
          CASE WHEN v_n = 1 THEN 'Te asignaron una entrega. Abrí tu cola para verla.'
               ELSE 'Te asignaron '||v_n||' entregas. Abrí tu cola para verlas.' END,
          '/repartidor', jsonb_build_object('entrega_ids', to_jsonb(p_entrega_ids)))
  RETURNING id INTO v_nid;
  PERFORM private.push_notificar('notificaciones', v_nid::text);           -- push best-effort (sale al COMMIT)

  IF p_anterior IS NOT NULL AND p_anterior <> p_delivery THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
    VALUES (p_anterior, 'entrega_quitada', 'Te quitaron una entrega',
            'Una entrega que tenías asignada pasó a otro repartidor.',
            '/repartidor', jsonb_build_object('entrega_ids', to_jsonb(p_entrega_ids)))
    RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION private.notificar_entregas_asignadas(uuid, bigint[], uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------- B. tablero del gerente
CREATE FUNCTION public.tablero_repartidores(p_farmacia_id bigint DEFAULT NULL)
RETURNS TABLE (repartidor_id uuid, nombre text, sucursal_id integer, sucursal_nombre text,
               asignadas integer, en_camino integer, entregadas_hoy integer, fallidas_hoy integer, estado_calc text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
#variable_conflict use_column
DECLARE v_hoy date := (now() AT TIME ZONE 'UTC')::date;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false)
     OR COALESCE(public.mi_rol_proveedor(), 'delivery') = 'delivery' THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT cp.id, cp.nombre_completo, cp.sucursal_id, f.nombre,
         (count(e.id) FILTER (WHERE e.estado = 'asignada'))::integer,
         (count(e.id) FILTER (WHERE e.estado = 'en_camino'))::integer,
         (count(e.id) FILTER (WHERE e.estado = 'entregada' AND (e.entregado_at AT TIME ZONE 'UTC')::date = v_hoy))::integer,
         (count(e.id) FILTER (WHERE e.estado = 'fallida' AND (e.updated_at AT TIME ZONE 'UTC')::date = v_hoy))::integer,
         CASE WHEN count(e.id) FILTER (WHERE e.estado IN ('asignada','en_camino')) = 0 THEN 'libre' ELSE 'en_ruta' END
    FROM public.cuentas_proveedor cp
    LEFT JOIN public.farmacias f ON f.id = cp.sucursal_id
    LEFT JOIN public.entregas e ON e.delivery_id = cp.id AND e.empresa_id = cp.empresa_id
   WHERE COALESCE(cp.empresa_id = public.mi_empresa_proveedor(), false)
     AND cp.rol_en_empresa = 'delivery' AND cp.activo = true
     AND COALESCE(private.sucursal_visible(cp.sucursal_id), false)
     AND (p_farmacia_id IS NULL OR cp.sucursal_id = p_farmacia_id)
   GROUP BY cp.id, cp.nombre_completo, cp.sucursal_id, f.nombre
   ORDER BY cp.nombre_completo, cp.id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.tablero_repartidores(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tablero_repartidores(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- C. repartidores asignables
CREATE FUNCTION public.listar_repartidores_asignables(p_entrega_id bigint)
RETURNS TABLE (repartidor_id uuid, nombre text, asignadas integer, en_camino integer, estado_calc text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
#variable_conflict use_column
DECLARE v_e public.entregas;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id = p_entrega_id
    AND COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe' USING ERRCODE = 'DE001'; END IF;
  RETURN QUERY
  SELECT cp.id, cp.nombre_completo,
         (count(e.id) FILTER (WHERE e.estado = 'asignada'))::integer,
         (count(e.id) FILTER (WHERE e.estado = 'en_camino'))::integer,
         CASE WHEN count(e.id) FILTER (WHERE e.estado IN ('asignada','en_camino')) = 0 THEN 'libre' ELSE 'en_ruta' END
    FROM public.cuentas_proveedor cp
    LEFT JOIN public.entregas e ON e.delivery_id = cp.id AND e.empresa_id = cp.empresa_id
   WHERE cp.empresa_id = v_e.empresa_id AND cp.rol_en_empresa = 'delivery' AND cp.activo = true
     AND cp.sucursal_id = v_e.farmacia_id
   GROUP BY cp.id, cp.nombre_completo
   ORDER BY count(e.id) FILTER (WHERE e.estado IN ('asignada','en_camino')), cp.nombre_completo, cp.id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.listar_repartidores_asignables(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_repartidores_asignables(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- D. asignacion en tanda
CREATE FUNCTION public.asignar_entregas_lote(p_entrega_ids bigint[], p_delivery_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_n integer := COALESCE(cardinality(p_entrega_ids), 0); v_id bigint; v_e public.entregas;
  v_del public.cuentas_proveedor; v_emp uuid;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;
  IF v_n = 0 THEN RAISE EXCEPTION 'El lote esta vacio' USING ERRCODE = 'DE007'; END IF;
  IF v_n > 50 THEN RAISE EXCEPTION 'El lote supera el maximo de 50 entregas (%)', v_n USING ERRCODE = 'DE008'; END IF;
  IF array_position(p_entrega_ids, NULL) IS NOT NULL
     OR (SELECT count(DISTINCT x) FROM unnest(p_entrega_ids) x) <> v_n THEN
    RAISE EXCEPTION 'El lote tiene entregas repetidas o vacias' USING ERRCODE = 'DE009';
  END IF;

  v_emp := public.mi_empresa_proveedor();
  -- bloquea las filas del lote en orden de id: dos tandas concurrentes no se cruzan (ni deadlock ni doble asignacion)
  PERFORM 1 FROM public.entregas e WHERE e.id = ANY (p_entrega_ids) AND e.empresa_id = v_emp ORDER BY e.id FOR UPDATE;

  -- mismas reglas y mismo orden que asignar_entrega, entrega por entrega; la primera que falla aborta todo
  FOREACH v_id IN ARRAY p_entrega_ids LOOP
    SELECT * INTO v_e FROM public.entregas WHERE id = v_id
      AND COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
      AND COALESCE(private.sucursal_visible(farmacia_id), false);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Entrega %: no visible/no existe', v_id USING ERRCODE = 'DE001', DETAIL = v_id::text;
    END IF;
    IF v_e.estado <> 'pendiente' THEN
      RAISE EXCEPTION 'Entrega %: solo se asigna desde pendiente (estado=%)', v_id, v_e.estado USING ERRCODE = 'DE002', DETAIL = v_id::text;
    END IF;
    SELECT * INTO v_del FROM public.cuentas_proveedor
      WHERE id = p_delivery_id AND empresa_id = v_e.empresa_id AND rol_en_empresa = 'delivery' AND activo = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Entrega %: delivery invalido (no es delivery activo de la empresa)', v_id USING ERRCODE = 'DE003', DETAIL = v_id::text;
    END IF;
    IF v_del.sucursal_id IS DISTINCT FROM v_e.farmacia_id THEN
      RAISE EXCEPTION 'Entrega %: el delivery no pertenece a la sucursal de la entrega', v_id USING ERRCODE = 'DE004', DETAIL = v_id::text;
    END IF;
  END LOOP;

  UPDATE public.entregas SET estado = 'asignada', delivery_id = p_delivery_id,
         asignado_por = auth.uid(), asignado_at = now(), updated_at = now()
   WHERE id = ANY (p_entrega_ids);

  PERFORM private.notificar_entregas_asignadas(p_delivery_id, p_entrega_ids, NULL);

  RETURN jsonb_build_object('ok', true, 'asignadas', v_n, 'delivery_id', p_delivery_id, 'entrega_ids', to_jsonb(p_entrega_ids));
END;
$fn$;

REVOKE ALL ON FUNCTION public.asignar_entregas_lote(bigint[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.asignar_entregas_lote(bigint[], uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- E. errcodes + push en las 2 RPCs vivas
-- Patron de la 347: el cuerpo nuevo se arma con replace() sobre el prosrc vivo; cada fragmento tiene que aparecer
-- EXACTAMENTE una vez, y el md5 del resultado se verifica antes de ejecutar. La logica no cambia.
DO $reemplazo$
DECLARE
  v_src text; v_new text; v_md5_nuevo text;
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('asignar_entrega', 'ff727cc7d4fb59bcee517b5ad13c2b87',
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'';',
         'RAISE EXCEPTION ''Solo se asigna desde pendiente (estado=%)'', v_e.estado;',
         'RAISE EXCEPTION ''Delivery inválido (no es delivery activo de la empresa)'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'';',
         '  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);'],
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado'' USING ERRCODE = ''42501''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'' USING ERRCODE = ''DE001'';',
         'RAISE EXCEPTION ''Solo se asigna desde pendiente (estado=%)'', v_e.estado USING ERRCODE = ''DE002'';',
         'RAISE EXCEPTION ''Delivery inválido (no es delivery activo de la empresa)'' USING ERRCODE = ''DE003'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'' USING ERRCODE = ''DE004'';',
         '  PERFORM private.notificar_entregas_asignadas(p_delivery_id, ARRAY[p_entrega_id], NULL);'||E'\n'||
         '  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);']),
      ('reasignar_entrega', '2883d4d8ad8a691e567bc8e879f2bd23',
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'';',
         'RAISE EXCEPTION ''Entrega ya cobrada: no reasignable'';',
         'RAISE EXCEPTION ''No reasignable desde estado %'', v_e.estado;',
         'RAISE EXCEPTION ''Delivery inválido'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'';',
         '  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);'],
       ARRAY[
         'THEN RAISE EXCEPTION ''No autorizado'' USING ERRCODE = ''42501''; END IF;',
         'RAISE EXCEPTION ''Entrega no visible/no existe'' USING ERRCODE = ''DE001'';',
         'RAISE EXCEPTION ''Entrega ya cobrada: no reasignable'' USING ERRCODE = ''DE005'';',
         'RAISE EXCEPTION ''No reasignable desde estado %'', v_e.estado USING ERRCODE = ''DE006'';',
         'RAISE EXCEPTION ''Delivery inválido'' USING ERRCODE = ''DE003'';',
         'RAISE EXCEPTION ''El delivery no pertenece a la sucursal de la entrega'' USING ERRCODE = ''DE004'';',
         '  PERFORM private.notificar_entregas_asignadas(p_delivery_id, ARRAY[p_entrega_id], v_e.delivery_id);'||E'\n'||
         '  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);'])
    ) t(fn, md5_viejo, desde, hacia)
  LOOP
    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = r.fn;
    IF md5(v_src) IS DISTINCT FROM r.md5_viejo THEN
      RAISE EXCEPTION 'MIG353: % md5 de partida % (esperado %)', r.fn, md5(v_src), r.md5_viejo;
    END IF;
    v_new := v_src;
    FOR i IN 1 .. array_length(r.desde, 1) LOOP
      -- "Delivery inválido" es prefijo del texto largo en asignar_entrega: se cuenta sobre el cuerpo de PARTIDA
      IF (length(v_src) - length(replace(v_src, r.desde[i], ''))) / length(r.desde[i]) <> 1 THEN
        RAISE EXCEPTION 'MIG353: % fragmento % aparece % veces', r.fn, i,
          (length(v_src) - length(replace(v_src, r.desde[i], ''))) / length(r.desde[i]);
      END IF;
      v_new := replace(v_new, r.desde[i], r.hacia[i]);
    END LOOP;
    v_md5_nuevo := CASE r.fn WHEN 'asignar_entrega' THEN 'e4b71601daea948e93aca10eb33198bb' ELSE '2647876d8273953b7624961dc7528c10' END;
    IF md5(v_new) IS DISTINCT FROM v_md5_nuevo THEN
      RAISE EXCEPTION 'MIG353: % md5 del cuerpo nuevo % (esperado %)', r.fn, md5(v_new), v_md5_nuevo;
    END IF;
    EXECUTE format('CREATE OR REPLACE FUNCTION public.%I(p_entrega_id bigint, p_delivery_id uuid) RETURNS jsonb '
                   'LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS %L', r.fn, v_new);
  END LOOP;
END $reemplazo$;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- las 5 publicas y la privada: DEFINER, search_path='', ACL exacta
  v := (SELECT string_agg(n.nspname||'.'||p.proname||':'||p.prosecdef::text||':'||COALESCE(array_to_string(p.proconfig, ','), '-')||':'||
           (SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'='||a.privilege_type, '+'
                               ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END)
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a), ',' ORDER BY n.nspname, p.proname)
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE (n.nspname = 'public' AND p.proname IN ('tablero_repartidores','listar_repartidores_asignables','asignar_entregas_lote','asignar_entrega','reasignar_entrega'))
            OR (n.nspname = 'private' AND p.proname = 'notificar_entregas_asignadas'));
  IF v IS DISTINCT FROM 'private.notificar_entregas_asignadas:true:search_path="":postgres=EXECUTE,'
                     || 'public.asignar_entrega:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
                     || 'public.asignar_entregas_lote:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
                     || 'public.listar_repartidores_asignables:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
                     || 'public.reasignar_entrega:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
                     || 'public.tablero_repartidores:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE' THEN
    bad := bad||'funciones '||COALESCE(v, 'no existen')||'; ';
  END IF;
  v := (SELECT string_agg(p.proname||'='||md5(p.prosrc), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('asignar_entrega','reasignar_entrega'));
  IF v IS DISTINCT FROM 'asignar_entrega=e4b71601daea948e93aca10eb33198bb,reasignar_entrega=2647876d8273953b7624961dc7528c10' THEN bad := bad||'cuerpos nuevos '||COALESCE(v, '-')||'; '; END IF;
  -- el tablero no devuelve datos de pacientes ni telefono
  v := pg_get_function_result('public.tablero_repartidores(bigint)'::regprocedure);
  IF v IS DISTINCT FROM 'TABLE(repartidor_id uuid, nombre text, sucursal_id integer, sucursal_nombre text, asignadas integer, en_camino integer, entregadas_hoy integer, fallidas_hoy integer, estado_calc text)' THEN
    bad := bad||'firma del tablero '||COALESCE(v, '-')||'; ';
  END IF;
  -- huellas: policies, relaciones, columnas, defaults y publicacion sin cambio; funciones con las 4 nuevas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '70a9dc38e222ca940d755103c7940c5a 374' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG353 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
