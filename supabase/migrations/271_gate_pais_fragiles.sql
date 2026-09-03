-- ============================================================================
-- Migracion 271: gate NULL-safe en las 5 fragiles-no-explotables — CIERRA EL PAQUETE
-- ============================================================================
-- Paquete PA-FAILOPEN - LOTE 6, EL ULTIMO.
--   activar_capacidad_suelta - asignar_tier - notificar_empresa_estado -
--   notificar_resultado_examen - registrar_evidencia_entrega
--
-- Con esta migracion la allowlist del centinela P480 llega a CERO y el paquete queda completo:
-- 27 funciones migradas a private.puede_admin_pais / private.es_admin_pais.
--
-- Texto capturado del objeto vivo con pg_get_functiondef() (md5 verificado) y migracion generada
-- por script desde ese texto, con reemplazos EXACTOS uno por uno.
--
-- ============================================================================
-- POR QUE SE MIGRAN SI NINGUNA ES EXPLOTABLE
-- ============================================================================
-- Las cinco aguantan hoy, pero ninguna aguanta POR DISENO: aguantan por la FORMA de su segundo
-- conjunto. Es la misma leccion que el lote 5 dejo escrita, llevada al final: la proteccion no puede
-- depender de que construccion eligio quien escribio el gate, porque la proxima persona elige otra.
-- Clasificacion, verificada contra el cuerpo vivo:
--
--   activar_capacidad_suelta     PREVENTIVO. El termino directo esta en una rama POSITIVA de scope
--   asignar_tier                 (IF get_auth_user_rol()='admin_pais' THEN ...) y ademas detras de
--                                TRES gates anteriores: admin_puede_gestionar_empresa (COALESCE-ado,
--                                corta), empresa_no_existe (PC002) y capacidad/tier_no_existe
--                                (PC003/PC004). Con rol NULL el primero ya bloqueo.
--
--   registrar_evidencia_entrega  PREVENTIVO. Su `p_path NOT LIKE (mi_empresa_proveedor()||...)` SI es
--                                fail-open (NOT LIKE NULL -> NULL -> sin RAISE), pero es INALCANZABLE:
--                                antes pasan tiene_permiso('entregas_actualizar_estado') COALESCE-ado,
--                                el SELECT con COALESCE(empresa_id=mi_empresa_proveedor(), false) +
--                                IF NOT FOUND, y el guard delivery_id IS DISTINCT FROM auth.uid().
--                                Un caller sin empresa nunca llega a esa linea.
--
--   notificar_empresa_estado     El gate de identidad es el UNICO control. Aguanta porque
--                                private.admin_puede_gestionar_empresa devuelve false (esta
--                                COALESCE-ado por dentro) y NULL AND false = false. Si ese helper
--                                devolviera NULL, seria fail-open. Depende de un COALESCE ajeno.
--
--   notificar_resultado_examen   El gate de identidad es el UNICO control. Aguanta porque
--                                IS DISTINCT FROM es NULL-safe por construccion.
--
-- ============================================================================
-- EL UNICO CAMBIO DE COMPORTAMIENTO DEL LOTE: notificar_resultado_examen
-- ============================================================================
--   ANTES: IF v.laboratorio_id IS DISTINCT FROM public.mi_empresa_proveedor() THEN RAISE
--   AHORA: IF NOT COALESCE(v.laboratorio_id = public.mi_empresa_proveedor(), false) THEN RAISE
-- Las dos formas coinciden en todos los casos MENOS UNO: cuando AMBOS lados son NULL.
--   IS DISTINCT FROM (NULL, NULL) = false  -> NO levantaba -> el caller PASABA.
--   NOT COALESCE(NULL = NULL, false) = true -> levanta -> el caller es BLOQUEADO.
-- O sea: un examen SIN laboratorio consultado por alguien SIN empresa proveedora pasaba, y ahora no.
-- Verificado contra la base viva antes de decidir: examenes.laboratorio_id ES NULLABLE, y hoy hay
-- 0 filas con NULL sobre 11 examenes -> impacto vivo NULO. Es un endurecimiento fail-closed,
-- consistente con la regla del proyecto, y se declara en vez de esconderlo detras de un COALESCE
-- cosmetico que dejara el IS DISTINCT FROM intacto solo para callar al centinela.
--
-- ============================================================================
-- LO QUE NO SE TOCA
-- ============================================================================
-- El p_roles de cada una tal cual: notificar_empresa_estado conserva su
-- ARRAY['ezpay_admin','super_admin','admin_finanzas'] (roles fantasma, ver mig 270) y ninguna otra
-- recibe un array que no tenia. Firmas, volatilidad, SECURITY DEFINER, search_path, cuerpos,
-- ERRCODEs (PC001-PC004, PC015, PC016, PT002), mensajes, el ON CONFLICT de las dos de capacidades,
-- los guards de existencia y su ORDEN respecto del gate.
--
-- En activar_capacidad_suelta / asignar_tier el termino `pais_id IS NOT NULL AND` que precede a la
-- comparacion es LOAD-BEARING y se conserva: sin el, una capacidad GLOBAL (pais_id NULL) daria
-- NOT puede_admin_pais(NULL) = true y se leeria como "de otro pais", rompiendo las capacidades
-- globales. La traduccion es exacta solo con ese termino delante.
--
-- Grants re-afirmados al final.
-- ============================================================================

