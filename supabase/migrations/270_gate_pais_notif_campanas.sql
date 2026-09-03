-- ============================================================================
-- Migracion 270: gate de pais NULL-safe en notificaciones, campanas y canjes
-- ============================================================================
-- Paquete PA-FAILOPEN - LOTE 5.
--   notificar_pago_resultado - notificar_campana_resultado - aprobar_solicitud_campana - resolver_canje
--
-- Texto capturado del objeto vivo con pg_get_functiondef() (md5 verificado) y migracion GENERADA
-- por script desde ese texto. Solo cambia la expresion del gate.
--
-- ============================================================================
-- EL ARRAY DE ROLES SE PRESERVA COMPLETO. NO SE SIMPLIFICA.
-- ============================================================================
-- Dos de las cuatro gatean con ARRAY['ezpay_admin','super_admin','admin_finanzas']. `ezpay_admin` y
-- `admin_finanzas` son roles FANTASMA: vestigios que el proyecto decidio dejar intactos (mig 222 lo
-- dice explicitamente). Estado verificado contra la base viva antes de escribir esto:
--     perfiles con rol ezpay_admin ........ 0
--     perfiles con rol admin_finanzas ..... 0
--     ezpay_admin en roles_catalogo ....... 0
--     admin_finanzas en roles_catalogo .... 0
--     ezpay_admin / admin_finanzas en public.roles (legacy) ... 0 / 0
--     FK perfiles.rol -> roles_catalogo ... existe
-- O sea: hoy no solo NO HAY perfiles con esos roles, sino que es ESTRUCTURALMENTE IMPOSIBLE
-- crearlos — la FK contra roles_catalogo los rechazaria. En la practica ese array matchea
-- unicamente a super_admin.
--
-- AUN ASI SE PASA COMPLETO como p_roles a private.puede_admin_pais. Reducirlo a ['super_admin']
-- seria hoy equivalente y manana no: bastaria que alguien agregue esos codigos a roles_catalogo
-- para que el array empiece a matchear, y el cambio de comportamiento habria quedado enterrado en
-- una migracion de seguridad que decia preservar. Esta migracion PRESERVA; limpiar vestigios es un
-- frente aparte, con su propio censo y su propia decision.
-- Las otras dos (aprobar_solicitud_campana, resolver_canje) gatean con ['super_admin'] y por lo
-- tanto usan el p_roles POR DEFECTO del helper: tampoco se les agrega el array que no tenian.
--
-- ============================================================================
-- UN OBJETO NUEVO: private.pais_de_solicitud_campana
-- ============================================================================
-- Es lo unico de esta migracion que no es preservacion, y va senalado a proposito.
-- Dos de las cuatro derivan el pais de la MISMA solicitud de campana, y lo hacian con un EXISTS
-- inline:
--     ... AND EXISTS (SELECT 1 FROM public.solicitudes_campana
--                      WHERE id = p_solicitud_id AND pais_id = public.get_auth_user_pais_id())
-- Para pasarlo como ARGUMENTO del helper hace falta el pais como valor, no como predicado. Las
-- alternativas eran una subconsulta escalar repetida en dos funciones, o un helper. Se elige el
-- helper porque la familia ya existe y este calca su forma exacta: private.pais_de_pago_proveedor
-- (creado en la mig 222, la misma que introdujo el bug que estamos cerrando),
-- private.pais_de_canje, private.pais_de_propuesta_especialidad,
-- private.pais_de_solicitud_personalizacion. La mig 222 habia decidido no crearlo "porque el pais
-- es directo"; con el helper de gate esa decision se invierte, y queda la familia completa.
-- SQL STABLE SECURITY DEFINER search_path='' + REVOKE de PUBLIC/anon, igual que sus cuatro hermanos.
--
-- ============================================================================
-- LO QUE NO SE TOCA
-- ============================================================================
-- Firma, volatilidad, SECURITY DEFINER, search_path, cuerpos, ERRCODEs (PT002 en las dos
-- notificar_*, RAISE sin codigo en las otras dos), mensajes, el FOR UPDATE anti doble-resolucion de
-- resolver_canje, su reversa de puntos y stock, la validacion empresa_opera_en_pais de
-- aprobar_solicitud_campana y los guards de estado notificable. Solo cambia el IF.
--
-- Grants re-afirmados al final. CENTINELA: allowlist 9 -> 5, y P481 SE RE-APUNTA (tercera vez):
-- apuntaba a aprobar_solicitud_campana, que se salda aca.
-- ============================================================================

