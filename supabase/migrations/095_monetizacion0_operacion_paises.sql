-- ============================================================
-- MONETIZACIÓN-0 / G1 · Operación M:N empresa↔país (INERTE) — base común publicidad+visitas
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first (P199–P202). Aditivo. NO se cablea el helper a
-- ninguna policy/RPC viva (inerte, como país-0/C.1). Operación la setea super_admin (no
-- self-service). Lectura directa por proveedor/anon = 0; el consumo real será vía el helper.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.empresa_paises_operacion (
  empresa_id uuid NOT NULL REFERENCES public.empresas_proveedoras(id) ON DELETE CASCADE,
  pais_id    uuid NOT NULL REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  activo     boolean NOT NULL DEFAULT true,
  PRIMARY KEY (empresa_id, pais_id)
);
ALTER TABLE public.empresa_paises_operacion ENABLE ROW LEVEL SECURITY;

-- Policy ÚNICA: super_admin gestiona. SIN policy para proveedor/anon → lectura directa = 0.
DROP POLICY IF EXISTS epo_superadmin_all ON public.empresa_paises_operacion;
CREATE POLICY epo_superadmin_all ON public.empresa_paises_operacion
  FOR ALL TO authenticated
  USING      (COALESCE(private.tiene_rol(ARRAY['super_admin']), false))
  WITH CHECK (COALESCE(private.tiene_rol(ARRAY['super_admin']), false));

-- Helper DEFINER (consumo real). fail-closed: sin fila/activo=false/p_id NULL → false.
CREATE OR REPLACE FUNCTION private.empresa_opera_en_pais(p_empresa_id uuid, p_pais_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.empresa_paises_operacion o
    WHERE o.empresa_id = p_empresa_id AND o.pais_id = p_pais_id AND o.activo
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.empresa_opera_en_pais(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.empresa_opera_en_pais(uuid, uuid) TO authenticated;

-- Seed: operación mínima = sede actual de cada empresa.
INSERT INTO public.empresa_paises_operacion (empresa_id, pais_id, activo)
SELECT id, pais_id, true FROM public.empresas_proveedoras WHERE pais_id IS NOT NULL
ON CONFLICT DO NOTHING;
