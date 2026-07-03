export type ProveedorRol = 'admin' | 'editor' | 'viewer' | 'visitador_medico'
export type EmpresaEstado = 'pendiente' | 'activa' | 'suspendida' | 'rechazada'
export type ProductoEstado = 'activo' | 'agotado' | 'descontinuado'
export type VisitaEstado = 'propuesta' | 'aprobada' | 'confirmada' | 'rechazada' | 'pendiente' | 'completada' | 'cancelada' | 'no_asistio'
export type VisitaTipo = 'presentacion_producto' | 'capacitacion' | 'muestra_gratis' | 'pedido' | 'otro'
export type PlanVisitadorEstado = 'activo' | 'expirado' | 'agotado'
export type SolicitudCampanaEstado = 'borrador' | 'enviada' | 'en_revision' | 'aprobada' | 'rechazada' | 'publicada'
export type PagoTipo = 'plan_publicidad' | 'plan_visitador' | 'campana' | 'suscripcion'
export type PagoEstado = 'pendiente' | 'verificado' | 'rechazado'

export interface EmpresaProveedora {
  id: string
  nombre_empresa: string
  tipo: 'farmacia' | 'laboratorio_farmaceutico' | 'laboratorio_clinico' | 'empresa_afin'
  ruc_nit: string | null
  pais_id: string | null
  ciudad: string | null
  direccion: string | null
  email_contacto: string
  telefono: string | null
  logo_url: string | null
  // Tema por tenant (mig 205). El empresa:empresa_id(*) ya las trae; solo faltaba tiparlas.
  color_primario: string | null
  color_secundario: string | null
  color_fondo: string | null
  estado: EmpresaEstado
  created_at: string
  updated_at: string
}

export interface CuentaProveedor {
  id: string
  empresa_id: string
  nombre_completo: string
  email: string
  rol_en_empresa: ProveedorRol
  activo: boolean
  created_at: string
  updated_at: string
  sucursal_id?: number | null
  empresa?: EmpresaProveedora
}

export interface ProductoEmpresa {
  id: string
  empresa_id: string
  nombre_producto: string
  principio_activo: string | null
  presentacion: string | null
  concentracion: string | null
  categoria: string | null
  precio_unitario: number
  moneda: string
  stock_disponible: number
  requiere_receta: boolean
  imagen_url: string | null
  estado: ProductoEstado
  created_at: string
  updated_at: string
  empresa?: { nombre_empresa: string; tipo: string }
}

export interface DisponibilidadMedico {
  id: string
  medico_id: string
  dia_semana: number
  hora_inicio: string
  hora_fin: string
  duracion_slot: number
  contexto?: 'visitador' | 'paciente'
  clinica_id: number | null
  activo: boolean
  created_at: string
  updated_at: string
}

export interface VisitaAgendada {
  id: string
  empresa_id: string
  medico_id: string
  cuenta_proveedor_id: string
  fecha_visita: string
  hora_inicio: string
  hora_fin: string
  tipo_visita: VisitaTipo
  productos_a_presentar: string[]
  estado: VisitaEstado
  notas_empresa: string | null
  notas_medico: string | null
  created_at: string
  updated_at: string
  medico?: { nombre_completo: string; email: string; direccion_consultorio?: string; lat?: number; lng?: number }
  visitador?: { nombre_completo: string; email: string }
  ubicacion?: { direccion?: string | null; lat?: number | null; lng?: number | null }
  // Flujo aprobación
  propuesta_por?: string
  aprobada_por?: string
  fecha_aprobacion?: string
  comentario_admin?: string
  // Campos de control
  fecha_limite_cancelacion?: string
  checkin_fecha?: string
  checkin_lat?: number
  checkin_lng?: number
  checkin_evidencia_url?: string
  checkout_fecha?: string
  checkout_notas?: string
  visita_concretada?: boolean
  verificada_por_sistema?: boolean
}

// DEPRECADO: Usar PlanAsignacion desde src/types/planes.ts
// Mantenido por compatibilidad temporal
export interface PlanVisitadorContratado {
  id: string
  empresa_id: string
  plan_visitador_id: number
  pais_id: number | null
  cantidad_visitas_incluidas: number
  visitas_usadas: number
  precio_pagado: number
  fecha_inicio: string
  fecha_fin: string
  estado: PlanVisitadorEstado
  created_at: string
  updated_at: string
}

export interface SolicitudCampana {
  id: string
  empresa_id: string
  cuenta_proveedor_id: string
  titulo: string
  descripcion: string | null
  tipo: string
  imagen_url: string | null
  link_url: string | null
  fecha_inicio: string
  fecha_fin: string
  condicion_filtro: string | null
  genero_filtro: string | null
  edad_min: number | null
  edad_max: number | null
  plan_publicidad_id: number | null
  estado: SolicitudCampanaEstado
  monto_pagado: number | null
  comprobante_pago_url: string | null
  notas_admin: string | null
  created_at: string
  updated_at: string
}

export interface PagoProveedor {
  id: string
  empresa_id: string
  tipo: PagoTipo
  referencia_id: string | null
  monto: number
  moneda: string
  metodo_pago: string | null
  comprobante_url: string | null
  estado: PagoEstado
  verificado_por: string | null
  fecha_pago: string | null
  fecha_verificacion: string | null
  created_at: string
  updated_at: string
}