BEGIN;

-- ========================= 0) HELPER NUEVO: pais_de_solicitud_campana =========================
-- Calca a private.pais_de_pago_proveedor (mig 222) linea por linea, cambiando la tabla.
CREATE OR REPLACE FUNCTION private.pais_de_solicitud_campana(p_solicitud_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT sc.pais_id FROM public.solicitudes_campana sc WHERE sc.id = p_solicitud_id;
$$;
REVOKE ALL     ON FUNCTION private.pais_de_solicitud_campana(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.pais_de_solicitud_campana(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION private.pais_de_solicitud_campana(uuid) IS
$c$Pais de una solicitud de campana, derivado del servidor. Hermano de pais_de_pago_proveedor,
pais_de_canje, pais_de_propuesta_especialidad y pais_de_solicitud_personalizacion.
Creado en la mig 270 (PA-FAILOPEN lote 5): aprobar_solicitud_campana y notificar_campana_resultado
derivaban el pais con un EXISTS inline, y para pasarlo como ARGUMENTO de private.puede_admin_pais
hace falta el valor, no el predicado. Si la solicitud no existe devuelve NULL, y puede_admin_pais
convierte ese NULL en false para admin_pais (antes: NULL = NULL -> NULL -> fail-open).$c$;


-- ========================= 1) notificar_pago_resultado =========================
-- MEDIDA EN EL CENSO: con el gate viejo, un caller sin fila en perfiles INSERTABA notificaciones
-- (3 filas en la medicion original). El pais ya salia del servidor via pais_de_pago_proveedor; lo
-- que fallaba era la comparacion trivaluada.
-- Gate AHORA: private.puede_admin_pais(private.pais_de_pago_proveedor(p_pago_id),
--                                      ARRAY['ezpay_admin','super_admin','admin_finanzas'])
-- El array de 3 roles va COMPLETO: ver el encabezado.
CREATE OR REPLACE FUNCTION public.notificar_pago_resultado(p_pago_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_pago_proveedor(p_pago_id),
                                  ARRAY['ezpay_admin','super_admin','admin_finanzas']) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, empresa_id INTO v FROM public.pagos_proveedor WHERE id = p_pago_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('verificado','rechazado') THEN RETURN; END IF;  -- estado notificable
  v_titulo := CASE WHEN v.estado = 'verificado' THEN 'Pago verificado' ELSE 'Pago rechazado' END;
  v_msg := CASE WHEN v.estado = 'verificado' THEN 'Tu pago fue verificado y el servicio quedó activo.'
                ELSE 'Tu pago fue rechazado. Revisa el comprobante o contacta a EzPayConnect.' END;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'pago', v_titulo, v_msg, '/proveedor/pagos');
  END LOOP;
END;
$function$
;


-- ========================= 2) notificar_campana_resultado =========================
-- Mismo patron. El EXISTS inline sobre solicitudes_campana pasa a
-- private.pais_de_solicitud_campana(p_solicitud_id) como argumento del helper.
-- Array de 3 roles COMPLETO.
CREATE OR REPLACE FUNCTION public.notificar_campana_resultado(p_solicitud_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; rec record;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_solicitud_campana(p_solicitud_id),
                                  ARRAY['ezpay_admin','super_admin','admin_finanzas']) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  SELECT estado, titulo, empresa_id, notas_admin INTO v FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND OR v.empresa_id IS NULL OR v.estado NOT IN ('publicada','rechazada') THEN RETURN; END IF;  -- estado notificable
  IF v.estado = 'publicada' THEN
    v_titulo := 'Campaña aprobada';
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue aprobada y publicada.';
  ELSE
    v_titulo := 'Campaña rechazada';
    -- notas_admin PERSISTIDO en el ref (no param del caller) → se incluye si existe
    v_msg := 'Tu campaña "' || COALESCE(v.titulo,'') || '" fue rechazada.' || COALESCE(' Motivo: ' || NULLIF(v.notas_admin,''), '');
  END IF;
  FOR rec IN SELECT user_id FROM public.obtener_usuarios_empresa(v.empresa_id) LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.user_id, 'campana', v_titulo, v_msg, '/proveedor/publicidad/campanas');
  END LOOP;
