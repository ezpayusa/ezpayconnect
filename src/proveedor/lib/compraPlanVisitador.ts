// Compra de planes de visitador (familia CP, mig 351): mapeo de errores de las RPCs y reglas puras del catálogo.
//
// Se mira `error.code` (el SQLSTATE que expone PostgREST), nunca `error.message`: el código es el contrato estable.
// solicitar_compra_plan_visitador levanta CP001-CP007 y 42501; aprobar_pago_plan_visitador, CP010-CP017 y 42501.
// Un CP0xx que este mapa todavía no conoce no cae en un genérico mudo: sale con el código a la vista.

export const MENSAJES_SOLICITAR: Record<string, string> = {
  '42501': 'Tu usuario no puede contratar planes. Pídeselo a un administrador o editor de tu empresa.',
  CP001: 'El plan elegido ya no está disponible. Vuelve a la lista de planes y elige otro.',
  CP002: 'El plan elegido no corresponde al país de tu empresa.',
  CP003: 'El plan elegido no tiene visitas, vigencia o precio configurados. Avisa al equipo de EzPayConnect.',
  CP004: 'Todavía no hay una cuenta bancaria activa para tu país. Contacta al equipo de EzPayConnect.',
  CP005: 'La moneda del plan no coincide con la de la cuenta bancaria. Avisa al equipo de EzPayConnect.',
  CP006: 'No se pudo validar el comprobante. Vuelve a subirlo.',
  CP007: 'Ya tienes una compra de plan pendiente de verificación. Espera a que se resuelva antes de comprar otra.',
}

export const MENSAJES_APROBAR: Record<string, string> = {
  '42501': 'Solo un super administrador puede aprobar pagos de planes de visitador.',
  CP010: 'El pago no existe.',
  CP011: 'El pago no es de un plan de visitador.',
  CP012: 'El pago ya no está pendiente.',
  CP013: 'Pago legacy (sin visitas ni vigencia registradas): resuélvelo manualmente.',
  CP014: 'La configuración del plan de este pago ya no existe.',
  CP015: 'La empresa no está activa.',
  CP016: 'La empresa no opera en el país del plan.',
  CP017: 'La bolsa vigente de la empresa en ese país es ilimitada: no se le puede sumar una compra.',
}

export const MENSAJE_GENERICO_COMPRA = 'No se pudo completar la operación. Intenta de nuevo.'

// Comprar planes es de admin/editor (permiso planes.contratar). Al visitador no se le ofrece comprar:
// se le pide que avise a su administrador.
export const MENSAJE_BOLSA_AGOTADA_VISITADOR = 'Bolsa agotada · avísale a tu administrador para recargarla'
export const MENSAJE_SIN_BOLSA_VISITADOR = 'Avísale a tu administrador para que contrate un plan de visitas.'
export const RUTA_COMPRA_PLANES_VISITADOR = '/proveedor/visitador/planes'

type ErrorRpc = { code?: string | null; message?: string | null } | null | undefined

export function mensajeErrorCompraPlan(error: ErrorRpc, operacion: 'solicitar' | 'aprobar'): string {
  const code = error?.code ?? null
  const mapa = operacion === 'solicitar' ? MENSAJES_SOLICITAR : MENSAJES_APROBAR
  if (code && Object.prototype.hasOwnProperty.call(mapa, code)) return mapa[code]
  if (code && /^CP\d{3}$/.test(code)) return `No se pudo completar la operación (${code}).`
  return MENSAJE_GENERICO_COMPRA
}

/**
 * Hoy en UTC como 'YYYY-MM-DD'. Es el CURRENT_DATE del servidor (la base corre en UTC): el gate de visitas y las
 * RPCs de compra deciden la vigencia con esa fecha, así que el front usa la misma y no la fecha local.
 */
export function hoyUTC(ahora: Date = new Date()): string {
  return ahora.toISOString().slice(0, 10)
}

type FechasBolsa = { fecha_inicio?: string | null; fecha_fin?: string | null }

/**
 * Una bolsa está vigente si fecha_inicio <= hoy <= fecha_fin (bordes inclusivos), con hoy en UTC: el mismo
 * criterio que el servidor. En GT (UTC-6) una bolsa deja de estar vigente a las 18:00 hora local de su último día.
 */
export function esBolsaVigente(bolsa: FechasBolsa, hoy: string = hoyUTC()): boolean {
  const inicio = bolsa.fecha_inicio?.slice(0, 10)
  const fin = bolsa.fecha_fin?.slice(0, 10)
  return !!inicio && !!fin && inicio <= hoy && hoy <= fin
}

/** Bolsa (pvc) tal como la devuelve get_planes_visitador_proveedor; restante NULL = ilimitada. */
export interface BolsaCupo extends FechasBolsa {
  pais_id: string
  pais_nombre?: string | null
  estado?: string | null
  restante: number | null
  ilimitado: boolean
}

/** Cupo de un país: el de UNA bolsa (la que usa el gate), no la suma de las bolsas del país. */
export interface CupoPais {
  pais_id: string
  pais_nombre: string | null
  ilimitado: boolean
  restante: number | null // null = ilimitado
  fecha_fin: string
}

/**
 * Cupo por país con el mismo criterio que private.gate_visita_pais: por país, entre las bolsas activas y
 * vigentes (esBolsaVigente), cuenta solo la de fecha_fin más lejana — su restante, o ilimitada si sus
 * visitas incluidas son NULL. Dos bolsas superpuestas del mismo país NO suman; cada país es independiente.
 */
export function cupoPorPais(bolsas: BolsaCupo[], hoy: string = hoyUTC()): CupoPais[] {
  const elegida = new Map<string, BolsaCupo>()
  for (const b of bolsas) {
    if ((b.estado ?? 'activo') !== 'activo' || !esBolsaVigente(b, hoy)) continue
    const actual = elegida.get(b.pais_id)
    if (!actual || (b.fecha_fin as string).slice(0, 10) > (actual.fecha_fin as string).slice(0, 10)) elegida.set(b.pais_id, b)
  }
  return [...elegida.values()].map((b) => ({
    pais_id: b.pais_id,
    pais_nombre: b.pais_nombre ?? null,
    ilimitado: b.ilimitado,
    restante: b.ilimitado ? null : Math.max(0, b.restante ?? 0),
    fecha_fin: (b.fecha_fin as string).slice(0, 10),
  }))
}

/**
 * País en el que opera la cuenta: el mismo que usa el servidor, private.mi_pais() = COALESCE(cuenta.pais_id,
 * empresa.pais_id). buscar_medicos_proveedor solo ofrece médicos de ese país, así que es el país de las visitas y el
 * de la bolsa que las cobra (private.gate_visita_pais).
 */
export function paisOperativo(
  cuenta: { pais_id?: string | null } | null | undefined,
  empresa: { pais_id?: string | null } | null | undefined,
): string | null {
  return cuenta?.pais_id ?? empresa?.pais_id ?? null
}

/** El cupo de un país, o null si no tiene bolsa vigente (el gate rechaza: sin plan que cubra el país). */
export function cupoDelPais(cupos: CupoPais[], paisId: string | null | undefined): CupoPais | null {
  if (!paisId) return null
  return cupos.find((c) => c.pais_id === paisId) ?? null
}

/** ¿Queda al menos una visita? Ilimitada siempre; sin bolsa vigente, nunca. */
export function hayCupo(cupo: CupoPais | null): boolean {
  return !!cupo && (cupo.ilimitado || (cupo.restante ?? 0) > 0)
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
