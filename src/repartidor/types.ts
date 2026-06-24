// Tipos de la PWA del repartidor (F1). La forma viene del RPC listar_entregas_delivery (mig 151):
// superficie de columnas CONTROLADA — el front NO asume más de lo que el RPC devuelve.

export type EstadoEntrega =
  | 'pendiente'
  | 'asignada'
  | 'en_camino'
  | 'entregada'
  | 'fallida'

export type MotivoFallo = 'rechazada' | 'ausente' | 'direccion_mala'

export type MetodoCobro = 'efectivo' | 'tarjeta' | 'transferencia' | 'sin_cobro'

/** Una entrega tal como la devuelve `listar_entregas_delivery` (solo las del repartidor). */
export interface EntregaRepartidor {
  entrega_id: number
  estado: EstadoEntrega
  receta_base_id: number
  farmacia_id: number
  sucursal_nombre: string | null
  // PII: solo de SU propia entrega (flujo delivery confinado). No exponer fuera de esta superficie.
  direccion_entrega: string | null
  telefono_contacto: string | null
  lat: number | null
  lng: number | null
  monto: number | null
  cobrado: boolean
  metodo_cobro: MetodoCobro | null
  intentos: number
  motivo_fallo: MotivoFallo | null
  evidencia_path: string | null
  asignado_at: string | null
  entregado_at: string | null
  created_at: string
  updated_at: string
}

export interface FiltrosCola {
  estado?: EstadoEntrega
  desde?: string
  hasta?: string
}
