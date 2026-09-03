-- ============================================================================
-- Migracion 267: gate de pais NULL-safe en las 4 funciones de DINERO
-- ============================================================================
-- Paquete PA-FAILOPEN - LOTE 2. cerrar_liquidacion - marcar_liquidacion_cobrada -
-- liquidar_comision - solicitar_contrato_comision.
--
-- LAS 4 SE VERSIONAN POR PRIMERA VEZ EN GIT CON ESTE COMMIT. No estaban en el repo: vivian solo
-- en supabase/fixes/ y en el objeto vivo. El texto de abajo se capturo de PRODUCCION con
-- pg_get_functiondef() el 2026-09-03 (md5 verificado contra el objeto vivo justo antes de escribir
-- esta migracion: identico byte a byte). TODO lo que no sea la expresion del gate esta TAL CUAL
-- estaba en produccion: firma, volatilidad, SECURITY DEFINER, search_path='', el cuerpo completo,
-- los ERRCODEs PC019-PC024, los mensajes, el FOR UPDATE anti doble-cobro, los LEFT JOIN LATERAL de
-- contrato vigente y la validacion de idempotencia.
--
-- ----------------------------------------------------------------------------
-- QUE SE CIERRA
-- ----------------------------------------------------------------------------
-- El gate trivaluado de la mig 222. Las 4 tienen EXECUTE para `authenticated`, y el conjunto de
-- callers sin fila en `perfiles` NO es marginal: son TODAS las cuentas de proveedor (viven en
-- `cuentas_proveedor`). Para ellas get_auth_user_rol() devuelve NULL, el gate entero evalua a NULL,
-- `IF NOT NULL` no ejecuta la rama y EL RAISE NUNCA CORRE. Consecuencias medidas, no supuestas:
-- marcar_liquidacion_cobrada llega hasta el UPDATE a estado='cobrada'; cerrar_liquidacion inserta la
-- liquidacion y su detalle; solicitar_contrato_comision inserta el contrato; liquidar_comision
-- expone el agregado de comisiones. Es mutacion de dinero por parte de cualquier empleado de
-- farmacia logueado.
--
-- ----------------------------------------------------------------------------
-- RIESGO VERIFICADO ANTES DE APLICAR: CAMBIA EL CAMINO DE super_admin?
-- ----------------------------------------------------------------------------
-- Tres de las cuatro usaban `get_auth_user_rol()='super_admin'` en el primer disyunto, y el helper
-- usa `private.tiene_rol(ARRAY['super_admin'])`. Si tiene_rol leyera otra fuente (un usuario_roles
-- legacy, claims del JWT), el comportamiento de super_admin cambiaria y esto seria una regresion,
-- no un fix. NO cambia, verificado contra el objeto vivo en tres niveles:
--   (a) Estructural: private.tiene_rol -> private.rol_usuario() -> `SELECT rol FROM public.perfiles
--       WHERE id = auth.uid()`. Es LA MISMA fuente que public.get_auth_user_rol().
--   (b) Datos: 28 perfiles vivos, 0 con rol NULL, 0 divergencias entre las dos expresiones.
--   (c) En vivo, impersonando: los 3 super_admin reales dan true por ambos caminos; el admin_pais da
--       false por ambos; y el caller SIN perfil da NULL por el viejo y false por el nuevo - que es
--       exactamente el fail-open que estamos cerrando, la unica diferencia y la deseada.
--
-- ----------------------------------------------------------------------------
-- LO QUE **NO** SE TOCA, A PROPOSITO
-- ----------------------------------------------------------------------------
-- El `IF NOT v_found THEN RAISE 'Empresa no encontrada'` que va DESPUES del gate se conserva, y
-- conserva su ORDEN. El termino `v_found` que vivia DENTRO del gate si queda redundante (sin fila,
-- v_pais es NULL y el helper devuelve false para admin_pais), pero la validacion posterior sigue
-- haciendo falta: es la que distingue "no existe" de "no autorizado" PARA QUIEN SI TIENE ACCESO.
-- Y el orden importa por la regla del proyecto: el gate va ANTES de validar existencia, para no
-- revelar si una empresa existe a alguien que no tiene acceso a ella (mismo criterio que la mig 219).
-- `v_found` sigue declarado y asignado aunque el gate ya no lo consuma: preservacion textual.
--
-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------
-- Se re-afirman al final. CREATE OR REPLACE puede restablecer privilegios por default (toda funcion
-- nueva en public nace con EXECUTE para PUBLIC), y estas 4 mutan dinero: un REPLACE que ensanche el
-- grant en silencio seria peor que el bug que cerramos. Estado previo verificado y preservado:
-- postgres + authenticated + service_role, sin anon, sin PUBLIC. Es la leccion de la mig 266.
--
-- ----------------------------------------------------------------------------
-- CENTINELA
-- ----------------------------------------------------------------------------
-- Las 4 salen de la allowlist del P480 en este mismo commit: 26 -> 22. Y P481 (el probe del probe)
-- apuntaba a cerrar_liquidacion, que se salda aca, asi que se re-apunta a aprobar_solicitud_campana.
-- LA REGLA YA SE CUMPLIO DOS VECES (lote 1 y lote 2): cada lote que salda entradas DEBE re-apuntar
-- P481 a una que siga en rojo, o el probe del probe se pone rojo por su propia premisa.
-- ============================================================================

