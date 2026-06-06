-- =============================================
-- MIGRACIÓN 016: Ubicaciones de médicos por proveedor
-- =============================================
-- Cada proveedor gestiona sus propias direcciones de visita para cada médico.
-- Un médico puede tener diferentes consultorios según el proveedor que lo visite.

CREATE TABLE IF NOT EXISTS public.ubicaciones_medico_proveedor (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES public.empresas_proveedoras(id) ON DELETE CASCADE,
  medico_id UUID NOT NULL REFERENCES public.perfiles(id) ON DELETE CASCADE,
  direccion TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  notas TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(empresa_id, medico_id)
);

COMMENT ON TABLE public.ubicaciones_medico_proveedor IS 'Direcciones de consultorio de médicos gestionadas por cada empresa proveedora';

-- RLS: solo la empresa dueña puede ver/modificar sus ubicaciones
-- NOTA: cuentas_proveedor usa 'id' (referencia a auth.users) y 'activo' (boolean), no 'usuario_id' ni 'estado'
ALTER TABLE public.ubicaciones_medico_proveedor ENABLE ROW LEVEL SECURITY;

CREATE POLICY ubicaciones_select ON public.ubicaciones_medico_proveedor
  FOR SELECT USING (empresa_id IN (
    SELECT empresa_id FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true
  ));

CREATE POLICY ubicaciones_insert ON public.ubicaciones_medico_proveedor
  FOR INSERT WITH CHECK (empresa_id IN (
    SELECT empresa_id FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true AND rol_en_empresa IN ('admin', 'editor')
  ));

CREATE POLICY ubicaciones_update ON public.ubicaciones_medico_proveedor
  FOR UPDATE USING (empresa_id IN (
    SELECT empresa_id FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true AND rol_en_empresa IN ('admin', 'editor')
  ));

CREATE POLICY ubicaciones_delete ON public.ubicaciones_medico_proveedor
  FOR DELETE USING (empresa_id IN (
    SELECT empresa_id FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true AND rol_en_empresa IN ('admin', 'editor')
  ));

-- Índice para lookups rápidos
CREATE INDEX IF NOT EXISTS idx_ubicaciones_empresa_medico ON public.ubicaciones_medico_proveedor(empresa_id, medico_id);

-- Función RPC para obtener ubicaciones con datos del médico (bypassea RLS de perfiles)
CREATE OR REPLACE FUNCTION public.get_ubicaciones_con_medico(p_empresa_id UUID)
RETURNS TABLE (
  ubicacion_id UUID,
  medico_id UUID,
  nombre_completo TEXT,
  email TEXT,
  direccion TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  notas TEXT,
  updated_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT 
    u.id AS ubicacion_id,
    u.medico_id,
    p.nombre_completo,
    p.email,
    u.direccion,
    u.lat,
    u.lng,
    u.notas,
    u.updated_at
  FROM public.ubicaciones_medico_proveedor u
  JOIN public.perfiles p ON p.id = u.medico_id
  WHERE u.empresa_id = p_empresa_id;
$$;

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at_ubicaciones ON public.ubicaciones_medico_proveedor;
CREATE TRIGGER set_updated_at_ubicaciones
BEFORE UPDATE ON public.ubicaciones_medico_proveedor
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_updated_at();