END;
$function$
;


-- ========================= 3) aprobar_solicitud_campana =========================
-- Gatea con ['super_admin'] -> p_roles POR DEFECTO del helper (no se le agrega el array de 3).
-- Crea la campana publicitaria y marca la solicitud como publicada: es escritura real.
-- La validacion empresa_opera_en_pais y el 'Solicitud no encontrada' posterior NO se tocan, y
-- conservan su orden respecto del gate.
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_s RECORD; v_campana_id integer;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_solicitud_campana(p_solicitud_id)) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada'; END IF;
  -- validación existente (que la empresa realmente opere en el país de la campaña): NO se toca.
  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el país de la campaña';
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id,
     empresa_id, solicitud_campana_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id,
     v_s.empresa_id, p_solicitud_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
    SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
    WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$
;


-- ========================= 4) resolver_canje =========================
-- Gatea con ['super_admin'] -> p_roles por defecto. El pais ya salia de private.pais_de_canje.
-- El FOR UPDATE anti doble-resolucion, el guard 'canje_ya_resuelto' y la REVERSA de puntos y stock
-- al rechazar quedan intactos.
CREATE OR REPLACE FUNCTION public.resolver_canje(_canje_id bigint, _aprobar boolean, _nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_canje RECORD;
  v_estado text;
BEGIN
  IF NOT private.puede_admin_pais(private.pais_de_canje(_canje_id)) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución
  SELECT id, paciente_id, premio_id, costo_puntos, estado INTO v_canje
  FROM public.canjes WHERE id = _canje_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'canje_inexistente'; END IF;
  IF v_canje.estado <> 'pendiente' THEN RAISE EXCEPTION 'canje_ya_resuelto'; END IF;

  IF _aprobar THEN
    v_estado := 'aprobado';
    -- puntos y stock YA descontados al solicitar; aprobar no los toca.
  ELSE
    v_estado := 'rechazado';
    -- REVERSA: devolver puntos + stock reservados.
    INSERT INTO public.puntos_movimientos (paciente_id, puntos, tipo, motivo)
    VALUES (v_canje.paciente_id, v_canje.costo_puntos, 'canje_reversa', 'Reversa por rechazo de canje');
    UPDATE public.premios SET stock = stock + 1 WHERE id = v_canje.premio_id;
  END IF;

  UPDATE public.canjes
  SET estado = v_estado, resuelto_at = now(), resuelto_por = auth.uid(), nota_resolucion = _nota
  WHERE id = _canje_id;

  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END;
$function$
;


-- ========================= GRANTS: re-afirmar el estado previo =========================
REVOKE ALL     ON FUNCTION public.notificar_pago_resultado(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.notificar_campana_resultado(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.aprobar_solicitud_campana(uuid, text) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.resolver_canje(bigint, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_pago_resultado(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.notificar_campana_resultado(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.aprobar_solicitud_campana(uuid, text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.resolver_canje(bigint, boolean, text) TO authenticated, service_role;

COMMIT;
