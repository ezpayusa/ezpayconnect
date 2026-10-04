-- ############################################################################################
-- 359 - campanas: el precio lo fija el servidor (familia CAMPANAS, punto 2)
-- ############################################################################################
-- Recon del 4-oct-2026 sobre la rama fix/campanas-publicacion (358 aplicada), solo lectura contra prod:
--   * Checkout de campana (PagoCheckoutPage.tsx): el monto sale de ?monto= de la URL (:27) y la moneda de la cuenta
--     bancaria del pais (:29), no del plan. usePagosProveedor.crearPago (:61-:93) sube el comprobante a
--     comprobantes/{empresa}/{ts}.{ext} y hace INSERT directo del pago con ese monto (metodo_pago 'transferencia',
--     comprobante_url = URL publica del bucket privado, fecha_pago = hoy); despues el checkout hace UPDATE de la
--     solicitud a 'enviada' con monto_pagado = el monto de la URL (:61-:64) y llama a notificar_campana_enviada (:70).
--     Cualquier proveedor con rol de la policy podia pagar 1 por una campana de 8000.
--   * Regla de precio del front (usePlanesPublicidad.ts): solo planes_publicidad activos; precio = la config ACTIVA del
--     pais (planes_publicidad_config.precio_local / moneda_local, UNIQUE (pais_id, plan_publicidad_id)) y si no hay, el
--     precio / moneda del plan base. El pais es el de la empresa; en prod solicitudes_campana.pais_id = el de su empresa
--     en el 100% de las filas (0 distintas), y el servidor usa el de la solicitud.
--   * Molde: solicitar_compra_plan_visitador (351): empresa y rol por private.mi_empresa_onboarding/mi_rol_onboarding,
--     comprobante = path que empieza con '{empresa}/' y existe en storage.objects del bucket 'comprobantes'.
--   * Policy "Proveedor crea pagos" (INSERT, authenticated): empresa propia, rol admin/editor/finanzas/marketing/
--     supervisor, estado pendiente, sin verificado_por/fecha_verificacion/pvc_id, tipo <> plan_visitador.
-- Cambios:
--   A private.precio_plan_publicidad(p_pais_id uuid, p_plan_id integer) -> TABLE(monto, moneda): la regla del front, en el
--     servidor. Plan inexistente o inactivo -> 0 filas. DEFINER, search_path '', EXECUTE solo postgres.
--   B public.cotizar_campana(p_solicitud_id) -> TABLE(monto, moneda): lectura para el checkout. CA009 si la solicitud no
--     es de la empresa del caller o su rol no puede pagar (no revela si existe); CA010 sin precio resoluble.
--   C public.solicitar_pago_campana(p_solicitud_id, p_comprobante_path) -> uuid (id del pago). Orden: gate de empresa y
--     rol (CA009) -> solicitud FOR UPDATE -> ya tiene pago tipo 'campana' (CA012) -> estado 'borrador' (CA011) -> precio
--     (CA010) -> comprobante (CA013) -> INSERT del pago (monto y moneda del servidor, 'pendiente', 'transferencia',
--     comprobante_url = path) -> solicitud 'enviada' con monto_pagado = monto del servidor. CA012 va ANTES que CA011: si
--     no, una segunda llamada (la solicitud ya quedo 'enviada') saldria por CA011 y nunca se veria el doble pago. Sin
--     notificaciones adentro (el front llama a notificar_campana_enviada).
--   La 359 es SOLO ADITIVA: no toca la policy "Proveedor crea pagos". El checkout actual (INSERT directo del pago) sigue
--     andando mientras el front pasa a solicitar_pago_campana.
--   PENDIENTE MIG 360 (despues del merge del front): cerrar el INSERT directo de pagos tipo 'campana' con
--     AND tipo <> 'campana' en el WITH CHECK de "Proveedor crea pagos" (plan_laboratorio y plan_farmacia siguen igual).
--   Grants: REVOKE de PUBLIC y anon en B y C, GRANT a authenticated y service_role; A sin EXECUTE para nadie salvo postgres.
-- Errcodes: CA009-CA013. Proximo libre: CA014.
-- Probes: P975-P982. P980 (INSERT directo de campana -> 42501) y el caso 6 de P939 quedan en 'pendiente mig 360' hasta
--   que la policy tenga el termino (lo detectan por catalogo). P939: los casos 1-4 pasan a tipo plan_laboratorio (con
--   campana darian 42501 por el termino de la 360 y dejarian de medir lo que dicen); caso 7 nuevo: plan_laboratorio
--   pendiente -> 1 fila.
-- Sin ventana rota: la 359 no cierra nada; el front nuevo y el viejo andan los dos con la base de la 359.
-- Rollback: 359_rollback.sql (DROP de las 3 funciones; no toca policies).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('private.precio_plan_publicidad(uuid,integer)') IS NOT NULL OR to_regprocedure('public.cotizar_campana(uuid)') IS NOT NULL
     OR to_regprocedure('public.solicitar_pago_campana(uuid,text)') IS NOT NULL THEN
    bad := bad||'alguna de las 3 funciones ya existe; ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')||' owner='||pg_get_userbyid(p.proowner), ';' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace AND p.proname IN ('mi_empresa_onboarding','mi_rol_onboarding'));
  IF v IS DISTINCT FROM 'private.mi_empresa_onboarding() sp=search_path="" owner=postgres;private.mi_rol_onboarding() sp=search_path="" owner=postgres' THEN bad := bad||'helpers'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM '64b305dcaa95e8bd2a881d64afc45413' THEN bad := bad||'la 358 no esta viva ('||COALESCE(v, '-')||'); '; END IF;
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
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG359 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: precio en el servidor
CREATE FUNCTION private.precio_plan_publicidad(p_pais_id uuid, p_plan_id integer)
 RETURNS TABLE(monto numeric, moneda text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- la regla de usePlanesPublicidad: solo planes activos; la config ACTIVA del pais y si no hay, el plan base
  SELECT COALESCE(c.precio_local, pp.precio), COALESCE(c.moneda_local, pp.moneda)
    FROM public.planes_publicidad pp
    LEFT JOIN public.planes_publicidad_config c
           ON c.plan_publicidad_id = pp.id AND c.pais_id = p_pais_id AND c.activo
   WHERE pp.id = p_plan_id AND pp.activo;
$function$;

REVOKE ALL ON FUNCTION private.precio_plan_publicidad(uuid, integer) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- B: cotizacion para el checkout
CREATE FUNCTION public.cotizar_campana(p_solicitud_id uuid)
 RETURNS TABLE(monto numeric, moneda text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_empresa uuid := private.mi_empresa_onboarding();
  v_rol text := private.mi_rol_onboarding();
  v_s public.solicitudes_campana%ROWTYPE;
  v_monto numeric; v_moneda text;
BEGIN
  IF v_empresa IS NULL OR NOT COALESCE(v_rol = ANY (ARRAY['admin','editor','finanzas','marketing','supervisor']), false) THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana s WHERE s.id = p_solicitud_id AND s.empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;
  SELECT x.monto, x.moneda INTO v_monto, v_moneda FROM private.precio_plan_publicidad(v_s.pais_id, v_s.plan_publicidad_id) x;
  IF v_monto IS NULL OR v_monto <= 0 OR v_moneda IS NULL THEN
    RAISE EXCEPTION 'El plan de la campaña no tiene precio para tu país' USING ERRCODE = 'CA010';
  END IF;
  monto := v_monto; moneda := v_moneda;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.cotizar_campana(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cotizar_campana(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- C: pago de campana por RPC
CREATE FUNCTION public.solicitar_pago_campana(p_solicitud_id uuid, p_comprobante_path text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_empresa uuid := private.mi_empresa_onboarding();
  v_rol text := private.mi_rol_onboarding();
  v_s public.solicitudes_campana%ROWTYPE;
  v_monto numeric; v_moneda text; v_pago uuid;
BEGIN
  IF v_empresa IS NULL OR NOT COALESCE(v_rol = ANY (ARRAY['admin','editor','finanzas','marketing','supervisor']), false) THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana s WHERE s.id = p_solicitud_id AND s.empresa_id = v_empresa FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;

  IF EXISTS (SELECT 1 FROM public.pagos_proveedor p WHERE p.tipo = 'campana' AND p.referencia_id = p_solicitud_id::text) THEN
    RAISE EXCEPTION 'La campaña ya tiene un pago registrado' USING ERRCODE = 'CA012';
  END IF;
  IF v_s.estado IS DISTINCT FROM 'borrador' THEN
    RAISE EXCEPTION 'La campaña no está en borrador (estado %)', v_s.estado USING ERRCODE = 'CA011';
  END IF;

  SELECT x.monto, x.moneda INTO v_monto, v_moneda FROM private.precio_plan_publicidad(v_s.pais_id, v_s.plan_publicidad_id) x;
  IF v_monto IS NULL OR v_monto <= 0 OR v_moneda IS NULL THEN
    RAISE EXCEPTION 'El plan de la campaña no tiene precio para tu país' USING ERRCODE = 'CA010';
  END IF;

  IF p_comprobante_path IS NULL OR NOT starts_with(p_comprobante_path, v_empresa::text || '/')
     OR NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'comprobantes' AND o.name = p_comprobante_path) THEN
    RAISE EXCEPTION 'Comprobante inválido: subilo de nuevo' USING ERRCODE = 'CA013';
  END IF;

  INSERT INTO public.pagos_proveedor
    (empresa_id, tipo, referencia_id, monto, moneda, metodo_pago, comprobante_url, estado, fecha_pago)
  VALUES
    (v_empresa, 'campana', p_solicitud_id::text, v_monto, v_moneda, 'transferencia', p_comprobante_path, 'pendiente', CURRENT_DATE)
  RETURNING id INTO v_pago;

  UPDATE public.solicitudes_campana SET estado = 'enviada', monto_pagado = v_monto WHERE id = p_solicitud_id;

  RETURN v_pago;
END;
$function$;

REVOKE ALL ON FUNCTION public.solicitar_pago_campana(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.solicitar_pago_campana(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text
          ||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default')||' md5='||md5(p.prosrc), ' ;; ' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('private.precio_plan_publicidad(uuid,integer)'), to_regprocedure('public.cotizar_campana(uuid)'), to_regprocedure('public.solicitar_pago_campana(uuid,text)')));
  IF v IS DISTINCT FROM 'cotizar_campana(uuid)(p_solicitud_id uuid) -> TABLE(monto numeric, moneda text) | definer=true sp=search_path="" vol=s owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=6323c55ac2d9010dfd2dad8ffc573cdf ;; private.precio_plan_publicidad(uuid,integer)(p_pais_id uuid, p_plan_id integer) -> TABLE(monto numeric, moneda text) | definer=true sp=search_path="" vol=s owner=postgres acl={postgres=X/postgres} md5=949e707c6682951dd6a09128ed59f9eb ;; solicitar_pago_campana(uuid,text)(p_solicitud_id uuid, p_comprobante_path text) -> uuid | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=49a10261bb1ad8c5ac49722afb295a15' THEN bad := bad||'funciones '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname IN ('precio_plan_publicidad','cotizar_campana','solicitar_pago_campana')) <> 3 THEN bad := bad||'sobrecargas; '; END IF;
  IF has_function_privilege('authenticated', 'private.precio_plan_publicidad(uuid,integer)', 'EXECUTE') THEN bad := bad||'authenticated ejecuta el helper; '; END IF;
  IF has_function_privilege('anon', 'public.cotizar_campana(uuid)', 'EXECUTE') OR has_function_privilege('anon', 'public.solicitar_pago_campana(uuid,text)', 'EXECUTE') THEN bad := bad||'anon ejecuta una RPC; '; END IF;
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
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG359 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
