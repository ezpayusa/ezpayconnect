import type { EstadoEntrega, MotivoFallo } from '@/repartidor/types'

// Máquina de estados del REPARTIDOR (espejo de actualizar_estado_entrega en el backend).
// La UI ofrece SOLO las transiciones válidas desde el estado actual; el server hace RAISE
// igual como red de seguridad (el front no es la autoridad).

const TRANSICIONES: Record<EstadoEntrega, EstadoEntrega[]> = {
  pendiente: [], // el repartidor no actúa sobre pendiente (la asignación es gestión, no del repartidor)
  asignada: ['en_camino', 'fallida'],
  en_camino: ['entregada', 'fallida'],
  entregada: [], // terminal
  fallida: [], // terminal para el repartidor (la reapertura es gestión)
}

export function transicionesValidas(estado: EstadoEntrega): EstadoEntrega[] {
  return TRANSICIONES[estado] ?? []
}

/** Estados desde los que el backend permite cobrar (COD). El front solo refleja. */
export function puedeCobrarDesde(estado: EstadoEntrega): boolean {
  return estado === 'en_camino' || estado === 'entregada'
}

export const MOTIVOS_FALLO: { value: MotivoFallo; label: string }[] = [
  { value: 'rechazada', label: 'Rechazada por el paciente' },
  { value: 'ausente', label: 'Paciente ausente' },
  { value: 'direccion_mala', label: 'Dirección incorrecta' },
]

export const LABEL_ESTADO: Record<EstadoEntrega, string> = {
  pendiente: 'Pendiente',
  asignada: 'Asignada',
  en_camino: 'En camino',
  entregada: 'Entregada',
  fallida: 'Fallida',
}

export const LABEL_TRANSICION: Record<EstadoEntrega, string> = {
  pendiente: 'Marcar pendiente',
  asignada: 'Marcar asignada',
  en_camino: 'Iniciar ruta (en camino)',
  entregada: 'Marcar entregada',
  fallida: 'Marcar fallida',
}

/** Clase de color del badge por estado (tokens tailwind del repo). */
export function colorEstado(estado: EstadoEntrega): string {
  switch (estado) {
    case 'en_camino':
      return 'bg-blue-100 text-blue-700 border-blue-200'
    case 'asignada':
      return 'bg-amber-100 text-amber-700 border-amber-200'
    case 'pendiente':
      return 'bg-gray-100 text-gray-600 border-gray-200'
    case 'entregada':
      return 'bg-emerald-100 text-emerald-700 border-emerald-200'
    case 'fallida':
      return 'bg-red-100 text-red-700 border-red-200'
  }
}
