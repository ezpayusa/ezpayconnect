-- ============================================================================
-- Migración 218: pais_id en capacidades_catalogo/tiers_catalogo + RPCs de creación
--                (crear_capacidad_pais / crear_tier_pais) con gate super_admin O admin_pais
-- ============================================================================
-- CONTEXTO: hasta hoy NINGUNA RPC crea filas en capacidades_catalogo/tiers_catalogo — el catálogo
-- se puebla solo por migración directa (mig 200 sembró las 4 capacidades; tiers_catalogo sigue
-- vacío). Las 5 RPCs de mig 200 solo LEEN el catálogo para validar que un código/id exista. No hay
-- policy de escritura en estas tablas (RLS on + solo SELECT authenticated → INSERT/UPDATE/DELETE
-- denegado por defecto); estas 2 RPCs SECURITY DEFINER son el ÚNICO camino de escritura (mismo
-- patrón que las RPCs de mig 200 sobre empresa_capacidades).
--
-- QUÉ HABILITA (decisión de negocio confirmada): admin_pais puede crear tiers/capacidades propias de
-- SU país; el maestro (super_admin) crea las globales o de cualquier país. Convención de pais_id:
--   NULL   = GLOBAL (usable/visible por cualquier país; solo super_admin puede crear con NULL)
--   <uuid> = propio de ese país (admin_pais SOLO puede crear con su propio pais_id, nunca NULL/otro)
--
-- REGLA cross-país en tier_capacidades: un tier de país X solo puede vincular capacidades GLOBALES
-- (pais_id NULL) o del MISMO país X — nunca capacidades de otro país. Un tier GLOBAL (pais_id NULL)
-- solo puede vincular capacidades GLOBALES. La validación de capacidades se hace ANTES del INSERT del
-- tier, así que si alguna no cumple la función retorna el error sin haber insertado nada (atómico,
-- sin necesidad de rollback explícito).
--
-- La RLS SELECT (authenticated USING true) NO se toca: el catálogo entero se puede LEER por cualquiera
-- (es metadata, no datos sensibles de empresa), incluidos tiers/capacidades de otros países.
-- ============================================================================

BEGIN;

-- ========================= PASO 1: columna pais_id + índice =========================
ALTER TABLE public.capacidades_catalogo
  ADD COLUMN pais_id uuid REFERENCES public.configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_capacidades_catalogo_pais_id ON public.capacidades_catalogo(pais_id);

ALTER TABLE public.tiers_catalogo
  ADD COLUMN pais_id uuid REFERENCES public.configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_tiers_catalogo_pais_id ON public.tiers_catalogo(pais_id);


-- ========================= PASO 2: crear_capacidad_pais =========================
CREATE OR REPLACE FUNCTION public.crear_capacidad_pais(
  p_codigo      text,
  p_nombre      text,
  p_descripcion text DEFAULT NULL,
  p_pais_id     uuid DEFAULT NULL,   -- NULL = capacidad GLOBAL (solo super_admin puede crear con NULL)
  p_orden       int  DEFAULT 100
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
BEGIN
  -- Gate: super_admin (cualquier país o NULL global) O admin_pais SOLO su propio país (nunca NULL/otro).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (get_auth_user_rol() = 'admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id())
  ) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin (cualquier país) o admin_pais de su propio país puede crear capacidades';
  END IF;

  IF EXISTS (SELECT 1 FROM capacidades_catalogo WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('error', 'Ya existe una capacidad con ese código');
  END IF;

  INSERT INTO capacidades_catalogo (codigo, nombre, descripcion, pais_id, orden, activo)
  VALUES (p_codigo, p_nombre, p_descripcion, p_pais_id, p_orden, true);

  RETURN jsonb_build_object('success', true, 'codigo', p_codigo);
END;
$function$;

REVOKE ALL     ON FUNCTION public.crear_capacidad_pais(text, text, text, uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_capacidad_pais(text, text, text, uuid, integer) TO authenticated, service_role;


-- ========================= PASO 3: crear_tier_pais =========================
CREATE OR REPLACE FUNCTION public.crear_tier_pais(
  p_codigo       text,
  p_nombre       text,
  p_descripcion  text   DEFAULT NULL,
  p_pais_id      uuid   DEFAULT NULL,   -- NULL = tier GLOBAL (solo super_admin)
  p_orden        int    DEFAULT 100,
  p_capacidades  text[] DEFAULT NULL    -- códigos de capacidades a vincular (opcional)
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_tier_id uuid;
  v_caps    text[];
  v_cod     text;
  v_cap_pais uuid;
  v_count   int := 0;
BEGIN
  -- Gate idéntico a crear_capacidad_pais.
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (get_auth_user_rol() = 'admin_pais' AND p_pais_id IS NOT NULL AND p_pais_id = get_auth_user_pais_id())
  ) THEN
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
$function$;

REVOKE ALL     ON FUNCTION public.crear_tier_pais(text, text, text, uuid, integer, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_tier_pais(text, text, text, uuid, integer, text[]) TO authenticated, service_role;

COMMIT;