BEGIN;

-- ========================= 1) cerrar_liquidacion =========================
-- DINERO: INSERT en liquidaciones_comision + liquidacion_dispensaciones (agregado congelado).
-- Gate ANTES:  IF NOT ( get_auth_user_rol()='super_admin'
--                       OR (get_auth_user_rol()='admin_pais' AND v_found AND v_pais IS NOT NULL
--                           AND v_pais = get_auth_user_pais_id()) ) THEN
-- Gate AHORA:  IF NOT private.puede_admin_pais(v_pais) THEN
-- v_pais sale de la EMPRESA (derivado del servidor), no del cliente. Si la empresa no existe,
-- v_pais es NULL: el helper deja pasar a super_admin (que cae en 'Empresa no encontrada', igual que
-- antes) y rechaza al admin_pais con PC019, sin revelar existencia.
CREATE OR REPLACE FUNCTION public.cerrar_liquidacion(p_empresa_id uuid, p_anio integer, p_mes integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_pais uuid; v_found boolean;
  v_desde date; v_hasta date;
  v_tot numeric; v_com numeric; v_n bigint; v_sin numeric;
  v_id uuid;
BEGIN
  -- Deriva país de la empresa (no del cliente).
  SELECT ep.pais_id INTO v_pais FROM public.empresas_proveedoras ep WHERE ep.id = p_empresa_id;
  v_found := FOUND;
  -- AUTHZ (scope de liquidar_comision).
  IF NOT private.puede_admin_pais(v_pais) THEN
    RAISE EXCEPTION 'No autorizado para cerrar liquidación de esta empresa' USING ERRCODE='PC019';
  END IF;
  IF NOT v_found THEN RAISE EXCEPTION 'Empresa no encontrada'; END IF;

  -- Rango del mes.
  v_desde := make_date(p_anio, p_mes, 1);
  v_hasta := (v_desde + interval '1 month' - interval '1 day')::date;

  -- Idempotencia dura (el índice único ya lo impide; esto da mensaje legible).
  IF EXISTS (SELECT 1 FROM public.liquidaciones_comision
             WHERE empresa_id = p_empresa_id AND anio = p_anio AND mes = p_mes) THEN
    RAISE EXCEPTION 'Ya existe liquidación para % %/%', p_empresa_id, p_mes, p_anio USING ERRCODE='PC020';
  END IF;

  -- Agregado (misma fórmula por-dispensación que liquidar_comision).
  SELECT COALESCE(SUM(x.total_dispensado),0)::numeric,
         COALESCE(SUM(x.comision),0)::numeric,
         COUNT(*)::bigint,
         COALESCE(SUM(x.total_dispensado) FILTER (WHERE x.porcentaje_aplicado IS NULL),0)::numeric
    INTO v_tot, v_com, v_n, v_sin
  FROM (
    SELECT d.total_dispensado,
           c.porcentaje_base AS porcentaje_aplicado,
           (d.total_dispensado * COALESCE(c.porcentaje_base,0) / 100.0) AS comision
    FROM public.dispensaciones d
    JOIN public.farmacias f ON f.id = d.farmacia_id
    LEFT JOIN LATERAL (
      SELECT c2.porcentaje_base
      FROM public.contratos_comision c2
      WHERE c2.empresa_id = f.empresa_id AND c2.estado = 'aprobada'
        AND d.fecha_dispensacion::date BETWEEN c2.vigencia_desde
                                       AND COALESCE(c2.vigencia_hasta, 'infinity'::date)
      ORDER BY c2.vigencia_desde DESC LIMIT 1
    ) c ON true
    WHERE f.empresa_id = p_empresa_id
      AND d.estado_dispensacion = 'completada'
      AND d.fecha_dispensacion::date BETWEEN v_desde AND v_hasta
  ) x;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Nada que liquidar para % %/% (sin dispensaciones completadas en el período)',
      p_empresa_id, p_mes, p_anio USING ERRCODE='PC021';
  END IF;

  -- Agregado congelado.
  INSERT INTO public.liquidaciones_comision
    (empresa_id, pais_id, anio, mes, total_dispensado, comision_total, n_dispensaciones,
     monto_sin_contrato, estado, cerrada_por, cerrada_at)
  VALUES
    (p_empresa_id, v_pais, p_anio, p_mes, v_tot, v_com, v_n::int, v_sin, 'pendiente', auth.uid(), now())
  RETURNING id INTO v_id;

  -- Detalle: snapshot por dispensación (misma fórmula).
  INSERT INTO public.liquidacion_dispensaciones
    (liquidacion_id, dispensacion_id, total_dispensado, porcentaje_aplicado, comision)
  SELECT v_id, d.id, d.total_dispensado, c.porcentaje_base,
         (d.total_dispensado * COALESCE(c.porcentaje_base,0) / 100.0)
  FROM public.dispensaciones d
  JOIN public.farmacias f ON f.id = d.farmacia_id
  LEFT JOIN LATERAL (
    SELECT c2.porcentaje_base
    FROM public.contratos_comision c2
    WHERE c2.empresa_id = f.empresa_id AND c2.estado = 'aprobada'
      AND d.fecha_dispensacion::date BETWEEN c2.vigencia_desde
                                     AND COALESCE(c2.vigencia_hasta, 'infinity'::date)
    ORDER BY c2.vigencia_desde DESC LIMIT 1
  ) c ON true
  WHERE f.empresa_id = p_empresa_id
    AND d.estado_dispensacion = 'completada'
    AND d.fecha_dispensacion::date BETWEEN v_desde AND v_hasta;

  RETURN v_id;
END;
$function$;


-- ========================= 2) marcar_liquidacion_cobrada =========================
-- DINERO: UPDATE a estado='cobrada'. Es LA funcion del censo con mutacion de dinero confirmada:
-- con el gate viejo, un caller sin fila en perfiles la llevaba de 'pendiente' a 'cobrada' sin
-- excepcion. El pais sale de la FILA ya cargada con FOR UPDATE (v_l.pais_id), no del cliente.
-- Gate AHORA: IF NOT private.puede_admin_pais(v_l.pais_id) THEN
CREATE OR REPLACE FUNCTION public.marcar_liquidacion_cobrada(p_liquidacion_id uuid, p_metodo_pago text, p_referencia text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_l RECORD;
BEGIN
  -- Cargar la liquidación con lock (evita doble cobro concurrente).
  SELECT * INTO v_l FROM public.liquidaciones_comision WHERE id = p_liquidacion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Liquidación no encontrada' USING ERRCODE='PC022'; END IF;

  -- AUTHZ (mismo scope que cerrar_liquidacion; el país sale de la fila, no del cliente).
  IF NOT private.puede_admin_pais(v_l.pais_id) THEN
    RAISE EXCEPTION 'No autorizado para cobrar liquidación de esta empresa' USING ERRCODE='PC019';
  END IF;

  -- Solo desde 'pendiente' (no re-cobrar ni cobrar una anulada).
  IF v_l.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'La liquidación no está pendiente (estado actual: %)', v_l.estado USING ERRCODE='PC023';
  END IF;

  -- metodo_pago obligatorio (texto libre, sin CHECK en el esquema; registro del cobro).
  IF p_metodo_pago IS NULL OR length(trim(p_metodo_pago)) = 0 THEN
    RAISE EXCEPTION 'El método de pago es obligatorio' USING ERRCODE='PC024';
  END IF;

  UPDATE public.liquidaciones_comision
    SET estado='cobrada', metodo_pago=trim(p_metodo_pago),
        referencia_pago=NULLIF(trim(COALESCE(p_referencia,'')),''), cobrada_at=now()
    WHERE id = p_liquidacion_id;

  RETURN jsonb_build_object('id', p_liquidacion_id, 'estado', 'cobrada', 'cobrada_at', now());
END;
$function$;


-- ========================= 3) liquidar_comision =========================
-- DINERO (lectura): agregado de comisiones por periodo. STABLE, no muta.
-- Gate AHORA: IF NOT private.puede_admin_pais(v_pais) THEN
-- Esta NO tiene el `IF NOT v_found` posterior (nunca lo tuvo): tras el gate va directo al
-- RETURN QUERY. No se agrega: preservacion textual, no es el alcance de este lote.
CREATE OR REPLACE FUNCTION public.liquidar_comision(p_empresa_id uuid, p_desde date, p_hasta date)
 RETURNS TABLE(total_dispensado_periodo numeric, comision_total numeric, n_dispensaciones bigint, n_sin_contrato bigint, monto_sin_contrato numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_pais uuid; v_found boolean;
BEGIN
  -- Deriva país de la empresa (no se recibe del cliente).
  SELECT ep.pais_id INTO v_pais FROM public.empresas_proveedoras ep WHERE ep.id = p_empresa_id;
  v_found := FOUND;
  -- AUTHZ (scope de listar_contratos_comision; agregado => RAISE en no-autorizado). La farmacia NO (eso es C).
  IF NOT private.puede_admin_pais(v_pais) THEN
    RAISE EXCEPTION 'No autorizado para liquidar comisión de esta empresa' USING ERRCODE='PC019';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(SUM(d.total_dispensado), 0)::numeric,
    COALESCE(SUM(d.total_dispensado * COALESCE(c.porcentaje_base,0) / 100.0), 0)::numeric,
    COUNT(*)::bigint,
    COUNT(*) FILTER (WHERE c.porcentaje_base IS NULL)::bigint,
    COALESCE(SUM(d.total_dispensado) FILTER (WHERE c.porcentaje_base IS NULL), 0)::numeric
  FROM public.dispensaciones d
  JOIN public.farmacias f ON f.id = d.farmacia_id
  -- Un contrato por dispensación: el vigente en su fecha (snapshot). LATERAL LIMIT 1 evita fan-out
  -- si hubiera vigencias solapadas (la pieza A las evita, pero esto es defensivo). LEFT: no esconde las sin contrato.
  LEFT JOIN LATERAL (
    SELECT c2.porcentaje_base
    FROM public.contratos_comision c2
    WHERE c2.empresa_id = f.empresa_id
      AND c2.estado = 'aprobada'
      AND d.fecha_dispensacion::date BETWEEN c2.vigencia_desde
                                     AND COALESCE(c2.vigencia_hasta, 'infinity'::date)
    ORDER BY c2.vigencia_desde DESC
    LIMIT 1
  ) c ON true
  WHERE f.empresa_id = p_empresa_id
    AND d.estado_dispensacion = 'completada'
    AND d.fecha_dispensacion::date BETWEEN p_desde AND p_hasta;
END;
$function$;


-- ========================= 4) solicitar_contrato_comision =========================
-- DINERO: INSERT en contratos_comision (define el porcentaje de comision de una cadena).
-- Es la UNICA de las 4 cuyo primer disyunto YA era private.tiene_rol(ARRAY['super_admin']), asi que
-- no corre el riesgo del cambio de camino para super_admin; la rama admin_pais era igual de
-- trivaluada que en las otras tres.
-- Gate AHORA: IF NOT private.puede_admin_pais(v_pais) THEN
CREATE OR REPLACE FUNCTION public.solicitar_contrato_comision(p_empresa_id uuid, p_porcentaje numeric, p_vigencia_desde date, p_vigencia_hasta date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id uuid; v_pais uuid; v_tipo text; v_found boolean;
BEGIN
  -- Deriva pais_id y tipo de la empresa (NO se reciben del cliente: no falsear país).
  SELECT ep.pais_id, ep.tipo INTO v_pais, v_tipo
    FROM public.empresas_proveedoras ep WHERE ep.id = p_empresa_id;
  v_found := FOUND;
  -- AUTHZ (espeja 227): super_admin, o admin_pais SOLO si el país de la empresa = su país.
  IF NOT private.puede_admin_pais(v_pais) THEN
    RAISE EXCEPTION 'No autorizado para solicitar contratos de comisión de esta empresa' USING ERRCODE='PC019';
  END IF;
  IF NOT v_found THEN RAISE EXCEPTION 'Empresa no encontrada'; END IF;
  IF v_tipo <> 'farmacia' THEN
    RAISE EXCEPTION 'Solo empresas tipo farmacia pueden tener contrato de comisión (tipo=%)', v_tipo;
  END IF;
  INSERT INTO public.contratos_comision
    (empresa_id, pais_id, porcentaje_base, vigencia_desde, vigencia_hasta, estado, solicitado_por)
  VALUES
    (p_empresa_id, v_pais, p_porcentaje, p_vigencia_desde, p_vigencia_hasta, 'pendiente', auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;


-- ========================= GRANTS: re-afirmar el estado previo =========================
-- Explicito y en un solo lugar. Si un CREATE OR REPLACE de arriba ensancho privilegios por default,
-- esto lo revierte; si no, es inerte. En funciones que mutan dinero no se deja al azar.
REVOKE ALL     ON FUNCTION public.cerrar_liquidacion(uuid, integer, integer)             FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.marcar_liquidacion_cobrada(uuid, text, text)           FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.liquidar_comision(uuid, date, date)                    FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.solicitar_contrato_comision(uuid, numeric, date, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cerrar_liquidacion(uuid, integer, integer)             TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.marcar_liquidacion_cobrada(uuid, text, text)           TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.liquidar_comision(uuid, date, date)                    TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.solicitar_contrato_comision(uuid, numeric, date, date) TO authenticated, service_role;

COMMIT;

-- Verificacion estructural (DESPUES del COMMIT): las 4 con prosecdef=t, anon=false,
-- gate_migrado=true y restos_viejos=false. Ver el paso estructural del protocolo.
