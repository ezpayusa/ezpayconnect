// Enrolamiento de médicos desde la PWA del visitador (RPCs de las migs 375-380). Tipos, parseo de lo que
// devuelven las RPCs y la validación en cliente del formulario de alta.
// La barrera real es la RPC: nada de esto decide permisos, y la UI nunca muestra un dato que la RPC no devuelva.

/** prioridad_para_agendar (mig 380). Nunca trae el id ni el nombre del otro laboratorio. */
export type EstadoPrioridad = 'propia' | 'otro_laboratorio' | 'libre'

export interface PrioridadAgendar {
  estado: EstadoPrioridad
  /** 'YYYY-MM-DD': primer día que el head-start deja agendar. Solo con 'otro_laboratorio'. */
  fecha_minima: string | null
  visitas_completadas: number | null
  visitas_limite: number | null
}

const ESTADOS_PRIORIDAD: readonly EstadoPrioridad[] = ['propia', 'otro_laboratorio', 'libre']
const FECHA_ISO = /^\d{4}-\d{2}-\d{2}$/

const numOrNull = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)

/** Lee el jsonb de prioridad_para_agendar. Algo que no reconoce → null (sin indicador, no se inventa nada). */
export function parsearPrioridad(raw: unknown): PrioridadAgendar | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Record<string, unknown>
  if (!ESTADOS_PRIORIDAD.includes(r.estado as EstadoPrioridad)) return null
  const estado = r.estado as EstadoPrioridad
  const fecha = typeof r.fecha_minima === 'string' && FECHA_ISO.test(r.fecha_minima) ? r.fecha_minima : null
  // 'otro_laboratorio' sin fecha válida no se puede pintar ni bloquear con honestidad.
  if (estado === 'otro_laboratorio' && !fecha) return null
  return {
    estado,
    fecha_minima: estado === 'otro_laboratorio' ? fecha : null,
    visitas_completadas: numOrNull(r.visitas_completadas),
    visitas_limite: numOrNull(r.visitas_limite),
  }
}

/** 'YYYY-MM-DD' → 'DD/MM/YYYY' sin pasar por Date (evita el corrimiento de zona horaria). */
export function formatearFechaIso(iso: string): string {
  const [y, m, d] = iso.split('-')
  return `${d}/${m}/${y}`
}

/** Texto del indicador, o null si no hay aviso ('libre'). */
export function textoPrioridad(p: PrioridadAgendar): string | null {
  if (p.estado === 'propia') {
    const visitas = p.visitas_completadas != null && p.visitas_limite != null
      ? ` (${p.visitas_completadas} de ${p.visitas_limite} visitas)`
      : ''
    return `Tienes prioridad con este médico${visitas}`
  }
  if (p.estado === 'otro_laboratorio' && p.fecha_minima) {
    return `Este médico tiene prioridad de otro laboratorio. Puedes agendar desde ${formatearFechaIso(p.fecha_minima)}`
  }
  return null
}

/** Un turno con fecha anterior a fecha_minima no se puede elegir (el trigger lo rechazaría con PV002). */
export function fechaBloqueadaPorPrioridad(fecha: string, p: PrioridadAgendar | null): boolean {
  return p?.estado === 'otro_laboratorio' && p.fecha_minima != null && fecha < p.fecha_minima
}

// --- enrolar_medico (mig 375) ---------------------------------------------------------------------
export type EstadoEnrolamiento = 'enrolado' | 'ya_enrolado_por_ti'

// --- solicitar_alta_medico (migs 377/378) ---------------------------------------------------------
export type RespuestaSolicitud =
  | { estado: 'creada'; solicitud_id: string }
  | { estado: 'existe'; medico_id: string }

export function parsearRespuestaSolicitud(raw: unknown): RespuestaSolicitud | null {
  if (!raw || typeof raw !== 'object') return null
  const r = raw as Record<string, unknown>
  if (r.estado === 'creada' && typeof r.solicitud_id === 'string') return { estado: 'creada', solicitud_id: r.solicitud_id }
  if (r.estado === 'existe' && typeof r.medico_id === 'string') return { estado: 'existe', medico_id: r.medico_id }
  return null
}

export interface DatosSolicitudAlta {
  nombre: string
  email: string
  telefono: string
  especialidad_id: string
  numero_colegiado: string
  nombre_clinica: string
  autorizado: boolean
}

export type CampoSolicitud = keyof DatosSolicitudAlta
export type ErroresSolicitud = Partial<Record<CampoSolicitud, string>>

// Mismos límites que solicitar_alta_medico (377): no reemplaza la validación del servidor, la adelanta.
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

