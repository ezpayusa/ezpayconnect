-- ============================================================================
-- Migracion 269: gate de pais NULL-safe en las 6 RPCs de LECTURA
-- ============================================================================
-- Paquete PA-FAILOPEN - LOTE 4.
--   listar_canjes_pendientes - listar_propuestas_especialidad - listar_solicitudes_personalizacion
--   listar_capacidades_pais - listar_tiers_pais - obtener_resumen_pais
--
-- Texto capturado del objeto vivo con pg_get_functiondef() (md5 verificado) y migracion GENERADA
-- por script desde ese texto. Las 6 ya estaban versionadas (migs 218, 221, 227); no hay primera
-- version en git aca.
--
-- ============================================================================
-- EL "BUG B" NO EXISTE, Y LA FUGA ESTA EN LAS OTRAS TRES
-- ============================================================================
-- La hipotesis de trabajo era que los tres listar_* de la mig 221 gatean por rol SIN termino de
-- pais y que el cuerpo tampoco filtra, con lo cual un admin_pais legitimo veria los canjes y
-- propuestas de TODOS los paises. SE VERIFICO CONTRA EL CUERPO VIVO Y ES FALSO: los tres YA
-- filtran por pais en el WHERE.
--
--   listar_canjes_pendientes            ... AND (get_auth_user_rol() = 'super_admin'
--                                                OR private.pais_de_canje(c.id) = get_auth_user_pais_id())
--   listar_propuestas_especialidad      ... AND (get_auth_user_rol() = 'super_admin'
--                                                OR private.pais_de_propuesta_especialidad(ep.id) = get_auth_user_pais_id())
--   listar_solicitudes_personalizacion  ... AND (get_auth_user_rol() = 'super_admin'
--                                                OR private.pais_de_solicitud_personalizacion(s.id) = get_auth_user_pais_id())
--
-- Y esos WHERE son FAIL-CLOSED: en un WHERE, NULL no es TRUE, asi que la fila se descarta. Para un
-- caller sin fila en perfiles el gate falla abierto (no dispara el RAISE) pero el cuerpo devuelve
-- CERO FILAS. El defecto de esas tres es un RAISE que no corre, no una fuga de datos.
--
-- LA FUGA REAL ESTA EN LAS TRES QUE PARECIAN SEGURAS. listar_capacidades_pais, listar_tiers_pais y
-- obtener_resumen_pais reciben p_pais_id, y su cuerpo filtra POR EL PARAMETRO, no por el caller:
--     WHERE c.pais_id = p_pais_id OR c.pais_id IS NULL      -- capacidades
--     WHERE t.pais_id = p_pais_id OR t.pais_id IS NULL      -- tiers
--     WHERE id = p_pais_id                                  -- resumen
-- El unico control que ata el parametro al caller es el gate, y el gate falla abierto. Un caller sin
-- perfil pasa y lee el catalogo de capacidades, el de tiers y el resumen DE CUALQUIER PAIS que
-- elija pasar por parametro. Es exactamente la forma inversa a la que se buscaba.
--
-- CONSECUENCIA PARA ESTA MIGRACION: NO se toca ningun WHERE. El unico cambio es la expresion del
-- gate, igual que en los lotes 1-3. La regla del proyecto (en una funcion que devuelve N filas el
-- confinamiento va en el WHERE) YA SE CUMPLE en las tres que la necesitan; en las otras tres el
-- confinamiento correcto es el gate, porque el parametro ES el scope.
--
-- ============================================================================
-- SIN CAMBIO DE COMPORTAMIENTO PARA NADIE LEGITIMO
-- ============================================================================
-- Como no se toca ningun WHERE, un admin_pais legitimo ve exactamente lo mismo que antes (su pais,
-- que es lo que ya veia) y super_admin sigue viendo todo. El riesgo de "filtro de mas" que
-- justificaria censar la UI no se materializa: no hay filtro nuevo.
-- Censo de consumidores hecho igual: las 6 se consumen SOLO desde src/pages/admin-ezpay/
-- (CanjesPendientesPage, EspecialidadesPropuestasPage, SolicitudesPersonalizacionPage y
-- CapacidadesTiersPais, que recibe paisId como prop derivada de la ruta). Cero edge functions.
-- Ninguna depende de listar cross-pais.
--
-- ============================================================================
-- DOS TRADUCCIONES
-- ============================================================================
-- (a) Gate por ROL, sin pais que comparar (los tres de la 221) -> private.es_admin_pais().
--     Es la mitad sin-parametro del helper, creada en la 265 justo para estos casos:
--       ANTES: COALESCE(private.tiene_rol(ARRAY['super_admin']), false) OR get_auth_user_rol() = 'admin_pais'
--       AHORA: private.tiene_rol(ARRAY['super_admin']) OR private.es_admin_pais()
--     tiene_rol ya devuelve boolean estricto, asi que el COALESCE externo era redundante; el
--     termino que fallaba abierto era el de la derecha, y es el que ahora es NULL-safe.
--     En listar_solicitudes_personalizacion el primer disyunto era un EXISTS sobre perfiles escrito
--     a mano; se unifica a private.tiene_rol (misma fuente: perfiles.rol de auth.uid(), y ambos
--     corren como el owner por ser DEFINER, asi que la RLS no cambia el resultado).
--
-- (b) Gate con pais parametrizado (los tres con p_pais_id) -> private.puede_admin_pais(p_pais_id).
--
-- ============================================================================
-- LOS get_auth_user_* QUE QUEDAN, Y POR QUE
-- ============================================================================
-- Los tres de la 221 conservan get_auth_user_rol()/get_auth_user_pais_id() DENTRO DEL WHERE. Se
-- dejan a proposito: ahi son fail-closed, cambiarlos no aporta seguridad y tocar la expresion que
-- decide que filas ve cada quien es un cambio que merece su propia justificacion, no un arrastre.
-- El centinela P480 no los marca porque solo mira gates (IF ... THEN ... RAISE), no cuerpos.
--
-- Grants re-afirmados al final. CENTINELA: allowlist 15 -> 9.
-- ============================================================================

