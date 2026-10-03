-- ############################################################################################
-- 352 ROLLBACK - borra las 3 configuraciones de visitador de GT creadas por la 352
-- ############################################################################################
-- Borra EXACTAMENTE estas 3 por UUID. Aborta si algun pago las referencia (pagos_proveedor.referencia_id): en ese caso
-- ya hubo compras sobre el catalogo y hay que decidir que hacer con ellas antes de borrar nada.
--   80f3c3e0-3ab5-412e-8a39-4c45cf6b816f  Plan Bronce GT
--   a383402a-280e-41f2-aea8-c40ce399df8b  Plan Plata GT
--   19a760ae-1e22-437a-8661-4dba9e0877a3  Plan Oro GT
-- Autochequeo: planes_configuracion vuelve a 6f9a39e2d49a4110fd0a3f10d1510bbe 110 y las de visitador de GT a
-- b12841237138f233809d3311e59c0bd1 7 (si nadie edito otra configuracion entre la 352 y el rollback).
-- ############################################################################################

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT count(*)::text FROM public.planes_configuracion
         WHERE id IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3'));
  IF v IS DISTINCT FROM '3' THEN bad := bad||'configuraciones de la 352 presentes: '||COALESCE(v, '-')||' de 3; '; END IF;
  v := (SELECT string_agg(p.id::text||'('||p.estado||')', ',') FROM public.pagos_proveedor p
         WHERE p.referencia_id IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3'));
  IF v IS NOT NULL THEN bad := bad||'pagos que referencian las configuraciones: '||v||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK352 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

DELETE FROM public.planes_configuracion
 WHERE id IN ('80f3c3e0-3ab5-412e-8a39-4c45cf6b816f','a383402a-280e-41f2-aea8-c40ce399df8b','19a760ae-1e22-437a-8661-4dba9e0877a3');

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(string_agg(to_jsonb(pc)::text, '|' ORDER BY pc.id))||' '||count(*) FROM public.planes_configuracion pc);
  IF v IS DISTINCT FROM '6f9a39e2d49a4110fd0a3f10d1510bbe 110' THEN bad := bad||'planes_configuracion '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(to_jsonb(pc)::text, '|' ORDER BY pc.id))||' '||count(*) FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id
         WHERE pc.pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' AND pb.tipo::text = 'visitador');
  IF v IS DISTINCT FROM 'b12841237138f233809d3311e59c0bd1 7' THEN bad := bad||'configuraciones de visitador de GT '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK352 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
