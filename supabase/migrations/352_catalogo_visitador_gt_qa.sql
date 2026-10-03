-- ############################################################################################
-- 352 - familia CP: catalogo de planes de visitador de Guatemala (QA)
-- ############################################################################################
-- Desde la 351 la compra de un plan de visitador sale del catalogo POR PAIS (planes_configuracion) y la RPC
-- solicitar_compra_plan_visitador rechaza (CP003) una configuracion sin visitas_incluidas/duracion_dias. Hoy GT no
-- tiene ninguna configuracion de visitador activa: las 7 que hay (Plan Plus x2, Plan Visitador Basico, Visitador
-- Basico, Visitador Medico x3) estan inactivas y no se tocan; los planes_base tampoco.
-- Se crean 3 configuraciones activas en GT (configuracion_pais cbbbbe6d-...), una por plan base activo de visitador,
-- en GTQ (la moneda de la cuenta bancaria activa de GT, fb0b94b0-..., que es la que usa el checkout), mensuales,
-- sin precio anual, comision 0 y descuento 0:
--   config 80f3c3e0-3ab5-412e-8a39-4c45cf6b816f  Plan Bronce (plan_base d1a9917e-...)  250 GTQ   20 visitas  30 dias
--   config a383402a-280e-41f2-aea8-c40ce399df8b  Plan Plata  (plan_base 838d9e7d-...)  450 GTQ   50 visitas  30 dias
--   config 19a760ae-1e22-437a-8661-4dba9e0877a3  Plan Oro    (plan_base 0af89fd9-...)  900 GTQ  120 visitas  30 dias
-- Es un cambio de DATOS: no toca esquema, policies, privilegios ni funciones.
-- Huellas fijadas: policies de public/private/storage 700082376ca04bcbb59eb743fe79c5ee 309 (la de la 351, sin cambio);
-- las 7 configuraciones de visitador de GT b12841237138f233809d3311e59c0bd1 7 (sin cambio); planes_base
-- 254518e1163774a236d4e43bc305378e 32 (sin cambio); planes_configuracion 110 -> 113 filas.
-- Rollback: 352_rollback.sql (borra exactamente estas 3; aborta si algun pago las referencia).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
-- Una segunda pasada aborta aca: las 3 configuraciones ya existen.
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- las 3 configuraciones nuevas no existen
  v := (SELECT string_agg(id::text, ',') FROM public.planes_configuracion
         WHERE id IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3'));
  IF v IS NOT NULL THEN bad := bad||'configuraciones ya existen: '||v||'; '; END IF;
  -- el pais y los 3 planes base activos de visitador
  v := (SELECT codigo||'|'||moneda||'|'||activo::text FROM public.configuracion_pais WHERE id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909');
  IF v IS DISTINCT FROM 'GT|GTQ|true' THEN bad := bad||'pais GT '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT string_agg(id::text||'|'||nombre||'|'||tipo::text||'|'||activo::text, ',' ORDER BY nombre) FROM public.planes_base
         WHERE id IN ('d1a9917e-31d5-4002-959e-5c0d3d12b5cd','838d9e7d-9fbd-49a6-a2ae-5bf3431efb4b','0af89fd9-ee3d-411d-84f6-dcd716ba1bac'));
  IF v IS DISTINCT FROM 'd1a9917e-31d5-4002-959e-5c0d3d12b5cd|Plan Bronce|visitador|true,0af89fd9-ee3d-411d-84f6-dcd716ba1bac|Plan Oro|visitador|true,838d9e7d-9fbd-49a6-a2ae-5bf3431efb4b|Plan Plata|visitador|true' THEN
    bad := bad||'planes base '||COALESCE(v, 'NO EXISTEN')||'; ';
  END IF;
  -- ninguna configuracion de visitador activa en GT (en particular, de esos 3 planes base)
  v := (SELECT string_agg(pc.id::text, ',') FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
         WHERE pc.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND pb.tipo::text = 'visitador' AND pc.activo);
  IF v IS NOT NULL THEN bad := bad||'configuraciones de visitador activas en GT: '||v||'; '; END IF;
  -- las 7 configuraciones de visitador de GT (inactivas) tal como se midieron
  v := (SELECT md5(string_agg(to_jsonb(pc)::text, '|' ORDER BY pc.id))||' '||count(*) FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
         WHERE pc.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND pb.tipo::text = 'visitador');
  IF v IS DISTINCT FROM 'b12841237138f233809d3311e59c0bd1 7' THEN bad := bad||'configuraciones de visitador de GT '||COALESCE(v, '-')||'; '; END IF;
  -- la cuenta bancaria del checkout de GT (la primera activa por created_at) es fb0b94b0 y esta en GTQ
  v := (SELECT cb.id::text||'|'||cb.moneda||'|'||cb.activo::text FROM public.cuentas_bancarias_pais cb
         WHERE cb.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND cb.activo ORDER BY cb.created_at LIMIT 1);
  IF v IS DISTINCT FROM 'fb0b94b0-1162-4d98-ae8a-18e6775f1b0c|GTQ|true' THEN bad := bad||'cuenta bancaria de GT '||COALESCE(v, 'ninguna activa')||'; '; END IF;
  -- planes_base completo, planes_configuracion completo y huella de policies (la de la 351)
  v := (SELECT md5(string_agg(to_jsonb(pb)::text, '|' ORDER BY pb.id))||' '||count(*) FROM public.planes_base pb);
  IF v IS DISTINCT FROM '254518e1163774a236d4e43bc305378e 32' THEN bad := bad||'planes_base '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(to_jsonb(pc)::text, '|' ORDER BY pc.id))||' '||count(*) FROM public.planes_configuracion pc);
  IF v IS DISTINCT FROM '6f9a39e2d49a4110fd0a3f10d1510bbe 110' THEN bad := bad||'planes_configuracion '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG352 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- las 3 configuraciones de GT
