-- ============================================
-- Migración 015: Sistema de visitadores médicos + roles + flujo aprobación
-- ============================================

-- 1. Actualizar enum de estados de visita (agregar propuesta, aprobada, rechazada)
-- PostgreSQL no permite ALTER TYPE ADD VALUE fácilmente en enums existentes,
-- así que usamos TEXT directamente (más flexible)
-- Nota: La columna 'estado' ya es TEXT en visitas_agendadas, solo validamos en app

-- 2. Agregar geolocalización a médicos (perfiles)
ALTER TABLE perfiles 
  ADD COLUMN IF NOT EXISTS lat NUMERIC(10, 8),
  ADD COLUMN IF NOT EXISTS lng NUMERIC(11, 8),
  ADD COLUMN IF NOT EXISTS direccion_consultorio TEXT;

-- 3. Agregar campos de aprobación a visitas_agendadas
ALTER TABLE visitas_agendadas
  ADD COLUMN IF NOT EXISTS propuesta_por UUID REFERENCES cuentas_proveedor(id),
  ADD COLUMN IF NOT EXISTS aprobada_por UUID REFERENCES cuentas_proveedor(id),
  ADD COLUMN IF NOT EXISTS fecha_aprobacion TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS comentario_admin TEXT;

-- 4. Asegurar que visitador_id exista (o usar cuenta_proveedor_id que ya existe)
-- visitas_agendadas.cuenta_proveedor_id ya es el visitador asignado
-- Verificamos que exista
COMMENT ON COLUMN visitas_agendadas.cuenta_proveedor_id IS 'Visitador médico asignado a esta visita';

-- 5. Función RPC para obtener visitadores de una empresa
CREATE OR REPLACE FUNCTION get_visitadores_empresa(p_empresa_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      cp.id,
      cp.nombre_completo,
      cp.email,
      cp.rol_en_empresa,
      cp.activo,
      COUNT(v.id) FILTER (WHERE v.estado IN ('confirmada', 'pendiente')) as visitas_pendientes,
      COUNT(v.id) FILTER (WHERE v.estado = 'completada') as visitas_completadas,
      COUNT(v.id) FILTER (WHERE v.estado = 'propuesta') as visitas_propuestas
    FROM cuentas_proveedor cp
    LEFT JOIN visitas_agendadas v ON v.cuenta_proveedor_id = cp.id
    WHERE cp.empresa_id = p_empresa_id
      AND cp.activo = true
    GROUP BY cp.id, cp.nombre_completo, cp.email, cp.rol_en_empresa, cp.activo
    ORDER BY cp.nombre_completo
  ) t;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- 6. Función RPC para obtener visitas pendientes de aprobación de una empresa
CREATE OR REPLACE FUNCTION get_visitas_pendientes_aprobacion(p_empresa_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      v.id,
      v.fecha_visita,
      v.hora_inicio,
      v.hora_fin,
      v.tipo_visita,
      v.estado,
      v.notas_empresa,
      v.created_at,
      cp.nombre_completo as visitador_nombre,
      cp.email as visitador_email,
      p.nombre_completo as medico_nombre,
      p.email as medico_email,
      p.direccion_consultorio
    FROM visitas_agendadas v
    JOIN cuentas_proveedor cp ON cp.id = v.cuenta_proveedor_id
    JOIN perfiles p ON p.id = v.medico_id
    WHERE v.empresa_id = p_empresa_id
      AND v.estado = 'propuesta'
    ORDER BY v.fecha_visita, v.hora_inicio
  ) t;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- 7. Función RPC para obtener ruta del día de un visitador
CREATE OR REPLACE FUNCTION get_ruta_dia_visitador(p_visitador_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      v.id,
      v.fecha_visita,
      v.hora_inicio,
      v.hora_fin,
      v.tipo_visita,
      v.estado,
      v.notas_empresa,
      v.checkin_fecha,
      v.checkin_lat,
      v.checkin_lng,
      v.checkin_evidencia_url,
      v.checkout_fecha,
      v.checkout_notas,
      p.nombre_completo as medico_nombre,
      p.email as medico_email,
      p.direccion_consultorio,
      p.lat,
      p.lng
    FROM visitas_agendadas v
    JOIN perfiles p ON p.id = v.medico_id
    WHERE v.cuenta_proveedor_id = p_visitador_id
      AND v.estado IN ('confirmada', 'pendiente', 'completada')
      AND v.fecha_visita = CURRENT_DATE
    ORDER BY v.hora_inicio
  ) t;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- 8. Función para aprobar/rechazar visita (admin)
CREATE OR REPLACE FUNCTION administrar_visita(
  p_visita_id UUID,
  p_accion TEXT, -- 'aprobar', 'rechazar', 'modificar'
  p_nueva_fecha DATE DEFAULT NULL,
  p_nueva_hora_inicio TIME DEFAULT NULL,
  p_nueva_hora_fin TIME DEFAULT NULL,
  p_comentario TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_visita RECORD;
  v_admin_id UUID;
  v_empresa_id UUID;
BEGIN
  v_admin_id := auth.uid();
  
  -- Verificar que el admin pertenece a la misma empresa
  SELECT empresa_id INTO v_empresa_id FROM cuentas_proveedor WHERE id = v_admin_id;
  
  SELECT * INTO v_visita FROM visitas_agendadas WHERE id = p_visita_id AND empresa_id = v_empresa_id;
  
  IF v_visita IS NULL THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada o no pertenece a tu empresa');
  END IF;
  
  IF p_accion = 'aprobar' THEN
    UPDATE visitas_agendadas
    SET estado = 'confirmada',
        aprobada_por = v_admin_id,
        fecha_aprobacion = NOW(),
        comentario_admin = p_comentario
    WHERE id = p_visita_id;
    RETURN jsonb_build_object('success', true, 'estado', 'confirmada');
    
  ELSIF p_accion = 'rechazar' THEN
    UPDATE visitas_agendadas
    SET estado = 'rechazada',
        comentario_admin = p_comentario
    WHERE id = p_visita_id;
    RETURN jsonb_build_object('success', true, 'estado', 'rechazada');
    
  ELSIF p_accion = 'modificar' THEN
    UPDATE visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin, hora_fin),
        estado = 'confirmada',
        aprobada_por = v_admin_id,
        fecha_aprobacion = NOW(),
        comentario_admin = p_comentario
    WHERE id = p_visita_id;
    RETURN jsonb_build_object('success', true, 'estado', 'confirmada');
    
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;
END;
$$;
