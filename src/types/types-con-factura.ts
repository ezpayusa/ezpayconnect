export interface Perfil {
  id: string
  rol: 'medico' | 'secretaria' | 'admin_clinica' | 'paciente' | 'ezpay_admin'
  nombre_completo: string
  email: string
  telefono: string | null
  avatar_url: string | null
  pais_id: number | null
  activo: boolean
  created_at: string
}

export interface Paciente {
  id: number
  medico_id: string
  clinica_id: number | null
  nombre: string
  apellido: string
  fecha_nacimiento: string | null
  genero: string | null
  telefono: string | null
  email: string | null
  direccion: string | null
  emergencia_nombre: string | null
  emergencia_telefono: string | null
  alergias: string | null
  notas: string | null
  activo: boolean
  created_at: string
}

export interface Cita {
  id: number
  medico_id: string
  paciente_id: number
  clinica_id: number | null
  fecha: string
  hora_inicio: string
  hora_fin: string | null
  motivo: string | null
  estado: 'agendada' | 'confirmada' | 'en_curso' | 'completada' | 'cancelada' | 'no_show'
  notas: string | null
  created_at: string
}

export interface Medicamento {
  id: number
  nombre_generico: string
  nombre_comercial: string | null
  laboratorio: string | null
  presentacion: string | null
  concentracion: string | null
  via_administracion: string | null
  precio_referencia: number | null
  requiere_receta: boolean
  activo: boolean
}

export interface Receta {
  id: number
  medico_id: string
  paciente_id: number
  paciente_nombre?: string
  cita_id: number | null
  estado: 'activa' | 'completada' | 'vencida' | 'cancelada'
  instrucciones_generales: string | null
  pdf_url: string | null
  created_at: string
}

export interface RecetaItem {
  id: number
  receta_id: number
  medicamento_id: number | null
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  duracion: string | null
  instrucciones: string | null
  cantidad: number
}

export interface ExpedienteNota {
  id: number
  cita_id: number | null
  paciente_id: number
  medico_id: string
  nota: string
  diagnostico: string | null
  signos_vitales: Record<string, any> | null
  created_at: string
}

export interface HistorialMedico {
  id: number
  paciente_id: number
  medico_id: string
  fecha: string
  motivo_consulta: string | null
  diagnostico: string | null
  tratamiento: string | null
  notas_medicas: string | null
  examenes_solicitados: string | null
  created_at: string
}

// ✅ NUEVO: Factura
export interface Factura {
  id: number
  paciente_id: number
  paciente_nombre?: string
  medico_id: string
  fecha_emision: string
  concepto: string
  cantidad: number
  precio_unitario: number
  subtotal: number
  descuento: number
  total: number
  metodo_pago: string | null
  estado: 'pendiente' | 'pagada' | 'cancelada'
  notas: string | null
  created_at: string
}
