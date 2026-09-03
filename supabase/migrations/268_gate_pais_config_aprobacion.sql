-- ============================================================================
-- Migracion 268: gate de pais NULL-safe en las 7 RPCs de configuracion y aprobacion
-- ============================================================================
-- Paquete PA-FAILOPEN - LOTE 3.
--   crear_capacidad_pais - crear_tier_pais - solicitar_capacidad_pais - solicitar_tier_pais
--   aprobar_personalizacion - rechazar_personalizacion - resolver_propuesta_especialidad
--
-- A DIFERENCIA DE LOS LOTES 1 Y 2, LAS 7 YA ESTABAN VERSIONADAS: crear_* en la mig 218,
-- solicitar_* en la 227, y las tres de moderacion en la 221 (sobre 205 y 186). No hay "primera
-- version en git" que revisar aca. Ademas se verifico que NO hay drift: el gate que dice la
-- migracion mas reciente del repo coincide con el gate vivo en las 7. Aun asi el texto se capturo
-- del objeto vivo con pg_get_functiondef() y la migracion se GENERO por script desde ese texto
-- (md5 verificado), igual que la 267: el repo puede coincidir hoy y no ser la fuente de verdad.
--
-- ----------------------------------------------------------------------------
-- LAS 7 USAN EL DEFAULT DE p_roles
-- ----------------------------------------------------------------------------
-- Ninguna de estas siete usa el array ['ezpay_admin','super_admin','admin_finanzas']. Ese vestigio
-- vive en notificar_empresa_estado / notificar_pago_resultado / notificar_campana_resultado, que
-- son de los lotes 5 y 6. Las 7 de aca gatean por super_admin, asi que consumen
-- private.puede_admin_pais(<pais>) con el p_roles POR DEFECTO (ARRAY['super_admin']) y no hace
-- falta pasarlo explicito.
--
-- ----------------------------------------------------------------------------
-- DOS FORMAS DE GATE, UNA SOLA TRADUCCION
-- ----------------------------------------------------------------------------
-- (a) Las cuatro de capacidades/tiers comparan un PARAMETRO contra el pais del caller:
--       ... AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id()
--     -> private.puede_admin_pais(p_pais_id).  El `IS NOT NULL` explicito ya vive DENTRO del
--     helper, asi que no se pierde: se centraliza.
--
-- (b) Las tres de moderacion derivan el pais del REGISTRO con un helper propio:
--       ... AND private.pais_de_solicitud_personalizacion(p_solicitud_id) = get_auth_user_pais_id()
--       ... AND private.pais_de_propuesta_especialidad(p_propuesta_id)    = get_auth_user_pais_id()
--     -> private.puede_admin_pais(private.pais_de_X(<id>)).  El helper interno se conserva tal
--     cual: sigue siendo el que deriva el pais del servidor, y ahora su resultado entra como
--     argumento en vez de compararse a mano. Si el registro no existe, ese helper devuelve NULL y
--     puede_admin_pais devuelve false para admin_pais (antes: NULL = NULL -> NULL -> fail-open).
--
-- El gate se localizo y reemplazo caminando parentesis, no con un regex: estos gates tienen
-- parentesis anidados (ARRAY[...], COALESCE, llamadas a helpers) y un regex corta donde no debe.
--
-- ----------------------------------------------------------------------------
-- LO QUE NO SE TOCA
-- ----------------------------------------------------------------------------
-- Firma, volatilidad, SECURITY DEFINER, search_path, cuerpo, ERRCODEs (PT001, PC005-PC009, PS001-
-- PS003 segun la funcion), mensajes, los FOR UPDATE de las de moderacion y el ORDEN del gate
-- respecto de las validaciones de existencia posteriores. Solo cambia la expresion del IF.
--
-- Grants re-afirmados al final: CREATE OR REPLACE puede restablecer privilegios por default.
-- Estado previo verificado y preservado. Es la leccion de la 266 y la 267.
--
-- CENTINELA: allowlist del P480 22 -> 15. P481 apunta hoy a aprobar_solicitud_campana, que NO entra
-- en este lote (es del lote 5) y sigue en rojo, asi que NO hay que re-apuntarlo esta vez. Verificado
-- explicitamente, no asumido.
-- ============================================================================

BEGIN;

