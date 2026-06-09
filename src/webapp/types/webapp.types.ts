// Tipos específicos del portal del paciente

export interface PacientePerfil {
  id: number
  nombre: string
  apellido: string
  email: string | null
  telefono: string | null
  fecha_nacimiento: string | null
  genero: string | null
  direccion: string | null
  alergias: string | null
  notas: string | null
  emergencia_nombre: string | null
  emergencia_telefono: string | null
  foto_url: string | null
  pais_id?: string | null
  activo: boolean
  created_at: string
}

export interface CitaPaciente {
  id: number
  fecha: string
  hora_inicio: string
  hora_fin: string | null
  motivo: string | null
  estado: 'solicitada' | 'agendada' | 'confirmada' | 'en_curso' | 'completada' | 'cancelada' | 'no_show'
  medico_nombre?: string
  medico_especialidad?: string
  clinica_nombre?: string
  notas?: string | null
  created_at: string
}

export interface RecetaPaciente {
  id: number
  medico_nombre: string
  estado: 'activa' | 'completada' | 'vencida' | 'cancelada'
  instrucciones_generales: string | null
  items: RecetaItemPaciente[]
  codigo_qr: string | null
  created_at: string
}

export interface RecetaItemPaciente {
  id: number
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  duracion: string | null
  instrucciones: string | null
  cantidad: number
  farmacia_nombre?: string | null
  farmacia_direccion?: string | null
  precio_unitario?: number | null
}

export interface ExamenPaciente {
  id: number
  tipo: string
  fecha: string
  estado: 'pendiente' | 'completado' | 'revision'
  resultados: string | null
  archivo_url: string | null
  medico_nombre?: string
  notas: string | null
  created_at: string
}

export interface HistorialItem {
  id: number
  tipo: 'cita' | 'receta' | 'examen' | 'nota'
  fecha: string
  titulo: string
  descripcion: string
  medico_nombre?: string
  detalles?: Record<string, any>
}

export interface ChatMensaje {
  id: number
  remitente: 'paciente' | 'medico'
  mensaje: string
  leido: boolean
  created_at: string
  medico_nombre?: string
  medico_avatar?: string | null
}

export interface NotificacionPaciente {
  id: number
  tipo: 'cita' | 'receta' | 'examen' | 'mensaje' | 'promocion'
  titulo: string
  mensaje: string | null
  leida: boolean
  accion_url: string | null
  created_at: string
}

export interface MedicoDisponible {
  id: string
  nombre_completo: string
  especialidad?: string
  foto_url?: string | null
  horarios?: { dia: string; inicio: string; fin: string }[]
}

export interface CampanaPublicitaria {
  id: number
  titulo: string
  descripcion: string | null
  tipo: 'farmacia' | 'equipo_medico' | 'laboratorio' | 'general'
  imagen_url: string | null
  link_url: string | null
  fecha_inicio: string
  fecha_fin: string
  activa: boolean
  condicion_filtro: string | null
  genero_filtro: string | null
  edad_min: number | null
  edad_max: number | null
  created_at: string
}