export function validarSolicitudAlta(d: DatosSolicitudAlta): ErroresSolicitud {
  const e: ErroresSolicitud = {}
  const nombre = d.nombre.trim()
  if (nombre.length < 3 || nombre.length > 150) e.nombre = 'El nombre del médico debe tener entre 3 y 150 caracteres.'
  const email = d.email.trim().toLowerCase()
  if (!email || email.length > 254 || !EMAIL.test(email)) e.email = 'El correo del médico no es válido.'
  const tel = d.telefono.trim()
  if (tel) {
    const digitos = tel.replace(/[^0-9]/g, '').length
    if (tel.length > 30 || digitos < 7 || digitos > 15) e.telefono = 'El teléfono debe tener entre 7 y 15 dígitos.'
  }
  if (d.numero_colegiado.trim().length > 30) e.numero_colegiado = 'El número de colegiado no puede tener más de 30 caracteres.'
  if (d.nombre_clinica.trim().length > 150) e.nombre_clinica = 'El nombre de la clínica no puede tener más de 150 caracteres.'
  if (!d.autorizado) e.autorizado = 'Necesitas la autorización del médico para solicitar su alta.'
  return e
}

/** Parámetros de la RPC: vacío = sin dato en los opcionales (la RPC hace el mismo NULLIF). */
export function paramsSolicitudAlta(d: DatosSolicitudAlta) {
  return {
    p_nombre: d.nombre.trim(),
    p_email: d.email.trim().toLowerCase(),
    p_telefono: d.telefono.trim() || null,
    p_especialidad_id: d.especialidad_id || null,
    p_numero_colegiado: d.numero_colegiado.trim() || null,
    p_nombre_clinica: d.nombre_clinica.trim() || null,
    p_autorizado: d.autorizado,
  }
}

// --- listar_solicitudes_alta (mig 377): solo las columnas que pinta la PWA -------------------------
export type EstadoSolicitud = 'pendiente' | 'invitada' | 'registrada' | 'rechazada' | 'cancelada'

export interface SolicitudAlta {
  id: string
  nombre_completo: string
  email: string
  especialidad_nombre: string | null
  estado: string
  motivo_rechazo: string | null
  created_at: string
}

/** EL mapa único de estados de solicitud → etiqueta y estilo del badge. */
export const ESTADOS_SOLICITUD: Record<EstadoSolicitud, { label: string; clase: string }> = {
  pendiente: { label: 'Pendiente', clase: 'bg-amber-100 text-amber-800' },
  invitada: { label: 'Invitada', clase: 'bg-blue-100 text-blue-800' },
  registrada: { label: 'Registrada', clase: 'bg-green-100 text-green-800' },
  rechazada: { label: 'Rechazada', clase: 'bg-red-100 text-red-800' },
  cancelada: { label: 'Cancelada', clase: 'bg-gray-100 text-gray-600' },
}

export function badgeEstadoSolicitud(estado: string): { label: string; clase: string } {
  return ESTADOS_SOLICITUD[estado as EstadoSolicitud] ?? { label: estado, clase: 'bg-gray-100 text-gray-600' }
}

/** Solo una solicitud pendiente se puede cancelar (cancelar_solicitud_alta da PV022 en cualquier otro estado). */
export const puedeCancelarSolicitud = (estado: string) => estado === 'pendiente'

// --- Visibilidad (pieza 6): cosmética, la barrera es la RPC ----------------------------------------
/** Enrolar y solicitar alta: laboratorio farmacéutico con el módulo 'enrolamiento' vigente. */
export function puedeEnrolarEmpresa(tipoEmpresa: string | null | undefined, tieneEnrolamiento: boolean): boolean {
  return tipoEmpresa === 'laboratorio_farmaceutico' && tieneEnrolamiento
}

/**
 * Cuántas semanas hay que avanzar la grilla de turnos (semanas de lunes a domingo) para llegar a la que contiene
 * `fechaIso`, contando desde la semana de `hoy`. Nunca negativo. Sin date-fns para no inflar el chunk de entrada.
 */
export function semanasHasta(fechaIso: string, hoy: Date): number {
  const [y, m, d] = fechaIso.split('-').map(Number)
  const lunes = (f: Date) => {
    const r = new Date(f.getFullYear(), f.getMonth(), f.getDate())
    r.setDate(r.getDate() - ((r.getDay() + 6) % 7))
    return r
  }
  const diff = Math.round((lunes(new Date(y, m - 1, d)).getTime() - lunes(hoy).getTime()) / (7 * 24 * 60 * 60 * 1000))
  return Math.max(0, diff)
}
