-- ############################################################################################
-- 358 ROLLBACK - aprobar_solicitud_campana y el indice unico vuelven a como estaban antes de la 358
-- ############################################################################################
-- Restaura el cuerpo de partida de public.aprobar_solicitud_campana(uuid, text) (md5(prosrc) f5a46a02..., sacado del
-- objeto VIVO el 4-oct-2026) y su ACL, y hace DROP del indice campanas_publicitarias_solicitud_uniq.
-- El prosrc de partida tiene CRLF y el repo exige LF: el cuerpo se arma como string E'...' con \r\n explicitos, se
-- verifica su md5 ANTES de ejecutar y se aplica con EXECUTE format(... %L) (la tecnica del rollback de la 357).
-- NO SE RESTAURAN las publicaciones duplicadas 7 y 8 de la solicitud 900dc0b3-c2e7-49aa-a89f-ea8e048bfe05 que borro la
-- 358 (ni sus campana_metricas, que cayeron por CASCADE): eran datos QA del 4-jun-2026, y volver a duplicarlas no tiene
-- sentido. La publicacion 6 queda.
-- Ojo: con el indice fuera, los dos caminos de publicacion (RPC vieja y el INSERT directo del front) vuelven a poder
-- duplicar.
-- Precondicion: la 358 esta viva (md5 64b305dc..., indice presente). Probes: con este rollback aplicado, P968, P969,
-- P973 y P974 vuelven a ROJO, y P507/P509/P510 tambien (esperan CA001).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 358)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM '64b305dcaa95e8bd2a881d64afc45413' THEN bad := bad||'md5(prosrc) de la 358'||' '||COALESCE(v, '-')||'; '; END IF;
  IF to_regclass('public.campanas_publicitarias_solicitud_uniq') IS NULL THEN bad := bad||'el indice de la 358 no existe; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK358 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cuerpo de partida
DO $restaurar$
DECLARE
  v_body text := E'\r\nDECLARE v_s RECORD; v_campana_id integer;\r\nBEGIN\r\n  IF NOT private.puede_admin_pais(private.pais_de_solicitud_campana(p_solicitud_id)) THEN\r\n    RAISE EXCEPTION ''No autorizado: solo super_admin aprueba campañas'';\r\n  END IF;\r\n  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;\r\n  IF NOT FOUND THEN RAISE EXCEPTION ''Solicitud no encontrada''; END IF;\r\n  -- validación existente (que la empresa realmente opere en el país de la campaña): NO se toca.\r\n  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN\r\n    RAISE EXCEPTION ''La empresa no opera en el país de la campaña'';\r\n  END IF;\r\n\r\n  INSERT INTO public.campanas_publicitarias\r\n    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,\r\n     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id,\r\n     empresa_id, solicitud_campana_id)\r\n  VALUES\r\n    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,\r\n     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,\r\n     v_s.edad_min, v_s.edad_max, v_s.pais_id,\r\n     v_s.empresa_id, p_solicitud_id)\r\n  RETURNING id INTO v_campana_id;\r\n\r\n  UPDATE public.solicitudes_campana\r\n    SET estado = ''publicada'', notas_admin = COALESCE(p_notas_admin, notas_admin)\r\n    WHERE id = p_solicitud_id;\r\n\r\n  RETURN v_campana_id;\r\nEND;\r\n';
BEGIN
  IF md5(v_body) IS DISTINCT FROM 'f5a46a02c2f06a7f5bcea0dda47c0d2b' THEN
    RAISE EXCEPTION 'ROLLBACK358: el cuerpo armado no es el de partida (md5 %)', md5(v_body);
  END IF;
  EXECUTE format($f$CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS %L$f$, v_body);
END $restaurar$;

REVOKE ALL ON FUNCTION public.aprobar_solicitud_campana(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aprobar_solicitud_campana(uuid, text) TO authenticated, service_role;

DROP INDEX public.campanas_publicitarias_solicitud_uniq;

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM 'aprobar_solicitud_campana(uuid,text)(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text) -> integer | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion restaurada'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM 'f5a46a02c2f06a7f5bcea0dda47c0d2b' THEN bad := bad||'md5(prosrc) restaurado'||' '||COALESCE(v, '-')||'; '; END IF;
  IF to_regclass('public.campanas_publicitarias_solicitud_uniq') IS NOT NULL THEN bad := bad||'el indice sigue; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK358 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
