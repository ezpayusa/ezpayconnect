-- 198 Monetización proveedor 3ª capa — CAPACIDADES/MÓDULOS por empresa (Modelo A+B)
-- SOLO modelo de datos (4 tablas). Sin RPCs, sin activación, sin front, SIN sembrar datos.
-- Sistema SEPARADO y complementario a planes_base/planes_features (venta/precio) — NO se construye encima.
-- Modelo: capacidades sueltas = la verdad que consultan RPCs/front; tiers = paquetes que al asignarse
-- EXPANDEN capacidades en filas concretas de empresa_capacidades.

-- ============================================================
-- 1) capacidades_catalogo — lista maestra de módulos vendibles
-- ============================================================
CREATE TABLE IF NOT EXISTS public.capacidades_catalogo (
  codigo      text PRIMARY KEY,                       -- código estable que consulta la lógica
  nombre      text NOT NULL,
  descripcion text,
  activo      boolean NOT NULL DEFAULT true,
  orden       integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 2) tiers_catalogo — paquetes con nombre (Oro/Platino/… como DATOS)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tiers_catalogo (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text UNIQUE NOT NULL,
  nombre      text NOT NULL,
  descripcion text,
  orden       integer NOT NULL DEFAULT 0,             -- jerarquía visual
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 3) tier_capacidades — qué capacidades incluye cada tier (N:N)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tier_capacidades (
  tier_id          uuid NOT NULL REFERENCES public.tiers_catalogo(id)        ON DELETE CASCADE,
  capacidad_codigo text NOT NULL REFERENCES public.capacidades_catalogo(codigo) ON DELETE CASCADE,
  PRIMARY KEY (tier_id, capacidad_codigo)
);

-- ============================================================
-- 4) empresa_capacidades — LA VERDAD: qué tiene activo cada empresa
-- ============================================================
CREATE TABLE IF NOT EXISTS public.empresa_capacidades (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid NOT NULL REFERENCES public.empresas_proveedoras(id)   ON DELETE CASCADE,
  capacidad_codigo text NOT NULL REFERENCES public.capacidades_catalogo(codigo) ON DELETE RESTRICT,
  activa           boolean NOT NULL DEFAULT true,
  origen           text NOT NULL DEFAULT 'suelta' CHECK (origen IN ('tier','suelta')),
  tier_id          uuid REFERENCES public.tiers_catalogo(id)                  ON DELETE SET NULL,
  desde            timestamptz NOT NULL DEFAULT now(),
  hasta            timestamptz,                        -- NULL = sin vencimiento; el gate evalúa vencidas
  activada_por     uuid,                               -- super_admin que la activó (auditoría, sin FK formal)
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, capacidad_codigo)                -- a lo sumo 1 fila por (empresa, capacidad) → re-activar = UPDATE
);

-- Índices de lectura frecuente
CREATE INDEX IF NOT EXISTS idx_empresa_capacidades_empresa   ON public.empresa_capacidades(empresa_id);
CREATE INDEX IF NOT EXISTS idx_empresa_capacidades_capacidad ON public.empresa_capacidades(capacidad_codigo);

-- updated_at por trigger (función reutilizable existente en el repo)
DROP TRIGGER IF EXISTS set_updated_at ON public.capacidades_catalogo;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.capacidades_catalogo
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.tiers_catalogo;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tiers_catalogo
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.empresa_capacidades;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.empresa_capacidades
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();

-- ============================================================
-- SEGURIDAD — escritura solo por RPCs DEFINER futuras (owner). Clientes sin escritura.
-- Default privileges otorgan ALL (incl. SELECT) a authenticated al crear la tabla → REVOKE explícito.
-- ============================================================
-- 3 catálogos: lectura pública (no sensible), sin escritura; anon cerrado.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.capacidades_catalogo FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.tiers_catalogo        FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.tier_capacidades       FROM authenticated;
GRANT  SELECT ON public.capacidades_catalogo TO authenticated;
GRANT  SELECT ON public.tiers_catalogo        TO authenticated;
GRANT  SELECT ON public.tier_capacidades      TO authenticated;
REVOKE ALL ON public.capacidades_catalogo FROM anon;
REVOKE ALL ON public.tiers_catalogo        FROM anon;
REVOKE ALL ON public.tier_capacidades      FROM anon;

-- empresa_capacidades: CERRADA a clientes (sensible por empresa). REVOKE ALL también quita el SELECT default.
REVOKE ALL ON public.empresa_capacidades FROM authenticated;
REVOKE ALL ON public.empresa_capacidades FROM anon;

-- RLS baseline (tablas en public expuestas por PostgREST; patrón premios/canjes).
ALTER TABLE public.capacidades_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tiers_catalogo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tier_capacidades     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresa_capacidades  ENABLE ROW LEVEL SECURITY;

-- Catálogos: SELECT para authenticated. empresa_capacidades: SIN policy → cerrada (solo owner/DEFINER).
DROP POLICY IF EXISTS "Authenticated lee capacidades_catalogo" ON public.capacidades_catalogo;
CREATE POLICY "Authenticated lee capacidades_catalogo" ON public.capacidades_catalogo
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated lee tiers_catalogo" ON public.tiers_catalogo;
CREATE POLICY "Authenticated lee tiers_catalogo" ON public.tiers_catalogo
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated lee tier_capacidades" ON public.tier_capacidades;
CREATE POLICY "Authenticated lee tier_capacidades" ON public.tier_capacidades
  FOR SELECT TO authenticated USING (true);
