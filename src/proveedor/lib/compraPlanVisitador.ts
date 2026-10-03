// Compra de planes de visitador (familia CP, mig 351): mapeo de errores de las RPCs y reglas puras del catálogo.
//
// Se mira `error.code` (el SQLSTATE que expone PostgREST), nunca `error.message`: el código es el contrato estable.
// solicitar_compra_plan_visitador levanta CP001-CP007 y 42501; aprobar_pago_plan_visitador, CP010-CP017 y 42501.
// Un CP0xx que este mapa todavía no conoce no cae en un genérico mudo: sale con el código a la vista.

export const MENSAJES_SOLICITAR: Record<string, string> = {
  '42501': 'Tu usuario no puede contratar planes. Pedíselo a un administrador o editor de tu empresa.',
  CP001: 'El plan elegido ya no está disponible. Volvé a la lista de planes y elegí otro.',
  CP002: 'El plan elegido no corresponde al país de tu empresa.',
  CP003: 'El plan elegido no tiene visitas, vigencia o precio configurados. Avisá al equipo de EzPayConnect.',
  CP004: 'Todavía no hay una cuenta bancaria activa para tu país. Contactá al equipo de EzPayConnect.',
  CP005: 'La moneda del plan no coincide con la de la cuenta bancaria. Avisá al equipo de EzPayConnect.',
  CP006: 'No se pudo validar el comprobante. Volvé a subirlo.',
  CP007: 'Ya tenés una compra de plan pendiente de verificación. Esperá a que se resuelva antes de comprar otra.',
}

export const MENSAJES_APROBAR: Record<string, string> = {
  '42501': 'Solo un super administrador puede aprobar pagos de planes de visitador.',
  CP010: 'El pago no existe.',
  CP011: 'El pago no es de un plan de visitador.',
  CP012: 'El pago ya no está pendiente.',
  CP013: 'Pago legacy (sin visitas ni vigencia registradas): resolvelo manualmente.',
  CP014: 'La configuración del plan de este pago ya no existe.',
  CP015: 'La empresa no está activa.',
  CP016: 'La empresa no opera en el país del plan.',
  CP017: 'La bolsa vigente de la empresa en ese país es ilimitada: no se le puede sumar una compra.',
}

export const MENSAJE_GENERICO_COMPRA = 'No se pudo completar la operación. Intentá de nuevo.'

type ErrorRpc = { code?: string | null; message?: string | null } | null | undefined

export function mensajeErrorCompraPlan(error: ErrorRpc, operacion: 'solicitar' | 'aprobar'): string {
  const code = error?.code ?? null
  const mapa = operacion === 'solicitar' ? MENSAJES_SOLICITAR : MENSAJES_APROBAR
  if (code && Object.prototype.hasOwnProperty.call(mapa, code)) return mapa[code]
  if (code && /^CP\d{3}$/.test(code)) return `No se pudo completar la operación (${code}).`
  return MENSAJE_GENERICO_COMPRA
}

/** Fecha local de hoy como 'YYYY-MM-DD' (las fechas de la bolsa son DATE, sin zona). */
export function hoyISO(ahora: Date = new Date()): string {
  const y = ahora.getFullYear()
  const m = String(ahora.getMonth() + 1).padStart(2, '0')
  const d = String(ahora.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

/** Una bolsa está vigente si su fecha_fin es hoy o posterior. */
export function esBolsaVigente(fechaFin: string | null | undefined, hoy: string = hoyISO()): boolean {
  return !!fechaFin && fechaFin.slice(0, 10) >= hoy
}

/** Una configuración se puede comprar solo con visitas y duración > 0 (la RPC rechaza el resto con CP003). */
export function configComprable(c: { visitas_incluidas?: number | null; duracion_dias?: number | null }): boolean {
  return (c.visitas_incluidas ?? 0) > 0 && (c.duracion_dias ?? 0) > 0
}

/** Entero > 0 desde un input; null si está vacío, no es entero o no es positivo. */
export function enteroPositivo(valor: string | number | null | undefined): number | null {
  if (valor === null || valor === undefined || valor === '') return null
  const n = typeof valor === 'number' ? valor : Number(valor)
  return Number.isInteger(n) && n > 0 ? n : null
}

/** Código de moneda ISO de 3 letras en mayúsculas (moneda_local es varchar(3)); null si no es válido. */
export function normalizarMoneda(valor: string | null | undefined): string | null {
  const m = (valor ?? '').trim().toUpperCase()
  return /^[A-Z]{3}$/.test(m) ? m : null
}

/**
 * La RPC rechaza la compra (CP005) si la moneda del plan no es la de la cuenta bancaria activa del país.
 * Devuelve el aviso para el admin, o null si coinciden o el país no tiene cuenta activa (eso lo reporta CP004).
 */
export function advertenciaMonedaCuenta(monedaConfig: string | null | undefined, monedaCuenta: string | null | undefined): string | null {
  const cfg = normalizarMoneda(monedaConfig)
  const cta = normalizarMoneda(monedaCuenta)
  if (!cta || !cfg || cfg === cta) return null
  return `La compra fallará: la cuenta bancaria del país está en ${cta}`
}
