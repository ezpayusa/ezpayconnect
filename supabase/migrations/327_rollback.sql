-- ROLLBACK mig 327 - restaura registrar_proveedor al estado previo (fase 1, 24-sep-2026):
-- cuerpo con md5(prosrc)=5272e04eb94a7fe8c861b989cf5003ca, search_path=public, EXECUTE a PUBLIC, anon,
-- authenticated y service_role.
-- El prosrc vivo previo tiene fines de linea CRLF y este archivo es LF (.gitattributes: eol=lf):
-- el cuerpo se normaliza a CRLF antes de crearlo para que el md5 coincida exacto.
DO $rb$
DECLARE v_body text := $body$
DECLARE
  v_user_id UUID := auth.uid();
  v_empresa_id UUID;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Usuario no autenticado'; END IF;

  INSERT INTO empresas_proveedoras (
    nombre_empresa, tipo, ruc_nit, pais_id, ciudad, direccion, email_contacto, telefono, estado
  ) VALUES (
    p_nombre_empresa, p_tipo, p_ruc_nit, p_pais_id, p_ciudad, p_direccion, p_email_contacto, p_telefono, 'pendiente'
  ) RETURNING id INTO v_empresa_id;

  INSERT INTO cuentas_proveedor (id, empresa_id, nombre_completo, email, rol_en_empresa, activo)
  VALUES (v_user_id, v_empresa_id, p_nombre_completo, p_email, 'admin', true);

  RETURN v_empresa_id;
END;
$body$;
BEGIN
  v_body := replace(replace(v_body, E'\r\n', E'\n'), E'\n', E'\r\n');
  EXECUTE 'CREATE OR REPLACE FUNCTION public.registrar_proveedor(p_nombre_empresa text, p_tipo text, p_ruc_nit text, '
       || 'p_pais_id uuid, p_ciudad text, p_direccion text, p_email_contacto text, p_telefono text, '
       || 'p_nombre_completo text, p_email text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER '
       || 'SET search_path TO ''public'' AS ' || quote_literal(v_body);
END $rb$;

GRANT EXECUTE ON FUNCTION public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text) TO PUBLIC, anon, authenticated, service_role;

-- Autochequeo: md5 del cuerpo, config y ACL exactos del estado previo.
DO $ck$
DECLARE v text := ''; r record;
BEGIN
  SELECT md5(p.prosrc) AS m, p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.proconfig,
         ARRAY(SELECT a::text FROM unnest(p.proacl) a ORDER BY 1) AS acl
    INTO r FROM pg_proc p
   WHERE p.oid = 'public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'::regprocedure;
  IF r.m <> '5272e04eb94a7fe8c861b989cf5003ca' THEN v := v||' md5='||r.m; END IF;
  IF NOT r.prosecdef OR r.owner <> 'postgres' THEN v := v||' secdef/owner'; END IF;
  IF r.proconfig IS DISTINCT FROM ARRAY['search_path=public'] THEN v := v||' proconfig='||COALESCE(r.proconfig::text,'NULL'); END IF;
  IF r.acl IS DISTINCT FROM ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres'] THEN
    v := v||' proacl='||r.acl::text; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK327: no coincide con el estado previo:%', v; END IF;
END $ck$;
