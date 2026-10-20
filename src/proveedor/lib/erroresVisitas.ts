import { mapearErrorRpc } from '@/lib/erroresRpc'

// Qué mostrar cuando falla una escritura de visitas (INSERT de visitas_agendadas o las RPCs de visitas).
// SE MIRA `error.code`, nunca el texto: PV001/PV002/PV003, 42501 y el resto los decide mapearErrorRpc.
//
// P0001 es el RAISE sin ERRCODE de plpgsql: el gate de país del INSERT (private.gate_visita_pais) y los
// 'No autorizado…' de cancelar_visita, administrar_visita, checkin_visita y checkout_visita. Como el código
// no distingue la causa, cada acción tiene un texto fijo y el mensaje de la base no se lee.
// DEUDA: esas RPCs tendrían que levantar su rechazo con ERRCODE propio (backlog de la 376, punto (a)); hasta
// entonces el front no puede decir "no tienes permiso" con certeza.

export type AccionVisita = 'agendar' | 'cancelar' | 'administrar' | 'checkin' | 'checkout'

const TEXTO_P0001: Record<AccionVisita, string> = {
  agendar: 'No se pudo agendar la visita. Revisa que tu empresa tenga un plan de visitas activo en el país del médico.',
  cancelar: 'No se pudo cancelar la visita. Revisa que tengas permiso sobre ella.',
  administrar: 'No se pudo administrar la visita. Revisa que tengas permiso para gestionarla.',
  checkin: 'No se pudo registrar el check-in. Revisa que la visita sea tuya.',
  checkout: 'No se pudo registrar el check-out. Revisa que la visita sea tuya.',
}

/** 23505 al agendar = el turno lo tomó otro entre que lo viste y lo guardaste (único por médico+horario). */
export const TEXTO_TURNO_TOMADO = 'Ese horario acaba de ser tomado por otro proveedor. Por favor elige otro.'

export function mensajeErrorVisita(error: unknown, accion: AccionVisita): string {
  const m = mapearErrorRpc(error)
  if (m.code === 'P0001') return TEXTO_P0001[accion]
  if (m.code === '23505' && accion === 'agendar') return TEXTO_TURNO_TOMADO
  return m.mensaje
}
