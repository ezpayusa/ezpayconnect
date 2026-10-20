// Bandeja de solicitudes de alta de médico del admin de país / super_admin (RPCs de las migs 377 y 378).
// Tipos, parseo de listar_solicitudes_alta y las reglas de la pantalla. La barrera real es la RPC: el gate
// de país (private.puede_admin_pais) vive en el servidor; acá solo se decide qué se pinta.

export interface SolicitudAltaAdmin {
  id: string
  pais_id: string
  nombre_completo: string
  email: string
  telefono: string | null
  especialidad_nombre: string | null
  numero_colegiado: string | null
  nombre_clinica: string | null
  empresa_nombre: string | null
  solicitante_nombre: string | null
  estado: string
  motivo_rechazo: string | null
  created_at: string
}

const textoONull = (v: unknown): string | null => (typeof v === 'string' && v.trim() !== '' ? v : null)

/** Lee las filas de listar_solicitudes_alta (377): solo las columnas que pinta la bandeja. */
export function parsearSolicitudesAdmin(raw: unknown): SolicitudAltaAdmin[] {
  const filas = (Array.isArray(raw) ? raw : []) as Record<string, unknown>[]
  return filas.map((f) => ({
    id: String(f.id),
    pais_id: String(f.pais_id ?? ''),
    nombre_completo: String(f.nombre_completo ?? ''),
    email: String(f.email ?? ''),
    telefono: textoONull(f.telefono),
    especialidad_nombre: textoONull(f.especialidad_nombre),
    numero_colegiado: textoONull(f.numero_colegiado),
    nombre_clinica: textoONull(f.nombre_clinica),
    empresa_nombre: textoONull(f.empresa_nombre),
    solicitante_nombre: textoONull(f.solicitante_nombre),
    estado: String(f.estado ?? ''),
    motivo_rechazo: textoONull(f.motivo_rechazo),
    created_at: String(f.created_at ?? ''),
  }))
}

/** Modo país: solo las del país de la URL. Sin paisId (menú global del super_admin): todas. */
export function filtrarPorPais(filas: SolicitudAltaAdmin[], paisId: string | null | undefined): SolicitudAltaAdmin[] {
  return paisId ? filas.filter((f) => f.pais_id === paisId) : filas
}

/** Filtro de estado de la bandeja ('todas' = p_estado NULL). */
export type FiltroEstado = 'pendiente' | 'invitada' | 'registrada' | 'rechazada' | 'cancelada' | 'todas'

export const FILTROS_ESTADO: { value: FiltroEstado; label: string }[] = [
  { value: 'pendiente', label: 'Pendientes' },
  { value: 'invitada', label: 'Invitadas' },
  { value: 'registrada', label: 'Registradas' },
  { value: 'rechazada', label: 'Rechazadas' },
  { value: 'cancelada', label: 'Canceladas' },
  { value: 'todas', label: 'Todas' },
]

export function pEstado(filtro: FiltroEstado): string | null {
  return filtro === 'todas' ? null : filtro
}

/** Acciones que la bandeja ofrece según el estado (las mismas transiciones que aceptan las RPCs). */
export type AccionSolicitud = 'aprobar' | 'rechazar' | 'reenviar'

export function accionesDeEstado(estado: string): AccionSolicitud[] {
  if (estado === 'pendiente') return ['aprobar', 'rechazar']
  if (estado === 'invitada') return ['reenviar']
  return []
}

// Mismos límites que rechazar_solicitud_alta (377, PV019): btrim + 5..500.
export const MOTIVO_MIN = 5
export const MOTIVO_MAX = 500

export function motivoValido(motivo: string): boolean {
  const m = motivo.trim()
  return m.length >= MOTIVO_MIN && m.length <= MOTIVO_MAX
}

export function textoConfirmarAprobar(email: string): string {
  return `Se va a enviar la invitación de MED al correo ${email}. ¿Quieres continuar?`
}

export function textoConfirmarReenviar(email: string): string {
  return `Se va a reenviar la invitación al correo ${email}. La invitación anterior deja de servir. ¿Quieres continuar?`
}