-- ========================= 1) crear_capacidad_pais (mig 218) =========================
-- Gate ANTES: private.tiene_rol(ARRAY['super_admin'])
--             OR (get_auth_user_rol() = 'admin_pais' AND p_pais_id IS NOT NULL
--                 AND p_pais_id = get_auth_user_pais_id())
-- Gate AHORA: IF NOT private.puede_admin_pais(p_pais_id) THEN
CREATE OR REPLACE FUNCTION public.crear_capacidad_pais(p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL::text, p_pais_id uuid DEFAULT NULL::uuid, p_orden integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Gate: super_admin (cualquier país o NULL global) O admin_pais SOLO su propio país (nunca NULL/otro).
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin (cualquier país) o admin_pais de su propio país puede crear capacidades';
  END IF;

  IF EXISTS (SELECT 1 FROM capacidades_catalogo WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('error', 'Ya existe una capacidad con ese código');
  END IF;

  INSERT INTO capacidades_catalogo (codigo, nombre, descripcion, pais_id, orden, activo)
  VALUES (p_codigo, p_nombre, p_descripcion, p_pais_id, p_orden, true);

  RETURN jsonb_build_object('success', true, 'codigo', p_codigo);
END;
$function$
;


-- ========================= 2) crear_tier_pais (mig 218) =========================
-- Mismo gate y misma traduccion que crear_capacidad_pais.
CREATE OR REPLACE FUNCTION public.crear_tier_pais(p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL::text, p_pais_id uuid DEFAULT NULL::uuid, p_orden integer DEFAULT 100, p_capacidades text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tier_id uuid;
  v_caps    text[];
  v_cod     text;
  v_cap_pais uuid;
  v_count   int := 0;
BEGIN
  -- Gate idéntico a crear_capacidad_pais.
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin (cualquier país) o admin_pais de su propio país puede crear tiers';
  END IF;

  IF EXISTS (SELECT 1 FROM tiers_catalogo WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('error', 'Ya existe un tier con ese código');
  END IF;

  -- VALIDAR las capacidades ANTES de insertar el tier (atomicidad: si alguna falla, no se insertó nada).
  -- Regla cross-país: cada capacidad debe existir y ser GLOBAL (pais_id NULL) o del MISMO país del tier.
  IF p_capacidades IS NOT NULL THEN
    v_caps := ARRAY(SELECT DISTINCT c FROM unnest(p_capacidades) AS c WHERE c IS NOT NULL);
    FOREACH v_cod IN ARRAY v_caps LOOP
      SELECT pais_id INTO v_cap_pais FROM capacidades_catalogo WHERE codigo = v_cod;
      IF NOT FOUND OR NOT (v_cap_pais IS NULL OR v_cap_pais = p_pais_id) THEN
        RETURN jsonb_build_object('error', format('La capacidad %s no existe o no pertenece a este país', v_cod));
      END IF;
    END LOOP;
  END IF;

  INSERT INTO tiers_catalogo (codigo, nombre, descripcion, pais_id, orden, activo)
  VALUES (p_codigo, p_nombre, p_descripcion, p_pais_id, p_orden, true)
  RETURNING id INTO v_tier_id;

  IF v_caps IS NOT NULL THEN
    FOREACH v_cod IN ARRAY v_caps LOOP
      INSERT INTO tier_capacidades (tier_id, capacidad_codigo) VALUES (v_tier_id, v_cod);
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'codigo', p_codigo, 'tier_id', v_tier_id, 'capacidades_vinculadas', v_count);
END;
$function$
;


-- ========================= 3) solicitar_capacidad_pais (mig 227) =========================
-- Mismo gate (sin espacios alrededor del '=' en el original, de ahi que el reemplazo se haga
-- caminando parentesis y no por coincidencia de texto).
CREATE OR REPLACE FUNCTION public.solicitar_capacidad_pais(p_pais_id uuid, p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL::text, p_orden integer DEFAULT 100)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado para solicitar capacidades de este país' USING ERRCODE='PC019';
  END IF;
  IF p_codigo IS NULL OR p_nombre IS NULL THEN RAISE EXCEPTION 'codigo y nombre son obligatorios'; END IF;
  INSERT INTO solicitudes_capacidad_pais (tipo, pais_id, solicitado_por, codigo, nombre, descripcion, orden)
  VALUES ('capacidad', p_pais_id, auth.uid(), p_codigo, p_nombre, p_descripcion, COALESCE(p_orden,100))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$
;


-- ========================= 4) solicitar_tier_pais (mig 227) =========================
-- Mismo gate y misma traduccion que solicitar_capacidad_pais.
CREATE OR REPLACE FUNCTION public.solicitar_tier_pais(p_pais_id uuid, p_codigo text, p_nombre text, p_descripcion text DEFAULT NULL::text, p_orden integer DEFAULT 100, p_capacidades text[] DEFAULT NULL::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado para solicitar tiers de este país' USING ERRCODE='PC019';
  END IF;
  IF p_codigo IS NULL OR p_nombre IS NULL THEN RAISE EXCEPTION 'codigo y nombre son obligatorios'; END IF;
  INSERT INTO solicitudes_capacidad_pais (tipo, pais_id, solicitado_por, codigo, nombre, descripcion, orden, capacidades)
  VALUES ('tier', p_pais_id, auth.uid(), p_codigo, p_nombre, p_descripcion, COALESCE(p_orden,100), p_capacidades)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$
;


-- ========================= 5) aprobar_personalizacion (mig 221) =========================
-- Gate ANTES: COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
--             OR (get_auth_user_rol() = 'admin_pais'
--                 AND private.pais_de_solicitud_personalizacion(p_solicitud_id) = get_auth_user_pais_id())
-- Gate AHORA: IF NOT private.puede_admin_pais(private.pais_de_solicitud_personalizacion(p_solicitud_id)) THEN
-- El COALESCE de la izquierda cubria SOLO tiene_rol; la rama admin_pais quedaba trivaluada. Es
-- exactamente el patron que un regex por "COALESCE" daria por bueno.
CREATE OR REPLACE FUNCTION public.aprobar_personalizacion(p_solicitud_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_s RECORD;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_solicitud_personalizacion(p_solicitud_id)) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;

  SELECT * INTO v_s FROM public.solicitudes_personalizacion WHERE id = p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_s.estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;

  PERFORM set_config('app.personalizacion_rpc','on', true);  -- habilita el guard SOLO en esta tx

  IF v_s.tenant_tipo = 'clinica' THEN
    UPDATE public.clinicas
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  ELSE
    UPDATE public.empresas_proveedoras
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  END IF;

  UPDATE public.solicitudes_personalizacion
    SET estado='aprobada', revisado_por=auth.uid(), revisado_at=now()
    WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok',true,'estado','aprobada','tenant_tipo',v_s.tenant_tipo,'tenant_id',v_s.tenant_id);
