-- ############################################################################################
-- 351 - familia CP (compra de planes de visitador): solicitud y aprobacion por RPC
-- ############################################################################################
-- Recon del 3-oct-2026 sobre 56951e59 (solo lectura contra prod):
--   * Hoy la compra es un INSERT directo del cliente en pagos_proveedor con monto de la URL
--     (PagoCheckoutPage) y la aprobacion son 3-4 llamadas sueltas desde PagosProveedoresPage (INSERT de la
--     bolsa, UPDATE del pago, notificacion), sin transaccion: si falla el UPDATE la bolsa queda creada con el
--     pago 'pendiente'. No activa la capacidad 'visitadores'.
--   * visitas_incluidas/duracion_dias vivian solo en planes_base.atributos (global); Bronce/Plata/Oro activos
--     tienen atributos = {} -> la aprobacion creaba bolsas ILIMITADAS (cantidad NULL) de 30 dias.
--   * La policy "Proveedor crea pagos" no restringia estado/verificado_por: un proveedor podia insertar un
--     pago ya 'verificado' (autoaprobacion) de cualquier tipo.
--   * planes_visitador_contratados no tiene donde atar el pago; el cupo NO usa visitas_usadas (columna
--     muerta): private.gate_visita_pais elige UNA bolsa (activa, vigente, del pais del medico, fecha_fin mas
--     lejana) y cuenta las visitas de la empresa en el pais dentro de su ventana (private.pvc_usadas). Por
--     eso una compra con bolsa vigente en el mismo pais SUMA a esa bolsa y EXTIENDE su fecha_fin, en vez de
--     crear otra superpuesta (dos bolsas superpuestas no suman cupo).
-- Decisiones (Oscar, 3-oct-2026):
--   * visitas y duracion se definen POR PAIS en planes_configuracion; la compra rechaza una config sin ellas.
--   * compra con bolsa vigente en el mismo pais: suma visitas y extiende fecha_fin; sin bolsa: crea una.
--   * no se vende ilimitado; monto, moneda, visitas y duracion salen del catalogo en el servidor.
--   * la aprobacion es UNA RPC atomica e idempotente y activa la capacidad 'visitadores' (permanente).
-- Cambios:
--   A1 planes_configuracion + visitas_incluidas, duracion_dias (int NULL, CHECK > 0).
--   A2 pagos_proveedor + pvc_id (FK a planes_visitador_contratados, ON DELETE RESTRICT, indice simple: varios
--      pagos pueden sumar a la misma bolsa), + plan_visitas, plan_duracion_dias (snapshot del catalogo al
--      momento de la compra, CHECK > 0), + CHECK estado IN ('pendiente','verificado','rechazado') (en prod
--      solo hay 'verificado').
--   B  public.solicitar_compra_plan_visitador(p_configuracion_id uuid, p_comprobante_path text) RETURNS uuid
--   C  public.aprobar_pago_plan_visitador(p_pago_id uuid) RETURNS jsonb
--   D  "Proveedor crea pagos" (INSERT): + estado 'pendiente', sin verificacion, sin pvc_id y tipo <>
--      'plan_visitador' (cierra la autoaprobacion para todos los tipos; plan_visitador solo por RPC).
--   E  backfill de pvc_id en los 2 vinculos 1:1 medidos (bolsa creada < 0,4 s despues de fecha_verificacion,
--      misma empresa y monto): pago fdc3578f -> bolsa b15708fe, pago f07983a2 -> bolsa 2db5f85a.
-- Errcodes (familia CP, nueva; el front distingue el modulo por el prefijo):
--   solicitar: 42501 sin empresa proveedora o rol fuera de ('admin','editor') (= permiso planes.contratar)
--     CP001 configuracion inexistente, inactiva, o de un plan base inactivo / que no es de visitador
--     CP002 la configuracion es de otro pais que la empresa (o la empresa no tiene pais)
--     CP003 configuracion incompleta: sin visitas_incluidas, sin duracion_dias o sin precio_local > 0
--     CP004 el pais no tiene cuenta bancaria activa
--     CP005 la moneda de la cuenta bancaria no coincide con moneda_local de la configuracion
--     CP006 comprobante invalido: el path no empieza con '<empresa_id>/' o no existe en el bucket comprobantes
--     CP007 la empresa ya tiene un pago de plan de visitador pendiente
--   aprobar: 42501 no es super_admin
--     CP010 el pago no existe          CP011 el pago no es de tipo plan_visitador
--     CP012 el pago no esta pendiente (rechazado, o verificado sin bolsa: legacy)
--     CP013 pago sin snapshot de visitas/duracion (legacy)
--     CP014 la configuracion del pago (referencia_id) ya no existe o no tiene pais
--     CP015 la empresa no esta activa  CP016 la empresa no opera en el pais del pago
--     CP017 la bolsa vigente del pais es ilimitada (legacy): no se suma sobre ilimitado
--   CP008/CP009 y CP018+ libres.
-- Comprobante: se guarda el PATH del objeto (no una URL). PagosProveedoresPage lo abre con openSignedUrl,
-- cuyo extractPath acepta el path tal cual y tambien la URL publica de las filas viejas.
-- Pais del pago en la aprobacion = planes_configuracion.pais_id de referencia_id (la solicitud exigio que
-- fuera el pais de la empresa).
-- Huella de policies de public/private/storage d1aae5eba7362ec479a3995bf2d29827 309 -> 700082376ca04bcbb59eb743fe79c5ee 309;
-- sin "Proveedor crea pagos" a37e40f9a2899b94e4e21fa58eb1aa4f 308 antes y despues (ninguna otra cambia).
-- Probes: P937 (solicitar), P938 (aprobar), P939 (policy de INSERT).
-- Rollback: 351_rollback.sql (aborta si ya hay pagos con pvc_id fuera del backfill, pagos con snapshot o
-- configuraciones con visitas/duracion cargadas: en ese caso PARAR y decidir).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- columnas nuevas: no existen
  v := (SELECT string_agg(c.relname||'.'||a.attname, ',') FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
         WHERE c.relnamespace = 'public'::regnamespace AND NOT a.attisdropped AND a.attnum > 0
           AND ((c.relname = 'planes_configuracion' AND a.attname IN ('visitas_incluidas','duracion_dias'))
             OR (c.relname = 'pagos_proveedor' AND a.attname IN ('pvc_id','plan_visitas','plan_duracion_dias'))));
  IF v IS NOT NULL THEN bad := bad||'columnas ya existen: '||v||'; '; END IF;
  -- funciones nuevas: no existen
  v := (SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('solicitar_compra_plan_visitador','aprobar_pago_plan_visitador'));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existen: '||v||'; '; END IF;
  -- estados de pagos_proveedor dentro del CHECK nuevo
  v := (SELECT string_agg(DISTINCT estado, ',') FROM public.pagos_proveedor WHERE estado NOT IN ('pendiente','verificado','rechazado'));
  IF v IS NOT NULL THEN bad := bad||'pagos con estado fuera del CHECK: '||v||'; '; END IF;
  -- la policy de INSERT es la medida
  v := (SELECT pl.polroles::text||'|'||pl.polcmd::text||'|'||pg_get_expr(pl.polwithcheck, pl.polrelid) FROM pg_policy pl
         WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos');
  IF v IS DISTINCT FROM '{'||'authenticated'::regrole::oid||'}|a|((empresa_id = private.mi_empresa_onboarding()) AND (private.mi_rol_onboarding() = ANY (ARRAY[''admin''::text, ''editor''::text, ''finanzas''::text, ''marketing''::text, ''supervisor''::text])))' THEN
    bad := bad||'policy Proveedor crea pagos: '||COALESCE(v, 'NO EXISTE')||'; ';
  END IF;
  -- los 2 vinculos del backfill: pago y bolsa existen, misma empresa y monto, pago verificado
  v := (SELECT string_agg(x, ',') FROM (
    SELECT p.id::text||'->'||b.id::text AS x FROM public.pagos_proveedor p JOIN public.planes_visitador_contratados b ON b.empresa_id = p.empresa_id AND b.precio_pagado = p.monto
     WHERE (p.id, b.id) IN (('fdc3578f-4418-462a-85d3-f94ae525017d'::uuid, 'b15708fe-6eac-4ed9-b678-501a6baa4d5f'::uuid),
                            ('f07983a2-50ae-4158-8e21-04b6156e82e8'::uuid, '2db5f85a-a2f1-424d-b021-a0179ae2abce'::uuid))
       AND p.tipo = 'plan_visitador' AND p.estado = 'verificado' ORDER BY 1) z);
  IF v IS DISTINCT FROM 'f07983a2-50ae-4158-8e21-04b6156e82e8->2db5f85a-a2f1-424d-b021-a0179ae2abce,fdc3578f-4418-462a-85d3-f94ae525017d->b15708fe-6eac-4ed9-b678-501a6baa4d5f' THEN
    bad := bad||'vinculos del backfill: '||COALESCE(v, 'ninguno')||'; ';
  END IF;
  -- huellas de policies: todas, y todas salvo la que cambia
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'd1aae5eba7362ec479a3995bf2d29827 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND NOT (n.nspname = 'public' AND c.relname = 'pagos_proveedor' AND pl.polname = 'Proveedor crea pagos')) y);
  IF v IS DISTINCT FROM 'a37e40f9a2899b94e4e21fa58eb1aa4f 308' THEN bad := bad||'huella de policies sin Proveedor crea pagos '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones, grants por columna y pg_default_acl (no cambian)
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
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG351 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A. esquema
ALTER TABLE public.planes_configuracion
  ADD COLUMN visitas_incluidas integer CONSTRAINT planes_configuracion_visitas_incluidas_check CHECK (visitas_incluidas > 0),
  ADD COLUMN duracion_dias integer CONSTRAINT planes_configuracion_duracion_dias_check CHECK (duracion_dias > 0);

ALTER TABLE public.pagos_proveedor
  ADD COLUMN pvc_id uuid CONSTRAINT pagos_proveedor_pvc_id_fkey REFERENCES public.planes_visitador_contratados(id) ON DELETE RESTRICT,
  ADD COLUMN plan_visitas integer CONSTRAINT pagos_proveedor_plan_visitas_check CHECK (plan_visitas > 0),
  ADD COLUMN plan_duracion_dias integer CONSTRAINT pagos_proveedor_plan_duracion_dias_check CHECK (plan_duracion_dias > 0),
  ADD CONSTRAINT pagos_proveedor_estado_check CHECK (estado IN ('pendiente','verificado','rechazado'));

CREATE INDEX idx_pagos_prov_pvc ON public.pagos_proveedor (pvc_id);

-- ---------------------------------------------------------------------------- B. solicitud (proveedor)
CREATE FUNCTION public.solicitar_compra_plan_visitador(p_configuracion_id uuid, p_comprobante_path text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_empresa uuid; v_rol text; v_pais_emp uuid; v_cfg record; v_moneda_cta text; v_pago uuid;
BEGIN
  v_empresa := private.mi_empresa_onboarding();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres una cuenta proveedora activa' USING ERRCODE = '42501';
  END IF;
  v_rol := private.mi_rol_onboarding();
  IF v_rol IS NULL OR v_rol NOT IN ('admin','editor') THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede contratar planes' USING ERRCODE = '42501';
  END IF;

  -- serializa las solicitudes de la misma empresa (el chequeo de pendiente de abajo no es TOCTOU)
  SELECT e.pais_id INTO v_pais_emp FROM public.empresas_proveedoras e WHERE e.id = v_empresa FOR UPDATE;

  SELECT pc.pais_id, pc.precio_local, pc.moneda_local::text AS moneda_local, pc.visitas_incluidas, pc.duracion_dias,
         pc.activo, pb.activo AS pb_activo, pb.tipo::text AS pb_tipo
    INTO v_cfg
    FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
   WHERE pc.id = p_configuracion_id;
  IF NOT FOUND OR v_cfg.activo IS NOT TRUE OR v_cfg.pb_activo IS NOT TRUE OR v_cfg.pb_tipo IS DISTINCT FROM 'visitador' THEN
    RAISE EXCEPTION 'El plan elegido no esta disponible' USING ERRCODE = 'CP001';
  END IF;
  IF v_pais_emp IS NULL OR v_cfg.pais_id IS DISTINCT FROM v_pais_emp THEN
    RAISE EXCEPTION 'El plan elegido no corresponde al pais de tu empresa' USING ERRCODE = 'CP002';
  END IF;
  IF v_cfg.visitas_incluidas IS NULL OR v_cfg.duracion_dias IS NULL OR v_cfg.precio_local IS NULL OR v_cfg.precio_local <= 0 THEN
    RAISE EXCEPTION 'El plan elegido no tiene visitas, duracion o precio configurados' USING ERRCODE = 'CP003';
  END IF;

  -- misma cuenta que muestra el checkout (useCuentaBancariaCheckout: la primera activa del pais)
  SELECT cb.moneda INTO v_moneda_cta FROM public.cuentas_bancarias_pais cb
   WHERE cb.pais_id = v_cfg.pais_id AND cb.activo ORDER BY cb.created_at LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay cuenta bancaria activa para tu pais' USING ERRCODE = 'CP004';
  END IF;
  IF v_moneda_cta IS NULL OR v_cfg.moneda_local IS NULL OR v_moneda_cta <> v_cfg.moneda_local THEN
    RAISE EXCEPTION 'La moneda del plan (%) no coincide con la de la cuenta bancaria (%)', v_cfg.moneda_local, v_moneda_cta
      USING ERRCODE = 'CP005';
  END IF;

  IF p_comprobante_path IS NULL OR NOT starts_with(p_comprobante_path, v_empresa::text || '/')
     OR NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'comprobantes' AND o.name = p_comprobante_path) THEN
    RAISE EXCEPTION 'Comprobante invalido: subilo de nuevo' USING ERRCODE = 'CP006';
  END IF;

  IF EXISTS (SELECT 1 FROM public.pagos_proveedor p
              WHERE p.empresa_id = v_empresa AND p.tipo = 'plan_visitador' AND p.estado = 'pendiente') THEN
    RAISE EXCEPTION 'Ya tienes una compra de plan pendiente de verificacion' USING ERRCODE = 'CP007';
  END IF;

  INSERT INTO public.pagos_proveedor
    (empresa_id, tipo, referencia_id, monto, moneda, metodo_pago, comprobante_url, estado, fecha_pago,
     plan_visitas, plan_duracion_dias)
  VALUES
    (v_empresa, 'plan_visitador', p_configuracion_id::text, v_cfg.precio_local, v_cfg.moneda_local, 'transferencia',
     p_comprobante_path, 'pendiente', CURRENT_DATE, v_cfg.visitas_incluidas, v_cfg.duracion_dias)
  RETURNING id INTO v_pago;

  RETURN v_pago;
END;
$fn$;

REVOKE ALL ON FUNCTION public.solicitar_compra_plan_visitador(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.solicitar_compra_plan_visitador(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- C. aprobacion (super_admin)
CREATE FUNCTION public.aprobar_pago_plan_visitador(p_pago_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_p record; v_pais uuid; v_estado_emp text; v_pvc record;
  v_pvc_id uuid; v_incl integer; v_fin date; v_accion text;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT p.id, p.empresa_id, p.tipo, p.estado, p.referencia_id, p.monto, p.pvc_id, p.plan_visitas, p.plan_duracion_dias
    INTO v_p FROM public.pagos_proveedor p WHERE p.id = p_pago_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El pago no existe' USING ERRCODE = 'CP010';
  END IF;
  IF v_p.tipo IS DISTINCT FROM 'plan_visitador' THEN
    RAISE EXCEPTION 'El pago no es de un plan de visitador' USING ERRCODE = 'CP011';
  END IF;
  -- idempotencia: ya aprobado por esta RPC -> no escribe nada
  IF v_p.estado = 'verificado' AND v_p.pvc_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotente', true, 'pvc_id', v_p.pvc_id);
  END IF;
  IF v_p.estado IS DISTINCT FROM 'pendiente' THEN
    RAISE EXCEPTION 'El pago no esta pendiente (estado=%)', v_p.estado USING ERRCODE = 'CP012';
  END IF;
  IF v_p.plan_visitas IS NULL OR v_p.plan_duracion_dias IS NULL THEN
    RAISE EXCEPTION 'Pago sin visitas/duracion registradas (anterior a la compra por RPC): aprobalo a mano' USING ERRCODE = 'CP013';
  END IF;

  SELECT pc.pais_id INTO v_pais FROM public.planes_configuracion pc WHERE pc.id::text = v_p.referencia_id;
  IF v_pais IS NULL THEN
    RAISE EXCEPTION 'La configuracion del plan del pago ya no existe' USING ERRCODE = 'CP014';
  END IF;

  -- serializa las compras/aprobaciones de la misma empresa
  SELECT e.estado INTO v_estado_emp FROM public.empresas_proveedoras e WHERE e.id = v_p.empresa_id FOR UPDATE;
  IF v_estado_emp IS DISTINCT FROM 'activa' THEN
    RAISE EXCEPTION 'La empresa no esta activa (estado=%)', v_estado_emp USING ERRCODE = 'CP015';
  END IF;
  IF NOT COALESCE(private.empresa_opera_en_pais(v_p.empresa_id, v_pais), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el pais del plan' USING ERRCODE = 'CP016';
  END IF;

  -- bolsa vigente: mismo criterio que private.gate_visita_pais
  SELECT b.id, b.cantidad_visitas_incluidas INTO v_pvc
    FROM public.planes_visitador_contratados b
   WHERE b.empresa_id = v_p.empresa_id AND b.pais_id = v_pais AND b.estado = 'activo'
     AND CURRENT_DATE BETWEEN b.fecha_inicio AND b.fecha_fin
   ORDER BY b.fecha_fin DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND THEN
    IF v_pvc.cantidad_visitas_incluidas IS NULL THEN
      RAISE EXCEPTION 'La bolsa vigente del pais es ilimitada: no se puede sumar una compra' USING ERRCODE = 'CP017';
    END IF;
    UPDATE public.planes_visitador_contratados b
       SET cantidad_visitas_incluidas = b.cantidad_visitas_incluidas + v_p.plan_visitas,
           fecha_fin = b.fecha_fin + v_p.plan_duracion_dias,
           precio_pagado = b.precio_pagado + v_p.monto,
           updated_at = now()
     WHERE b.id = v_pvc.id
    RETURNING b.id, b.cantidad_visitas_incluidas, b.fecha_fin INTO v_pvc_id, v_incl, v_fin;
    v_accion := 'sumada';
  ELSE
    INSERT INTO public.planes_visitador_contratados
      (empresa_id, plan_visitador_id, pais_id, cantidad_visitas_incluidas, visitas_usadas, precio_pagado,
       fecha_inicio, fecha_fin, estado, origen)
    VALUES
      (v_p.empresa_id, 1, v_pais, v_p.plan_visitas, 0, v_p.monto,
       CURRENT_DATE, CURRENT_DATE + v_p.plan_duracion_dias - 1, 'activo', 'comprado')
    RETURNING id, cantidad_visitas_incluidas, fecha_fin INTO v_pvc_id, v_incl, v_fin;
    v_accion := 'creada';
  END IF;

  -- capacidad 'visitadores' = acceso permanente (mismo upsert que activar_modulo_visitadores; no pisa origen)
  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  VALUES (v_p.empresa_id, 'visitadores', true, 'suelta', NULL, now(), NULL, auth.uid())
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = NULL, activada_por = auth.uid();

  UPDATE public.pagos_proveedor
     SET estado = 'verificado', verificado_por = auth.uid(), fecha_verificacion = now(), pvc_id = v_pvc_id, updated_at = now()
   WHERE id = v_p.id;

  PERFORM public.notificar_pago_resultado(v_p.id);

  RETURN jsonb_build_object('ok', true, 'pvc_id', v_pvc_id, 'accion', v_accion,
                            'cantidad_visitas_incluidas', v_incl, 'fecha_fin', v_fin);
END;
$fn$;

REVOKE ALL ON FUNCTION public.aprobar_pago_plan_visitador(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aprobar_pago_plan_visitador(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- D. policy de INSERT
ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor TO authenticated
  WITH CHECK ((empresa_id = private.mi_empresa_onboarding())
    AND (private.mi_rol_onboarding() = ANY (ARRAY['admin','editor','finanzas','marketing','supervisor']))
    AND estado = 'pendiente' AND verificado_por IS NULL AND fecha_verificacion IS NULL AND pvc_id IS NULL
    AND tipo <> 'plan_visitador');

-- ---------------------------------------------------------------------------- E. backfill (2 vinculos 1:1)
UPDATE public.pagos_proveedor SET pvc_id = 'b15708fe-6eac-4ed9-b678-501a6baa4d5f'
 WHERE id = 'fdc3578f-4418-462a-85d3-f94ae525017d' AND pvc_id IS NULL;
UPDATE public.pagos_proveedor SET pvc_id = '2db5f85a-a2f1-424d-b021-a0179ae2abce'
 WHERE id = 'f07983a2-50ae-4158-8e21-04b6156e82e8' AND pvc_id IS NULL;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- columnas: tipo y nullability
  v := (SELECT string_agg(c.relname||'.'||a.attname||':'||format_type(a.atttypid, a.atttypmod)||':'||a.attnotnull::text, ',' ORDER BY c.relname, a.attname)
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
         WHERE c.relnamespace = 'public'::regnamespace AND NOT a.attisdropped AND a.attnum > 0
           AND ((c.relname = 'planes_configuracion' AND a.attname IN ('visitas_incluidas','duracion_dias'))
             OR (c.relname = 'pagos_proveedor' AND a.attname IN ('pvc_id','plan_visitas','plan_duracion_dias'))));
  IF v IS DISTINCT FROM 'pagos_proveedor.plan_duracion_dias:integer:false,pagos_proveedor.plan_visitas:integer:false,pagos_proveedor.pvc_id:uuid:false,planes_configuracion.duracion_dias:integer:false,planes_configuracion.visitas_incluidas:integer:false' THEN
    bad := bad||'columnas '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  -- constraints nuevos e indice
  v := (SELECT string_agg(conname||'='||pg_get_constraintdef(oid), ' ; ' ORDER BY conname) FROM pg_constraint
         WHERE conname IN ('planes_configuracion_visitas_incluidas_check','planes_configuracion_duracion_dias_check',
                           'pagos_proveedor_pvc_id_fkey','pagos_proveedor_plan_visitas_check','pagos_proveedor_plan_duracion_dias_check',
                           'pagos_proveedor_estado_check')
           AND connamespace = 'public'::regnamespace);
  IF v IS DISTINCT FROM 'pagos_proveedor_estado_check=CHECK ((estado = ANY (ARRAY[''pendiente''::text, ''verificado''::text, ''rechazado''::text]))) ; pagos_proveedor_plan_duracion_dias_check=CHECK ((plan_duracion_dias > 0)) ; pagos_proveedor_plan_visitas_check=CHECK ((plan_visitas > 0)) ; pagos_proveedor_pvc_id_fkey=FOREIGN KEY (pvc_id) REFERENCES planes_visitador_contratados(id) ON DELETE RESTRICT ; planes_configuracion_duracion_dias_check=CHECK ((duracion_dias > 0)) ; planes_configuracion_visitas_incluidas_check=CHECK ((visitas_incluidas > 0))' THEN
    bad := bad||'constraints '||COALESCE(v, 'ninguno')||'; ';
  END IF;
  v := (SELECT pg_get_indexdef(i.indexrelid) FROM pg_index i WHERE i.indexrelid = 'public.idx_pagos_prov_pvc'::regclass);
  IF v IS DISTINCT FROM 'CREATE INDEX idx_pagos_prov_pvc ON public.pagos_proveedor USING btree (pvc_id)' THEN bad := bad||'indice '||COALESCE(v, '-')||'; '; END IF;
  -- las 2 RPCs: DEFINER, search_path='', EXECUTE solo postgres/authenticated/service_role
  v := (SELECT string_agg(p.proname||':'||p.prosecdef::text||':'||COALESCE(array_to_string(p.proconfig, ','), '-')||':'||
           (SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'='||a.privilege_type, '+'
                               ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END)
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a), ',' ORDER BY p.proname)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('solicitar_compra_plan_visitador','aprobar_pago_plan_visitador'));
  IF v IS DISTINCT FROM 'aprobar_pago_plan_visitador:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,solicitar_compra_plan_visitador:true:search_path="":authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE' THEN
    bad := bad||'RPCs '||COALESCE(v, 'no existen')||'; ';
  END IF;
  -- policy de INSERT: roles {authenticated}, cmd INSERT, WITH CHECK nuevo
  v := (SELECT pl.polroles::text||'|'||pl.polcmd::text||'|'||md5(pg_get_expr(pl.polwithcheck, pl.polrelid)) FROM pg_policy pl
         WHERE pl.polrelid = 'public.pagos_proveedor'::regclass AND pl.polname = 'Proveedor crea pagos');
  IF v IS DISTINCT FROM '{'||'authenticated'::regrole::oid||'}|a|3badf42f9babd6faa27eccfd3043a955' THEN bad := bad||'policy Proveedor crea pagos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  -- backfill: exactamente los 2 vinculos
  v := (SELECT string_agg(id::text||'->'||pvc_id::text, ',' ORDER BY id) FROM public.pagos_proveedor WHERE pvc_id IS NOT NULL);
  IF v IS DISTINCT FROM 'f07983a2-50ae-4158-8e21-04b6156e82e8->2db5f85a-a2f1-424d-b021-a0179ae2abce,fdc3578f-4418-462a-85d3-f94ae525017d->b15708fe-6eac-4ed9-b678-501a6baa4d5f' THEN
    bad := bad||'backfill '||COALESCE(v, 'ninguno')||'; ';
  END IF;
  -- huellas de policies: ninguna otra cambio; la total nueva
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND NOT (n.nspname = 'public' AND c.relname = 'pagos_proveedor' AND pl.polname = 'Proveedor crea pagos')) y);
  IF v IS DISTINCT FROM 'a37e40f9a2899b94e4e21fa58eb1aa4f 308' THEN bad := bad||'huella de policies sin Proveedor crea pagos '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones, grants por columna y pg_default_acl sin cambio; ACL de funciones con las 2 nuevas
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG351 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
