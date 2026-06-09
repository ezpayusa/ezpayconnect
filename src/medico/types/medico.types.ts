import type { Cita, Paciente, Receta } from '@/types'

export interface CitaConPaciente extends Cita {
  paciente?: {
    id: number
    nombre: string
    apellido: string
    telefono: string | null
    email: string | null
  }
}

export interface MedicoStats {
  citasHoy: number
  pendientesCount: number
  pacientesMes: number
  recetasMes: number
  proximaCita: CitaConPaciente | null
}

export type FiltroCitaEstado = 'todos' | 'solicitada' | 'agendada' | 'confirmada' | 'en_curso' | 'completada' | 'cancelada'
