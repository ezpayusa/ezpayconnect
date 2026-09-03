-- ============================================================================
-- Migración 266: metricas_campana_pais — cerrar el vector anónimo + gate NULL-safe
-- ============================================================================
-- Paquete PA-FAILOPEN · LOTE 1. Primera función del censo que se migra a los helpers de la 265.
--
-- ⚠️ ESTA FUNCIÓN NO ESTABA VERSIONADA EN EL REPO. Vivía solo en supabase/fixes/ y en el objeto
-- vivo. Este archivo es su PRIMERA versión en git: el cuerpo de abajo es el texto exacto que
-- devolvió pg_get_functiondef() contra prod el 2026-09-03, con UN solo cambio — la expresión del IF.
-- Firma, RETURNS TABLE, STABLE, SECURITY DEFINER, search_path='', el RETURN QUERY completo, el
-- ERRCODE 42501 y el mensaje 'no_autorizado' se preservan textualmente.
--
-- ----------------------------------------------------------------------------
-- EL VECTOR QUE CIERRA (verificado en vivo, no teórico)
-- ----------------------------------------------------------------------------
-- Es la ÚNICA función del censo de 27 alcanzable SIN SESIÓN. Dos defectos que se componen:
--
--   (1) GRANT: tenía EXECUTE otorgado a `anon`.
--   (2) GATE: el gate trivaluado de la mig 222. Sin sesión auth.uid() es NULL, entonces
--       get_auth_user_rol() devuelve NULL, y NULL='super_admin' OR (NULL='admin_pais' AND ...)
--       evalúa a NULL. `NOT NULL` = NULL. `IF NULL THEN` no ejecuta la rama ⇒ el RAISE NUNCA CORRE.
--
-- Comprobado contra prod ANTES de esta migración, con la anon key y sin ningún Authorization de
-- usuario:  POST /rest/v1/rpc/metricas_campana_pais → HTTP 200, **14 filas**. Títulos de campaña,
-- URLs de imagen, fechas, impresiones, clicks, usuarios únicos y el desglose por empresa dueña, de
-- cualquier país, a cualquiera que tenga la anon key (que es pública por diseño: viaja en el bundle).
--
-- ----------------------------------------------------------------------------
-- POR QUÉ EL REVOKE VA ANTES *Y* DESPUÉS
-- ----------------------------------------------------------------------------
-- ANTES y solo: es la mitad barata y la que cierra el vector sin sesión. Si el CREATE OR REPLACE de
-- abajo fallara por cualquier motivo, la transacción entera revierte — pero el orden deja explícito
-- que el REVOKE no depende de nada del resto, y en una aplicación por partes es lo primero que entra.
--
-- DESPUÉS: porque `CREATE OR REPLACE FUNCTION` puede restablecer privilegios por default. En este
-- proyecto TODA función nueva en public nace con EXECUTE para PUBLIC (default privileges — la misma
-- lección que la de los grants de tablas), así que un REPLACE que no re-revoca puede reabrir
-- exactamente el agujero que acabamos de cerrar. Re-aplicarlo es barato e idempotente.
-- El paso estructural de verificación DEBE mirar el grant de anon AL FINAL DE TODO, no en el medio.
--
-- ----------------------------------------------------------------------------
-- ALLOWLIST DEL CENTINELA
-- ----------------------------------------------------------------------------
-- Esta es la PRIMERA entrada que se salda de las 27 del centinela P480. La entrada
-- 'public.metricas_campana_pais' se borra de la allowlist en el MISMO commit que esta migración:
-- el centinela debe quedar VERDE con 26, no con 27. Si quedara en la lista, P480 lo reportaría como
-- "deuda saldada, quitar de la allowlist" — que es el aviso, no un rojo.
-- ============================================================================

BEGIN;

-- ========================= 1) REVOKE — cierra el vector sin sesión =========================
REVOKE EXECUTE ON FUNCTION public.metricas_campana_pais(uuid) FROM PUBLIC, anon;


-- ========================= 2) Gate migrado a private.puede_admin_pais =========================
-- ÚNICO cambio respecto del texto vivo: la expresión del IF.
--   ANTES:  IF NOT ( public.get_auth_user_rol() = 'super_admin'
--                    OR ( public.get_auth_user_rol() = 'admin_pais'
--                         AND public.get_auth_user_pais_id() = p_pais_id ) ) THEN
--   AHORA:  IF NOT private.puede_admin_pais(p_pais_id) THEN
-- Mismo significado para todo caller CON identidad; para el caller sin fila en perfiles el helper
-- devuelve false (no NULL) y el RAISE por fin corre. El helper ya incluye la rama super_admin vía
-- private.tiene_rol(p_roles) con el default ARRAY['super_admin'].
CREATE OR REPLACE FUNCTION public.metricas_campana_pais(p_pais_id uuid)
 RETURNS TABLE(campana_id integer, titulo text, imagen_url text, fecha_inicio date, fecha_fin date, impresiones bigint, clicks bigint, usuarios_unicos bigint, empresa_id uuid, empresa_nombre text, empresa_tipo text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin,
           count(cm.id) FILTER (WHERE cm.clickeado = false) AS impresiones,
           count(cm.id) FILTER (WHERE cm.clickeado = true)  AS clicks,
           count(DISTINCT COALESCE(cm.perfil_id::text, cm.paciente_id::text)) AS usuarios_unicos,
           cp.empresa_id, ep.nombre_empresa, ep.tipo
    FROM public.campanas_publicitarias cp
    LEFT JOIN public.campana_metricas cm ON cm.campana_id = cp.id
    LEFT JOIN public.empresas_proveedoras ep ON ep.id = cp.empresa_id
    WHERE cp.pais_id = p_pais_id
    GROUP BY cp.id, cp.titulo, cp.imagen_url, cp.fecha_inicio, cp.fecha_fin, cp.empresa_id, ep.nombre_empresa, ep.tipo
    ORDER BY ep.nombre_empresa NULLS FIRST, cp.fecha_inicio DESC;
END;
$function$;


-- ========================= 3) REVOKE otra vez — el CREATE OR REPLACE puede haber reabierto =====
REVOKE EXECUTE ON FUNCTION public.metricas_campana_pais(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.metricas_campana_pais(uuid) TO authenticated, service_role;

COMMIT;

-- Verificación estructural (correr DESPUÉS del COMMIT, no en el medio):
--   SELECT has_function_privilege('anon','public.metricas_campana_pais(uuid)','EXECUTE') AS anon,
--          has_function_privilege('authenticated','public.metricas_campana_pais(uuid)','EXECUTE') AS auth;
--   esperado: anon=false, auth=true