BEGIN;

-- ========================= 1) activar_capacidad_suelta (mig 219) =========================
-- PREVENTIVO: detras de admin_puede_gestionar_empresa (COALESCE-ado) + PC002 + PC003.
--   rama de scope:  IF get_auth_user_rol() = 'admin_pais' THEN  ->  IF private.es_admin_pais() THEN
--   comparacion:    AND pais_id <> get_auth_user_pais_id()      ->  AND NOT private.puede_admin_pais(pais_id)
-- Equivalencia: para un admin_pais, puede_admin_pais(p) = (p IS NOT NULL AND p = su pais), asi que
-- `pais_id IS NOT NULL AND NOT puede_admin_pais(pais_id)` == `pais_id IS NOT NULL AND pais_id <> su pais`.
CREATE OR REPLACE FUNCTION public.activar_capacidad_suelta(p_empresa_id uuid, p_capacidad_codigo text, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.capacidades_catalogo WHERE codigo = p_capacidad_codigo) THEN
    RAISE EXCEPTION 'capacidad_no_existe' USING ERRCODE = 'PC003';
  END IF;

  -- SCOPE (mig 219): un admin_pais no puede asignar una capacidad de OTRO país (super_admin sí, global).
  IF private.es_admin_pais() THEN
    IF EXISTS (
      SELECT 1 FROM public.capacidades_catalogo
      WHERE codigo = p_capacidad_codigo
        AND pais_id IS NOT NULL
        AND NOT private.puede_admin_pais(pais_id)
    ) THEN
      RAISE EXCEPTION 'capacidad_de_otro_pais' USING ERRCODE = 'PC015';
    END IF;
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  VALUES (p_empresa_id, p_capacidad_codigo, true, 'suelta', NULL, now(), p_hasta, auth.uid())
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por;
    -- NO se toca origen/tier_id: si venía de un tier, se queda como estaba (solo re-activa). updated_at por trigger.

  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND capacidad_codigo = p_capacidad_codigo;
END;
$function$
;


-- ========================= 2) asignar_tier (mig 219) =========================
-- Mismo caso y misma traduccion que activar_capacidad_suelta, sobre tiers_catalogo.
CREATE OR REPLACE FUNCTION public.asignar_tier(p_empresa_id uuid, p_tier_id uuid, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tiers_catalogo WHERE id = p_tier_id) THEN
    RAISE EXCEPTION 'tier_no_existe' USING ERRCODE = 'PC004';
  END IF;

  -- SCOPE (mig 219): un admin_pais no puede asignar un tier de OTRO país (super_admin sí, global).
  IF private.es_admin_pais() THEN
    IF EXISTS (
      SELECT 1 FROM public.tiers_catalogo
      WHERE id = p_tier_id
        AND pais_id IS NOT NULL
        AND NOT private.puede_admin_pais(pais_id)
    ) THEN
      RAISE EXCEPTION 'tier_de_otro_pais' USING ERRCODE = 'PC016';
    END IF;
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  SELECT p_empresa_id, tc.capacidad_codigo, true, 'tier', p_tier_id, now(), p_hasta, auth.uid()
  FROM public.tier_capacidades tc
  WHERE tc.tier_id = p_tier_id
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por,
        origen = 'tier', tier_id = EXCLUDED.tier_id;  -- el tier adopta la capacidad. updated_at por trigger.

  -- set resultante: capacidades activas vigentes de la empresa (las sueltas ajenas al tier se mantienen)
  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND activa = true AND (hasta IS NULL OR hasta > now());
END;
$function$
;