INSERT INTO public.planes_configuracion
  (id, pais_id, plan_base_id, precio_local, moneda_local, precio_anual, comision_aplicada, descuento_porcentaje, activo,
   visitas_incluidas, duracion_dias)
VALUES
  ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f', 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', 'd1a9917e-31d5-4002-959e-5c0d3d12b5cd',
   250, 'GTQ', NULL, 0, 0, true, 20, 30),
  ('a383402a-280e-41f2-aea8-c40ce399df8b', 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', '838d9e7d-9fbd-49a6-a2ae-5bf3431efb4b',
   450, 'GTQ', NULL, 0, 0, true, 50, 30),
  ('19a760ae-1e22-437a-8661-4dba9e0877a3', 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', '0af89fd9-ee3d-411d-84f6-dcd716ba1bac',
   900, 'GTQ', NULL, 0, 0, true, 120, 30);

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- las 3 filas con sus valores exactos
  v := (SELECT string_agg(pc.id::text||'|'||pc.pais_id::text||'|'||pc.plan_base_id::text||'|'||pc.precio_local::text||'|'||pc.moneda_local::text||'|'||
                          COALESCE(pc.precio_anual::text, 'NULL')||'|'||pc.comision_aplicada::text||'|'||pc.descuento_porcentaje::text||'|'||pc.activo::text||'|'||
                          pc.visitas_incluidas::text||'|'||pc.duracion_dias::text, ',' ORDER BY pc.precio_local)
          FROM public.planes_configuracion pc
         WHERE pc.id IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3'));
  IF v IS DISTINCT FROM
     '80f3c3e0-3ab5-412e-8a39-4c45cf6b816f|cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909|d1a9917e-31d5-4002-959e-5c0d3d12b5cd|250.00|GTQ|NULL|0.00|0.00|true|20|30,'
   ||'a383402a-280e-41f2-aea8-c40ce399df8b|cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909|838d9e7d-9fbd-49a6-a2ae-5bf3431efb4b|450.00|GTQ|NULL|0.00|0.00|true|50|30,'
   ||'19a760ae-1e22-437a-8661-4dba9e0877a3|cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909|0af89fd9-ee3d-411d-84f6-dcd716ba1bac|900.00|GTQ|NULL|0.00|0.00|true|120|30' THEN
    bad := bad||'las 3 configuraciones: '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  -- son las UNICAS configuraciones de visitador activas en GT
  v := (SELECT string_agg(pc.id::text, ',' ORDER BY pc.id) FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
         WHERE pc.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND pb.tipo::text = 'visitador' AND pc.activo);
  IF v IS DISTINCT FROM '19a760ae-1e22-437a-8661-4dba9e0877a3,80f3c3e0-3ab5-412e-8a39-4c45cf6b816f,a383402a-280e-41f2-aea8-c40ce399df8b' THEN
    bad := bad||'configuraciones de visitador activas en GT: '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  -- las 7 de antes, intactas; planes_base intacto; 113 configuraciones en total
  v := (SELECT md5(string_agg(to_jsonb(pc)::text, '|' ORDER BY pc.id))||' '||count(*) FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
         WHERE pc.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND pb.tipo::text = 'visitador'
           AND pc.id NOT IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3'));
  IF v IS DISTINCT FROM 'b12841237138f233809d3311e59c0bd1 7' THEN bad := bad||'configuraciones de visitador de GT previas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(to_jsonb(pb)::text, '|' ORDER BY pb.id))||' '||count(*) FROM public.planes_base pb);
  IF v IS DISTINCT FROM '254518e1163774a236d4e43bc305378e 32' THEN bad := bad||'planes_base '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT count(*)::text FROM public.planes_configuracion);
  IF v IS DISTINCT FROM '113' THEN bad := bad||'planes_configuracion filas '||COALESCE(v, '-')||'; '; END IF;
  -- la huella de policies no cambia
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG352 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