BEGIN;

-- ========================= 1) listar_canjes_pendientes (mig 221) =========================
-- Gate por rol; el confinamiento por pais YA vive en el WHERE (fail-closed) y no se toca.
-- Gate AHORA: IF NOT (private.tiene_rol(ARRAY['super_admin']) OR private.es_admin_pais()) THEN
CREATE OR REPLACE FUNCTION public.listar_canjes_pendientes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT (private.tiene_rol(ARRAY['super_admin']) OR private.es_admin_pais()) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'canje_id', c.id, 'solicitado_at', c.solicitado_at, 'costo_puntos', c.costo_puntos,
             'paciente_id', c.paciente_id, 'paciente_nombre', p.nombre || ' ' || COALESCE(p.apellido, ''),
             'premio_id', c.premio_id, 'premio_nombre', pr.nombre, 'premio_tipo', pr.tipo
           ) ORDER BY c.solicitado_at)
    FROM public.canjes c
    JOIN public.pacientes p  ON p.id  = c.paciente_id
    JOIN public.premios   pr ON pr.id = c.premio_id
    WHERE c.estado = 'pendiente'
      AND (public.get_auth_user_rol() = 'super_admin'
           OR private.pais_de_canje(c.id) = public.get_auth_user_pais_id())
  ), '[]'::jsonb);
END;
$function$
;


-- ========================= 2) listar_propuestas_especialidad (mig 221) =========================
-- Idem: el WHERE ya acota por private.pais_de_propuesta_especialidad(ep.id).
CREATE OR REPLACE FUNCTION public.listar_propuestas_especialidad(p_estado text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (private.tiene_rol(ARRAY['super_admin']) OR private.es_admin_pais()) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id',                 ep.id,
             'nombre_propuesto',   ep.nombre_propuesto,
             'estado',             ep.estado,
             'created_at',         ep.created_at,
             'resolved_at',        ep.resolved_at,
             'resolved_by',        ep.resolved_by,
             'medico_id',          ep.medico_id,
             'medico_nombre',      m.nombre_completo,
             'resolved_by_nombre', rp.nombre_completo
           )
           ORDER BY (ep.estado = 'pendiente') DESC, ep.created_at DESC)
    FROM public.especialidades_propuestas ep
    LEFT JOIN public.medicos  m  ON m.id  = ep.medico_id
    LEFT JOIN public.perfiles rp ON rp.id = ep.resolved_by       -- super_admin que resolvió (si aplica)
    WHERE (p_estado IS NULL OR ep.estado = p_estado)
      AND (get_auth_user_rol() = 'super_admin'
           OR private.pais_de_propuesta_especialidad(ep.id) = get_auth_user_pais_id())
  ), '[]'::jsonb);
END;
$function$
;