END;
$function$
;


-- ========================= 6) rechazar_personalizacion (mig 221) =========================
-- Mismo gate y misma traduccion que aprobar_personalizacion.
CREATE OR REPLACE FUNCTION public.rechazar_personalizacion(p_solicitud_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_estado text;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_solicitud_personalizacion(p_solicitud_id)) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;
  SELECT estado INTO v_estado FROM public.solicitudes_personalizacion WHERE id=p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;
  UPDATE public.solicitudes_personalizacion
    SET estado='rechazada', revisado_por=auth.uid(), revisado_at=now(), motivo_rechazo=p_motivo
    WHERE id=p_solicitud_id;
  RETURN jsonb_build_object('ok',true,'estado','rechazada');
END;
$function$
;


-- ========================= 7) resolver_propuesta_especialidad (mig 221) =========================
-- Igual, con el helper de pais propio de las propuestas de especialidad.
-- Gate AHORA: IF NOT private.puede_admin_pais(private.pais_de_propuesta_especialidad(p_propuesta_id)) THEN
CREATE OR REPLACE FUNCTION public.resolver_propuesta_especialidad(p_propuesta_id uuid, p_aprobar boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_prop   RECORD;
  v_esp_id uuid;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_propuesta_especialidad(p_propuesta_id)) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución.
  SELECT id, medico_id, nombre_propuesto, estado
  INTO v_prop
  FROM public.especialidades_propuestas
  WHERE id = p_propuesta_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'propuesta_inexistente'; END IF;
  IF v_prop.estado <> 'pendiente' THEN RAISE EXCEPTION 'propuesta_ya_resuelta'; END IF;

  IF p_aprobar THEN
    -- a) crear especialidad, o REUSAR la existente por nombre exacto (UNIQUE) sin fallar.
    --    ON CONFLICT DO UPDATE (self no-op) permite RETURNING id tanto en insert nuevo como en reuso, y es race-safe.
    INSERT INTO public.especialidades (nombre, activo)
    VALUES (v_prop.nombre_propuesto, true)
    ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
    RETURNING id INTO v_esp_id;

    -- b) setear la especialidad del médico proponente.
    UPDATE public.medicos SET especialidad_id = v_esp_id WHERE id = v_prop.medico_id;

    -- c) marcar la propuesta como aprobada (referencia la especialidad usada).
    UPDATE public.especialidades_propuestas
    SET estado = 'aprobada', especialidad_id = v_esp_id, resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'aprobada', 'especialidad_id', v_esp_id);
  ELSE
    -- Rechazo: NO tocar medicos ni especialidades, solo marcar.
    UPDATE public.especialidades_propuestas
    SET estado = 'rechazada', resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'rechazada');
  END IF;
  -- Si cualquier paso de la aprobación falla, la excepción revierte TODA la transacción de la función.
END;
$function$
;


-- ========================= GRANTS: re-afirmar el estado previo =========================
REVOKE ALL     ON FUNCTION public.crear_capacidad_pais(text, text, text, uuid, integer) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.crear_tier_pais(text, text, text, uuid, integer, text[]) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.solicitar_capacidad_pais(uuid, text, text, text, integer) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.solicitar_tier_pais(uuid, text, text, text, integer, text[]) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.aprobar_personalizacion(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.rechazar_personalizacion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.resolver_propuesta_especialidad(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_capacidad_pais(text, text, text, uuid, integer) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.crear_tier_pais(text, text, text, uuid, integer, text[]) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.solicitar_capacidad_pais(uuid, text, text, text, integer) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.solicitar_tier_pais(uuid, text, text, text, integer, text[]) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.aprobar_personalizacion(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.rechazar_personalizacion(uuid, text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.resolver_propuesta_especialidad(uuid, boolean) TO authenticated, service_role;

COMMIT;

-- Verificacion estructural (DESPUES del COMMIT): las 7 con prosecdef=t, proconfig preservado,
-- anon=false, PUBLIC=false, gate_migrado=true y restos_gate_viejo=false.
