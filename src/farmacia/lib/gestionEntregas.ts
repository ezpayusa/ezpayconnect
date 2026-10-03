// Gestión de entregas del gerente (mig 353): mapeo de errores de las RPCs y reglas puras de asignación.
//
// Se mira `error.code` (el SQLSTATE que expone PostgREST), nunca `error.message`: el código es el contrato estable.
// asignar_entrega, reasignar_entrega, asignar_entregas_lote, listar_repartidores_asignables y tablero_repartidores
// levantan 42501 y DE001-DE009. En la tanda, la entrega que falló viaja en `error.details` (su id).
// Un DE0xx que este mapa todavía no conoce no cae en un genérico mudo: sale con el código a la vista.
import { folioEntrega } from '@/repartidor/lib/folio'
import type { EstadoEntrega } from '@/repartidor/types'

export const MENSAJES_ENTREGAS: Record<string, string> = {
  '42501': 'Tu usuario no puede asignar entregas. Pedíselo a un administrador o gerente de tu farmacia.',
  DE001: 'La entrega ya no existe o no es de tu sucursal. Actualizá la lista.',
  DE002: 'La entrega ya no está pendiente: otra persona la asignó. Actualizá la lista.',
  DE003: 'El repartidor elegido no está activo en tu farmacia. Elegí otro.',
  DE004: 'El repartidor elegido es de otra sucursal. Elegí uno de la sucursal de la entrega.',
  DE005: 'La entrega ya está cobrada: no se puede reasignar.',
  DE006: 'La entrega no se puede reasignar en su estado actual. Actualizá la lista.',
  DE007: 'Elegí al menos una entrega.',
  DE008: 'Podés asignar hasta 50 entregas por tanda.',
  DE009: 'La tanda tiene entregas repetidas. Volvé a seleccionarlas.',
}

export const MENSAJE_GENERICO_ENTREGAS = 'No se pudo completar la operación. Intentá de nuevo.'

/** Tope de la tanda: el mismo que asignar_entregas_lote (DE008). */
export const MAX_LOTE = 50

type ErrorRpc = { code?: string | null; message?: string | null; details?: string | null } | null | undefined

export function mensajeErrorEntrega(error: ErrorRpc): string {
  const code = error?.code ?? null
  let base: string
  if (code && Object.prototype.hasOwnProperty.call(MENSAJES_ENTREGAS, code)) base = MENSAJES_ENTREGAS[code]
  else if (code && /^DE\d{3}$/.test(code)) base = `No se pudo completar la operación (${code}).`
  else return MENSAJE_GENERICO_ENTREGAS
  // En la tanda, DETAIL trae el id de la entrega que falló: se antepone su folio.
  const id = entregaQueFallo(error)
  return id != null ? `${folioEntrega(id)}: ${base}` : base
}

/** El id de la entrega que hizo fallar una tanda (DETAIL de asignar_entregas_lote), o null. */
export function entregaQueFallo(error: ErrorRpc): number | null {
  const d = (error?.details ?? '').trim()
  return /^\d+$/.test(d) ? Number(d) : null
}

type EntregaGestion = { estado: EstadoEntrega; cobrado: boolean; farmacia_id: number }

/** Se asigna solo desde pendiente (mismo criterio que asignar_entrega). */
export function puedeAsignar(e: EntregaGestion): boolean {
  return e.estado === 'pendiente'
}

/** Se reasigna desde asignada, en_camino o fallida, si no está cobrada (mismo criterio que reasignar_entrega). */
export function puedeReasignar(e: EntregaGestion): boolean {
  return !e.cobrado && (e.estado === 'asignada' || e.estado === 'en_camino' || e.estado === 'fallida')
}

/**
 * Una tanda va a UN repartidor, y el repartidor es de UNA sucursal: la selección tiene que ser de una sola
 * sucursal. Devuelve esa sucursal, o null si la selección está vacía o mezcla sucursales.
 */
export function sucursalUnica(entregas: Pick<EntregaGestion, 'farmacia_id'>[]): number | null {
  if (entregas.length === 0) return null
  const s = entregas[0].farmacia_id
  return entregas.every((e) => e.farmacia_id === s) ? s : null
}
