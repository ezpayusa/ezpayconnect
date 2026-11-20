import { supabase } from '@/lib/supabase'

// Cambio de estado de una cita: camino ÚNICO del front (agenda del médico y consulta).
//
// Por qué existe (demo IGSS, H5/H6/H21):
//  - Con la mig 391, un UPDATE de `citas` que la RLS no deja tocar NO da error: afecta 0 filas y
//    PostgREST responde 200. Sin `.select('id')` el front lo pintaba como éxito. Acá 0 filas es un
//    error explícito (SIN_FILAS).
//  - La agenda avisaba al paciente al cambiar el estado y la consulta no (H5): el aviso vive acá y
//    lo reciben los dos caminos por igual.
//  - Las etiquetas de estado son las mismas de la agenda (H21), no el texto crudo en mayúsculas.

export type EstadoCita =
  | 'solicitada'
  | 'agendada'
  | 'confirmada'
  | 'en_espera'
  | 'en_curso'
  | 'completada'
  | 'cancelada'
  | 'no_show'

export const ETIQUETA_ESTADO_CITA: Record<EstadoCita, string> = {
  solicitada: 'Solicitada',
  agendada: 'Agendada',
  confirmada: 'Confirmada',
  en_espera: 'En espera',
  en_curso: 'En curso',
  completada: 'Completada',
  cancelada: 'Cancelada',
  no_show: 'No asistió',
}

export function etiquetaEstadoCita(estado: string): string {
  return ETIQUETA_ESTADO_CITA[estado as EstadoCita] ?? estado
}

// H1: estados desde los que el médico ABRE la consulta y la pasa a en_curso («En sala» / «Atender»).
// Flujo del servidor (mig 260): confirmada|agendada → en_espera (recepción marca la llegada) → en_curso
// → completada. Una cita en_espera es una confirmada cuyo paciente ya llegó: se atiende igual. La mig
// 391 deja al médico escribir solo `estado` de SUS citas, sin guard de transición, así que en_espera →
// en_curso pasa igual que confirmada → en_curso. en_curso no está acá: ya está abierta («Continuar»).
export const ESTADOS_PARA_ATENDER: readonly EstadoCita[] = ['confirmada', 'en_espera']

export function puedeAtender(estado: string): boolean {
  return (ESTADOS_PARA_ATENDER as readonly string[]).includes(estado)
}

// Estados que avisan al paciente (notificar_cita_paciente, RPC gateada server-side: verifica la
// relación médico/clínica→cita y compone el contenido; el cliente solo pasa la cita y el evento).
const EVENTOS_AVISO = ['confirmada', 'cancelada', 'en_curso', 'completada'] as const
type EventoAviso = (typeof EVENTOS_AVISO)[number]

export const MENSAJE_SIN_FILAS =
  'No se pudo cambiar el estado de la cita: no tienes permiso sobre ella o ya no existe.'

// Forma plana (sin unión discriminada): el tsconfig de la app no tiene strictNullChecks y no estrecha
// por `ok`. Con ok=true, codigo y mensaje son null.
export type ResultadoEstadoCita = {
  ok: boolean
  codigo: 'SIN_FILAS' | 'ERROR' | null
  mensaje: string | null
}

export async function cambiarEstadoCita(citaId: number, estado: EstadoCita): Promise<ResultadoEstadoCita> {
  const { data, error } = await supabase
    .from('citas')
    .update({ estado })
    .eq('id', citaId)
    .select('id')

  if (error) {
    return { ok: false, codigo: 'ERROR', mensaje: error.message || 'No se pudo cambiar el estado de la cita.' }
  }
  if (!data || data.length === 0) {
    return { ok: false, codigo: 'SIN_FILAS', mensaje: MENSAJE_SIN_FILAS }
  }

  if ((EVENTOS_AVISO as readonly string[]).includes(estado)) {
    // El aviso no revierte el cambio: si falla, el estado ya quedó y solo se registra.
    const { error: errAviso } = await supabase.rpc('notificar_cita_paciente', {
      p_cita_id: citaId,
      p_evento: estado as EventoAviso,
    })
    if (errAviso) console.error('Error notificar_cita_paciente:', errAviso.message ?? errAviso.code)
  }

  return { ok: true, codigo: null, mensaje: null }
}
