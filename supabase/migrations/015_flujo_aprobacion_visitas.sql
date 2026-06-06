-- =============================================
-- MIGRACIÓN 015: Flujo de Aprobación de Visitas
-- =============================================

-- 1. Añadir campos de geolocalización a perfiles (médicos) - UNA COLUMNA POR LÍNEA
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS direccion_consultorio TEXT;
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;

COMMENT ON COLUMN public.perfiles.direccion_consultorio IS 'Dirección del consultorio para rutas del visitador';
COMMENT ON COLUMN public.perfiles.lat IS 'Latitud del consultorio';
COMMENT ON COLUMN public.perfiles.lng IS 'Longitud del consultorio';

-- 2. Añadir campos de flujo de aprobación a visitas_agendadas
ALTER TABLE public.visitas_agendadas ADD COLUMN IF NOT EXISTS propuesta_por UUID REFERENCES public.cuentas_proveedor(id);
ALTER TABLE public.visitas_agendadas ADD COLUMN IF NOT EXISTS aprobada_por UUID REFERENCES public.cuentas_proveedor(id);
ALTER TABLE public.visitas_agendadas ADD COLUMN IF NOT EXISTS fecha_aprobacion TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.visitas_agendadas ADD COLUMN IF NOT EXISTS comentario_admin TEXT;

-- 3. Actualizar restricción de CHECK para incluir nuevos estados
ALTER TABLE public.visitas_agendadas DROP CONSTRAINT IF EXISTS visitas_agendadas_estado_check;
ALTER TABLE public.visitas_agendadas ADD CONSTRAINT visitas_agendadas_estado_check
  CHECK (estado IN ('propuesta', 'aprobada', 'confirmada', 'rechazada', 'pendiente', 'completada', 'cancelada', 'no_asistio'));

-- 4. Función RPC para administrar visita (aprobar/rechazar/modificar)
CREATE OR REPLACE FUNCTION public.administrar_visita(
  p_visita_id UUID,
  p_accion TEXT,
  p_nueva_fecha DATE DEFAULT NULL,
  p_nueva_hora_inicio TEXT DEFAULT NULL,
  p_nueva_hora_fin TEXT DEFAULT NULL,
  p_comentario TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  IF p_accion = 'aprobar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'confirmada',
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada');
  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'rechazada',
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'rechazada');
  ELSIF p_accion = 'modificar' THEN
    UPDATE public.visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin, hora_fin),
        estado = 'confirmada',
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada', 'modificado', true);
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;

  RETURN v_result;
END;
$$;

-- 5. Trigger para forzar estado propuesta en inserts por visitadores
CREATE OR REPLACE FUNCTION public.set_default_estado_propuesta()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor 
    WHERE id = NEW.cuenta_proveedor_id 
    AND rol_en_empresa IN ('admin', 'editor')
  ) THEN
    NEW.estado := 'propuesta';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_forzar_estado_propuesta ON public.visitas_agendadas;
CREATE TRIGGER trigger_forzar_estado_propuesta
BEFORE INSERT ON public.visitas_agendadas
FOR EACH ROW
EXECUTE FUNCTION public.set_default_estado_propuesta();

-- 6. Índices para rendimiento
CREATE INDEX IF NOT EXISTS idx_visitas_estado ON public.visitas_agendadas(estado);
CREATE INDEX IF NOT EXISTS idx_visitas_cuenta ON public.visitas_agendadas(cuenta_proveedor_id);
CREATE INDEX IF NOT EXISTS idx_visitas_fecha_estado ON public.visitas_agendadas(fecha_visita, estado);
CREATE INDEX IF NOT EXISTS idx_perfiles_lat_lng ON public.perfiles(lat, lng);
