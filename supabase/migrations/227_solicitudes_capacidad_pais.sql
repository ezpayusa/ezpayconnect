-- ============================================================================
-- Migración 227 (Front B admin_pais): flujo de SOLICITUD/APROBACIÓN de capacidades/tiers por país +
--   lectura de lo ya creado + techo de cortesía por RPC. Mismo patrón que solicitudes_campana.
-- ============================================================================
-- Hoy crear_capacidad_pais/crear_tier_pais (mig 218) ejecutan DIRECTO (admin_pais crea sin aprobación).
-- Nuevo modelo: admin_pais (o super_admin) SOLICITA; super_admin RESUELVE (aprueba, opcionalmente
-- editando los campos, o rechaza). La aprobación reusa crear_*_pais (que revalida y maneja duplicado/
-- cross-país devolviendo {error} jsonb — si eso pasa, la solicitud queda PENDIENTE, no se marca aprobada).
-- Todo por RPC DEFINER; la tabla es deny-all (RLS sin policy + REVOKE authenticated).
-- ERRCODE PC019 para autz (PC014-018 ya usados). Errores de negocio → {error} jsonb.
-- ============================================================================

BEGIN;

-- ========================= TABLA =========================
CREATE TABLE IF NOT EXISTS public.solicitudes_capacidad_pais (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo           text NOT NULL CHECK (tipo IN ('capacidad','tier')),
  pais_id        uuid NOT NULL REFERENCES public.configuracion_pais(id),
  solicitado_por uuid NOT NULL REFERENCES public.perfiles(id),
  codigo         text NOT NULL,
  nombre         text NOT NULL,
  descripcion    text,
  orden          integer NOT NULL DEFAULT 100,
  capacidades    text[],                    -- solo tier: códigos de capacidades a incluir
  estado         text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobada','rechazada')),
  nota_revision  text,
  resuelto_por   uuid REFERENCES public.perfiles(id),
  resuelto_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_solic_cap_pais_pais_estado ON public.solicitudes_capacidad_pais (pais_id, estado);

-- deny-all: RLS ENABLE sin policy + REVOKE (default privileges dan ALL a authenticated → revocar).
ALTER TABLE public.solicitudes_capacidad_pais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.solicitudes_capacidad_pais FROM PUBLIC, anon, authenticated;
GRANT  SELECT, INSERT, UPDATE ON public.solicitudes_capacidad_pais TO service_role;

-- ========================= 1) solicitar_capacidad_pais =========================
CREATE OR REPLACE FUNCTION public.solicitar_capacidad_pais(
  p_pais_id uuid, p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL, p_orden integer DEFAULT 100)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT ( private.tiene_rol(ARRAY['super_admin'])
        OR (get_auth_user_rol()='admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()) ) THEN
    RAISE EXCEPTION 'No autorizado para solicitar capacidades de este país' USING ERRCODE='PC019';
  END IF;
  IF p_codigo IS NULL OR p_nombre IS NULL THEN RAISE EXCEPTION 'codigo y nombre son obligatorios'; END IF;
  INSERT INTO solicitudes_capacidad_pais (tipo, pais_id, solicitado_por, codigo, nombre, descripcion, orden)
  VALUES ('capacidad', p_pais_id, auth.uid(), p_codigo, p_nombre, p_descripcion, COALESCE(p_orden,100))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ========================= 2) solicitar_tier_pais =========================
CREATE OR REPLACE FUNCTION public.solicitar_tier_pais(
  p_pais_id uuid, p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL, p_orden integer DEFAULT 100,
  p_capacidades text[] DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT ( private.tiene_rol(ARRAY['super_admin'])
        OR (get_auth_user_rol()='admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()) ) THEN
    RAISE EXCEPTION 'No autorizado para solicitar tiers de este país' USING ERRCODE='PC019';
  END IF;
  IF p_codigo IS NULL OR p_nombre IS NULL THEN RAISE EXCEPTION 'codigo y nombre son obligatorios'; END IF;
  INSERT INTO solicitudes_capacidad_pais (tipo, pais_id, solicitado_por, codigo, nombre, descripcion, orden, capacidades)
  VALUES ('tier', p_pais_id, auth.uid(), p_codigo, p_nombre, p_descripcion, COALESCE(p_orden,100), p_capacidades)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ========================= 3) resolver_solicitud_capacidad_pais (super_admin EXCLUSIVO) =========================
CREATE OR REPLACE FUNCTION public.resolver_solicitud_capacidad_pais(
  p_solicitud_id uuid, p_aprobar boolean, p_campos_editados jsonb DEFAULT NULL, p_nota text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_s RECORD; v_codigo text; v_nombre text; v_desc text; v_orden int; v_caps text[]; v_res jsonb;
BEGIN
  IF NOT private.tiene_rol(ARRAY['super_admin']) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin resuelve solicitudes' USING ERRCODE='PC019';
  END IF;
  SELECT * INTO v_s FROM solicitudes_capacidad_pais WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Solicitud no encontrada'); END IF;
  IF v_s.estado <> 'pendiente' THEN RETURN jsonb_build_object('error','La solicitud ya fue resuelta ('||v_s.estado||')'); END IF;

  -- RECHAZO: no crea nada.
  IF NOT p_aprobar THEN
    UPDATE solicitudes_capacidad_pais
      SET estado='rechazada', nota_revision=p_nota, resuelto_por=auth.uid(), resuelto_at=now(), updated_at=now()
      WHERE id=p_solicitud_id;
    RETURN jsonb_build_object('success', true, 'estado','rechazada');
  END IF;

  -- APROBACIÓN: campos efectivos = los de la solicitud, sobrescritos por p_campos_editados (keys presentes).
  v_codigo := COALESCE(p_campos_editados->>'codigo', v_s.codigo);
  v_nombre := COALESCE(p_campos_editados->>'nombre', v_s.nombre);
  v_desc   := COALESCE(p_campos_editados->>'descripcion', v_s.descripcion);
  v_orden  := COALESCE((p_campos_editados->>'orden')::int, v_s.orden);
  IF p_campos_editados ? 'capacidades' THEN
    v_caps := ARRAY(SELECT jsonb_array_elements_text(p_campos_editados->'capacidades'));
  ELSE
    v_caps := v_s.capacidades;
  END IF;

  -- Reusa crear_*_pais (auth.uid sigue siendo el super_admin → pasa su gate; revalida y maneja duplicado/cross-país).
  IF v_s.tipo = 'capacidad' THEN
    v_res := crear_capacidad_pais(v_codigo, v_nombre, v_desc, v_s.pais_id, v_orden);
  ELSE
    v_res := crear_tier_pais(v_codigo, v_nombre, v_desc, v_s.pais_id, v_orden, v_caps);
  END IF;

  -- Si la creación devolvió {error} (duplicado/cross-país): NO se marca aprobada → queda pendiente para reintentar.
  IF v_res ? 'error' THEN
    RETURN v_res;
  END IF;

  UPDATE solicitudes_capacidad_pais
    SET estado='aprobada', codigo=v_codigo, nombre=v_nombre, descripcion=v_desc, orden=v_orden,
        capacidades = CASE WHEN v_s.tipo='tier' THEN v_caps ELSE capacidades END,
        nota_revision=p_nota, resuelto_por=auth.uid(), resuelto_at=now(), updated_at=now()
    WHERE id=p_solicitud_id;
  RETURN jsonb_build_object('success', true, 'estado','aprobada', 'creado', v_res);
END;
$function$;

-- ========================= 4) listar_solicitudes_capacidades_pais =========================
CREATE OR REPLACE FUNCTION public.listar_solicitudes_capacidades_pais(p_pais_id uuid DEFAULT NULL)
RETURNS TABLE(id uuid, tipo text, pais_id uuid, pais_nombre text, solicitado_por uuid, solicitante text,
              codigo text, nombre text, descripcion text, orden int, capacidades text[], estado text,
              nota_revision text, resuelto_por uuid, resuelto_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT s.id, s.tipo, s.pais_id, cp.nombre::text, s.solicitado_por, pf.nombre_completo, s.codigo, s.nombre,
         s.descripcion, s.orden, s.capacidades, s.estado, s.nota_revision, s.resuelto_por, s.resuelto_at, s.created_at
  FROM solicitudes_capacidad_pais s
  JOIN configuracion_pais cp ON cp.id = s.pais_id
  LEFT JOIN perfiles pf ON pf.id = s.solicitado_por
  WHERE (
      (get_auth_user_rol()='super_admin' AND (p_pais_id IS NULL OR s.pais_id = p_pais_id))
   OR (get_auth_user_rol()='admin_pais' AND s.pais_id = get_auth_user_pais_id())
  )
  ORDER BY s.created_at DESC;
END;
$function$;

-- ========================= 5) listar_capacidades_pais =========================
CREATE OR REPLACE FUNCTION public.listar_capacidades_pais(p_pais_id uuid)
RETURNS TABLE(codigo text, nombre text, descripcion text, orden int, activo boolean, pais_id uuid, es_global boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT ( private.tiene_rol(ARRAY['super_admin'])
        OR (get_auth_user_rol()='admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()) ) THEN
    RAISE EXCEPTION 'No autorizado para ver capacidades de este país' USING ERRCODE='PC019';
  END IF;
  RETURN QUERY
  SELECT c.codigo, c.nombre, c.descripcion, c.orden, c.activo, c.pais_id, (c.pais_id IS NULL)
  FROM capacidades_catalogo c
  WHERE c.pais_id = p_pais_id OR c.pais_id IS NULL
  ORDER BY c.pais_id NULLS FIRST, c.orden, c.codigo;
END;
$function$;

-- ========================= 6) listar_tiers_pais =========================
CREATE OR REPLACE FUNCTION public.listar_tiers_pais(p_pais_id uuid)
RETURNS TABLE(id uuid, codigo text, nombre text, descripcion text, orden int, activo boolean, pais_id uuid,
              es_global boolean, capacidades text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT ( private.tiene_rol(ARRAY['super_admin'])
        OR (get_auth_user_rol()='admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()) ) THEN
    RAISE EXCEPTION 'No autorizado para ver tiers de este país' USING ERRCODE='PC019';
  END IF;
  RETURN QUERY
  SELECT t.id, t.codigo, t.nombre, t.descripcion, t.orden, t.activo, t.pais_id, (t.pais_id IS NULL),
         COALESCE(ARRAY(SELECT tc.capacidad_codigo FROM tier_capacidades tc WHERE tc.tier_id = t.id ORDER BY tc.capacidad_codigo), '{}'::text[])
  FROM tiers_catalogo t
  WHERE t.pais_id = p_pais_id OR t.pais_id IS NULL
  ORDER BY t.pais_id NULLS FIRST, t.orden, t.codigo;
END;
$function$;

-- ========================= 7) actualizar_techo_cortesia_pais (super_admin EXCLUSIVO) =========================
CREATE OR REPLACE FUNCTION public.actualizar_techo_cortesia_pais(p_pais_id uuid, p_valor integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.tiene_rol(ARRAY['super_admin']) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin actualiza el techo de cortesía' USING ERRCODE='PC019';
  END IF;
  IF p_valor IS NOT NULL AND p_valor <= 0 THEN
    RETURN jsonb_build_object('error','El techo debe ser NULL o mayor a 0');   -- espejo del CHECK existente
  END IF;
  UPDATE configuracion_pais SET techo_cortesia_visitas = p_valor WHERE id = p_pais_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','País no encontrado'); END IF;
  RETURN jsonb_build_object('success', true, 'techo_cortesia_visitas', p_valor);
END;
$function$;

-- ========================= 8) obtener_resumen_pais (lectura; super o admin_pais-propio) =========================
CREATE OR REPLACE FUNCTION public.obtener_resumen_pais(p_pais_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT ( private.tiene_rol(ARRAY['super_admin'])
        OR (get_auth_user_rol()='admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()) ) THEN
    RAISE EXCEPTION 'No autorizado para ver el resumen de este país' USING ERRCODE='PC019';
  END IF;
  SELECT jsonb_build_object('pais_id', id, 'nombre', nombre, 'techo_cortesia_visitas', techo_cortesia_visitas)
    INTO v FROM configuracion_pais WHERE id = p_pais_id;
  IF v IS NULL THEN RETURN jsonb_build_object('error','País no encontrado'); END IF;
  RETURN v;
END;
$function$;

-- ========================= GRANTS =========================
DO $grants$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'solicitar_capacidad_pais(uuid,text,text,text,integer)',
    'solicitar_tier_pais(uuid,text,text,text,integer,text[])',
    'resolver_solicitud_capacidad_pais(uuid,boolean,jsonb,text)',
    'listar_solicitudes_capacidades_pais(uuid)',
    'listar_capacidades_pais(uuid)',
    'listar_tiers_pais(uuid)',
    'actualizar_techo_cortesia_pais(uuid,integer)',
    'obtener_resumen_pais(uuid)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon;', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role;', fn);
  END LOOP;
END;
$grants$;

COMMIT;