-- ========================= 3) notificar_empresa_estado (mig 222) =========================
-- El gate de identidad es el unico control; aguantaba por el COALESCE INTERNO de
-- admin_puede_gestionar_empresa. Ahora el termino de rol es NULL-safe por si mismo.
--   ANTES: COALESCE(tiene_rol(ARRAY[3 roles]), false)
--          OR (public.get_auth_user_rol() = 'admin_pais' AND admin_puede_gestionar_empresa(...))
--   AHORA: tiene_rol(ARRAY[3 roles])            -- ya devuelve boolean estricto: el COALESCE sobraba
--          OR (private.es_admin_pais() AND admin_puede_gestionar_empresa(...))
-- El array de 3 roles se preserva completo (ver mig 270 para el porque).
CREATE OR REPLACE FUNCTION public.notificar_empresa_estado(p_empresa_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_estado text; v_titulo text; v_msg text; rec record;
BEGIN
  -- Vestigio de roles NO se toca (ezpay_admin/admin_finanzas no existen → solo super_admin pasa por ahí).
  -- Se AGREGA la rama admin_pais: empresa de su país (helper de pieza 7).
  IF NOT (
    private.tiene_rol(ARRAY['ezpay_admin','super_admin','admin_finanzas'])
    OR (private.es_admin_pais() AND private.admin_puede_gestionar_empresa(p_empresa_id))
  ) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado INTO v_estado FROM public.empresas_proveedoras WHERE id = p_empresa_id;
  IF NOT FOUND OR v_estado IS NULL THEN RETURN; END IF;
  v_titulo := CASE WHEN v_estado = 'activa' THEN 'Empresa aprobada' ELSE 'Estado de tu empresa actualizado' END;
  v_msg := CASE WHEN v_estado = 'activa' THEN 'Tu empresa fue aprobada. Ya puedes operar en EzPayConnect.'
                ELSE 'El estado de tu empresa cambió a: ' || v_estado || '.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(p_empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'empresa', v_titulo, v_msg, '/proveedor/dashboard');
  END LOOP;
END;
$function$
;


-- ========================= 4) notificar_resultado_examen =========================
-- UNICO CAMBIO DE COMPORTAMIENTO DEL LOTE — ver el encabezado. IS DISTINCT FROM y la forma COALESCE
-- solo difieren cuando AMBOS lados son NULL; ahi la nueva BLOQUEA donde la vieja dejaba pasar.
-- examenes.laboratorio_id es nullable pero hoy tiene 0 filas NULL: impacto vivo nulo.
CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_mid uuid;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  IF NOT COALESCE(v.laboratorio_id = public.mi_empresa_proveedor(), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='PT002'; END IF;
  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
              'Un paciente tiene un resultado de examen nuevo para revisar.', '/medico/citas')
      RETURNING id INTO v_mid;
    IF v_mid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones', v_mid::text); END IF;
  END IF;
  RETURN jsonb_build_object('medico', v.medico_id);
END; $function$
;


-- ========================= 5) registrar_evidencia_entrega =========================
-- PREVENTIVO pero el unico con fail-open REAL en la linea: NOT LIKE contra un concat que da NULL si
-- mi_empresa_proveedor() es NULL. Inalcanzable por los tres gates anteriores. Se envuelve igual.
CREATE OR REPLACE FUNCTION public.registrar_evidencia_entrega(p_entrega_id bigint, p_path text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_e public.entregas; v_tipo text;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.delivery_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Solo el delivery asignado adjunta evidencia'; END IF;
  IF NOT COALESCE(p_path LIKE (public.mi_empresa_proveedor()::text || '/' || p_entrega_id::text || '/%'), false) THEN
    RAISE EXCEPTION 'Path fuera de scope'; END IF;
  -- Tipo: explícito si viene; si no, se infiere del nombre del archivo (la PWA viva sube {tipo}_{ts}).
  v_tipo := COALESCE(
    p_tipo,
    CASE WHEN p_path ~ '/foto_'  THEN 'foto'
         WHEN p_path ~ '/firma_' THEN 'firma' END
  );
  IF v_tipo IS NOT NULL AND v_tipo NOT IN ('foto','firma') THEN RAISE EXCEPTION 'Tipo inválido'; END IF;
  -- COMPAT: SIGUE seteando evidencia_path (la PWA en prod lo lee). NO se dropea la columna en esta mig.
  UPDATE public.entregas SET evidencia_path=p_path, updated_at=now() WHERE id=p_entrega_id;
  -- ADITIVO: registra en la tabla nueva (si se pudo determinar el tipo).
  IF v_tipo IS NOT NULL THEN
    INSERT INTO public.entrega_evidencias(entrega_id, tipo, path, subido_por)
    VALUES (p_entrega_id, v_tipo, p_path, auth.uid());
  END IF;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $function$
;


-- ========================= GRANTS: re-afirmar el estado previo =========================
REVOKE ALL     ON FUNCTION public.activar_capacidad_suelta(uuid, text, timestamp with time zone) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.asignar_tier(uuid, uuid, timestamp with time zone) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.notificar_empresa_estado(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.notificar_resultado_examen(integer) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.registrar_evidencia_entrega(bigint, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.activar_capacidad_suelta(uuid, text, timestamp with time zone) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.asignar_tier(uuid, uuid, timestamp with time zone) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.notificar_empresa_estado(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.notificar_resultado_examen(integer) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint, text, text) TO authenticated, service_role;

COMMIT;