-- ========================= 3) listar_solicitudes_personalizacion (mig 221) =========================
-- Idem. Ademas el primer disyunto era un EXISTS sobre perfiles escrito a mano: se unifica a
-- private.tiene_rol, que lee la misma fuente y corre con los mismos privilegios (DEFINER).
CREATE OR REPLACE FUNCTION public.listar_solicitudes_personalizacion(p_estado text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, tenant_tipo text, tenant_id uuid, tenant_nombre text, estado text, logo_url text, color_primario text, color_secundario text, color_fondo text, motivo_rechazo text, solicitante_nombre text, created_at timestamp with time zone, revisado_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Gate: super_admin (global) o admin_pais (acotado en el WHERE). PT002 = no_autorizado del listador.
  IF NOT (private.tiene_rol(ARRAY['super_admin']) OR private.es_admin_pais()) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PT002';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.tenant_tipo,
    s.tenant_id,
    CASE s.tenant_tipo
      WHEN 'clinica'            THEN (SELECT c.nombre         FROM public.clinicas c              WHERE c.id = s.tenant_id)
      WHEN 'empresa_proveedora' THEN (SELECT e.nombre_empresa FROM public.empresas_proveedoras e  WHERE e.id = s.tenant_id)
    END AS tenant_nombre,
    s.estado,
    s.logo_url,
    s.color_primario,
    s.color_secundario,
    s.color_fondo,
    s.motivo_rechazo,
    COALESCE(
      (SELECT pf.nombre_completo FROM public.perfiles pf          WHERE pf.id = s.solicitado_por),
      (SELECT cp.nombre_completo FROM public.cuentas_proveedor cp WHERE cp.id = s.solicitado_por),
      'Desconocido'
    ) AS solicitante_nombre,
    s.created_at,
    s.revisado_at
  FROM public.solicitudes_personalizacion s
  WHERE (p_estado IS NULL OR s.estado = p_estado)
    AND (get_auth_user_rol() = 'super_admin'
         OR private.pais_de_solicitud_personalizacion(s.id) = get_auth_user_pais_id())
  ORDER BY s.created_at DESC;
END;
$function$
;


-- ========================= 4) listar_capacidades_pais (mig 218) =========================
-- FUGA REAL: el cuerpo filtra por el PARAMETRO (WHERE c.pais_id = p_pais_id OR c.pais_id IS NULL),
-- no por el caller. El gate es el unico control que ata el parametro a quien llama, y fallaba
-- abierto: un caller sin perfil leia el catalogo de capacidades de cualquier pais.
-- Gate AHORA: IF NOT private.puede_admin_pais(p_pais_id) THEN
CREATE OR REPLACE FUNCTION public.listar_capacidades_pais(p_pais_id uuid)
 RETURNS TABLE(codigo text, nombre text, descripcion text, orden integer, activo boolean, pais_id uuid, es_global boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado para ver capacidades de este país' USING ERRCODE='PC019';
  END IF;
  RETURN QUERY
  SELECT c.codigo, c.nombre, c.descripcion, c.orden, c.activo, c.pais_id, (c.pais_id IS NULL)
  FROM capacidades_catalogo c
  WHERE c.pais_id = p_pais_id OR c.pais_id IS NULL
  ORDER BY c.pais_id NULLS FIRST, c.orden, c.codigo;
END;
$function$
;


-- ========================= 5) listar_tiers_pais (mig 218) =========================
-- Misma fuga y misma traduccion que listar_capacidades_pais.
CREATE OR REPLACE FUNCTION public.listar_tiers_pais(p_pais_id uuid)
 RETURNS TABLE(id uuid, codigo text, nombre text, descripcion text, orden integer, activo boolean, pais_id uuid, es_global boolean, capacidades text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado para ver tiers de este país' USING ERRCODE='PC019';
  END IF;
  RETURN QUERY
  SELECT t.id, t.codigo, t.nombre, t.descripcion, t.orden, t.activo, t.pais_id, (t.pais_id IS NULL),
         COALESCE(ARRAY(SELECT tc.capacidad_codigo FROM tier_capacidades tc WHERE tc.tier_id = t.id ORDER BY tc.capacidad_codigo), '{}'::text[])
  FROM tiers_catalogo t
  WHERE t.pais_id = p_pais_id OR t.pais_id IS NULL
  ORDER BY t.pais_id NULLS FIRST, t.orden, t.codigo;
END;
$function$
;


-- ========================= 6) obtener_resumen_pais (mig 218) =========================
-- Misma fuga: WHERE id = p_pais_id. Devuelve nombre y techo_cortesia_visitas del pais elegido.
CREATE OR REPLACE FUNCTION public.obtener_resumen_pais(p_pais_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT private.puede_admin_pais(p_pais_id) THEN
    RAISE EXCEPTION 'No autorizado para ver el resumen de este país' USING ERRCODE='PC019';
  END IF;
  SELECT jsonb_build_object('pais_id', id, 'nombre', nombre, 'techo_cortesia_visitas', techo_cortesia_visitas)
    INTO v FROM configuracion_pais WHERE id = p_pais_id;
  IF v IS NULL THEN RETURN jsonb_build_object('error','País no encontrado'); END IF;
  RETURN v;
END;
$function$
;


-- ========================= GRANTS: re-afirmar el estado previo =========================
REVOKE ALL     ON FUNCTION public.listar_canjes_pendientes() FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.listar_propuestas_especialidad(text) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.listar_solicitudes_personalizacion(text) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.listar_capacidades_pais(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.listar_tiers_pais(uuid) FROM PUBLIC, anon;
REVOKE ALL     ON FUNCTION public.obtener_resumen_pais(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_canjes_pendientes() TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.listar_propuestas_especialidad(text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.listar_solicitudes_personalizacion(text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.listar_capacidades_pais(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.listar_tiers_pais(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.obtener_resumen_pais(uuid) TO authenticated, service_role;

COMMIT;
