// Rangos de plausibilidad y unidades canónicas de los signos vitales. FUENTE ÚNICA del front.
// Espejo EXACTO de la mig 330 (capturar_signo_vital + CHECK sv_*_rango): si cambia una cota acá,
// cambia allá, y viceversa. Los mensajes son el mismo texto que devuelve la RPC (SV001/SV002).
// Unidades canónicas (lo que se guarda): glucosa mg/dL entero, temperatura °C, peso kg, talla cm.
// El peso admite lb solo como capa de input/display (ver unidades.ts); se valida siempre en kg.
import { kgALb, type UnidadPeso } from '@/lib/unidades'

export type CampoVitalNumerico =
  | 'frecuencia_cardiaca'
  | 'frecuencia_respiratoria'
  | 'temperatura'
  | 'saturacion_o2'
  | 'peso_kg'
  | 'talla_cm'
  | 'glucosa'

export interface RangoVital {
  min: number
  max: number
  unidad: string
  step: number
  entero: boolean
}

export const RANGOS_VITALES: Record<CampoVitalNumerico, RangoVital> = {
  frecuencia_cardiaca: { min: 20, max: 300, unidad: 'lpm', step: 1, entero: true },
  frecuencia_respiratoria: { min: 4, max: 80, unidad: 'rpm', step: 1, entero: true },
  temperatura: { min: 30, max: 45, unidad: '°C', step: 0.1, entero: false },
  saturacion_o2: { min: 50, max: 100, unidad: '%', step: 1, entero: true },
  peso_kg: { min: 0.5, max: 400, unidad: 'kg', step: 0.1, entero: false },
  talla_cm: { min: 30, max: 250, unidad: 'cm', step: 0.1, entero: false },
  glucosa: { min: 10, max: 1000, unidad: 'mg/dL', step: 1, entero: true },
}

export const PRESION_ARTERIAL = {
  unidad: 'mmHg',
  formato: /^[0-9]{2,3}\/[0-9]{2,3}$/,
  sistolica: { min: 50, max: 300 },
  diastolica: { min: 20, max: 200 },
} as const

/**
 * min/max/step del input de peso en la unidad activa. En lb se redondea hacia adentro a 1 decimal
 * (1.1-881.8): inputAKg guarda toFixed(2), así que 1.1 lb -> 0.50 kg y 881.8 lb -> 399.97 kg entran.
 */
export function rangoPesoEnUnidad(unidad: UnidadPeso): { min: number; max: number; step: number } {
  const r = RANGOS_VITALES.peso_kg
  if (unidad === 'kg') return { min: r.min, max: r.max, step: r.step }
  return { min: Math.round(kgALb(r.min) * 10) / 10, max: Math.floor(kgALb(r.max) * 10) / 10, step: 0.1 }
}

// Tope de imc numeric(4,2): la RPC calcula el IMC igual que trg_calcular_imc y rechaza > 99.99.
const IMC_MAX = 99.99

export const MSG_PA_FORMATO = 'Presión arterial con formato inválido (use NNN/NN)'
export const MSG_PA_RANGO =
  'Signo vital fuera de rango: presion_arterial (sistolica 50-300, diastolica 20-200 mmHg, sistolica > diastolica)'
export const MSG_COMBINACION = 'Combinación peso/talla inválida'
// Mismo texto que el SV003 de la RPC (mig 331). notas no es un vital.
export const MSG_TOMA_VACIA = 'Toma vacía: cargue al menos un signo vital'
// input type=number con texto que no es número (p. ej. "10-100"): el navegador entrega '' y marca
// validity.badInput. Sin este error, '' se leía como "no medido" (mig 331, fila 1453).
export const MSG_VALOR_INVALIDO = 'Valor inválido: ingrese solo un número'

export function mensajeFueraDeRango(campo: CampoVitalNumerico): string {
  const r = RANGOS_VITALES[campo]
  return `Signo vital fuera de rango: ${campo} (${r.min}-${r.max} ${r.unidad})`
}

// Clave 'imc' = error de la combinación peso/talla (no es un input). 'toma' = toma vacía (va arriba del botón).
export type CampoConError = CampoVitalNumerico | 'presion_arterial' | 'imc' | 'toma'
export type ErroresVitales = Partial<Record<CampoConError, string>>

export interface VitalesAValidar {
  presion_arterial: string
  frecuencia_cardiaca: string
  frecuencia_respiratoria: string
  temperatura: string
  peso_kg: string
  talla_cm: string
  saturacion_o2: string
  glucosa: string
}

/**
 * Valida igual que capturar_signo_vital (migs 330/331). Vacío = no medido → válido, pero al menos un
 * vital tiene que venir (SV003). Los numéricos llegan como string (lo que tipea el usuario); el peso ya en kg.
 * `invalidos`: campos cuyo input tiene validity.badInput — su '' NO es "no medido", es texto inválido.
 * Agregados del cliente: badInput, y un valor no numérico o con decimales en un campo entero, que la RPC
 * rechazaría con un error de tipo (no SV) — acá se nombra el campo en lugar de eso.
 */
export function validarVitales(v: VitalesAValidar, invalidos: CampoVitalNumerico[] = []): ErroresVitales {
  const errores: ErroresVitales = {}
  for (const campo of invalidos) errores[campo] = MSG_VALOR_INVALIDO
  for (const campo of Object.keys(RANGOS_VITALES) as CampoVitalNumerico[]) {
    if (errores[campo]) continue
    const s = v[campo].trim()
    if (s === '') continue
    const r = RANGOS_VITALES[campo]
    const n = Number(s)
    if (!Number.isFinite(n)) { errores[campo] = `${campo}: valor no numérico (${r.unidad})`; continue }
    if (r.entero && !Number.isInteger(n)) { errores[campo] = `${campo}: debe ser un número entero (${r.unidad})`; continue }
    if (n < r.min || n > r.max) errores[campo] = mensajeFueraDeRango(campo)
  }

  const pa = v.presion_arterial.trim()
  if (pa !== '') {
    if (!PRESION_ARTERIAL.formato.test(pa)) {
      errores.presion_arterial = MSG_PA_FORMATO
    } else {
      const [sis, dia] = pa.split('/').map(Number)
      const { sistolica: s, diastolica: d } = PRESION_ARTERIAL
      if (sis < s.min || sis > s.max || dia < d.min || dia > d.max || sis <= dia) errores.presion_arterial = MSG_PA_RANGO
    }
  }

  // Combinación: solo si peso y talla pasaron su propio rango (mismo orden que la RPC).
  if (!errores.peso_kg && !errores.talla_cm && v.peso_kg.trim() !== '' && v.talla_cm.trim() !== '') {
    const peso = round2(Number(v.peso_kg))
    const talla = round2(Number(v.talla_cm))
    if (round2(peso / ((talla / 100) * (talla / 100))) > IMC_MAX) errores.imc = MSG_COMBINACION
  }

  // Toma vacía (SV003): solo si no hay otro error — un badInput deja el campo en '' y el error útil es el suyo.
  const vacia = pa === '' && (Object.keys(RANGOS_VITALES) as CampoVitalNumerico[]).every((c) => v[c].trim() === '')
  if (vacia && Object.keys(errores).length === 0) errores.toma = MSG_TOMA_VACIA
  return errores
}

const round2 = (n: number) => Math.round(n * 100) / 100

/** Errores de rango/formato de la RPC: se muestran tal cual en el formulario, no como toast. */
export function esErrorVital(error: { code?: string } | null | undefined): boolean {
  return error?.code === 'SV001' || error?.code === 'SV002' || error?.code === 'SV003'
}

/** A qué campo del formulario corresponde un mensaje SV de la RPC (null = general). */
export function campoDeErrorVital(mensaje: string): CampoConError | null {
  if (mensaje === MSG_PA_FORMATO || mensaje === MSG_PA_RANGO) return 'presion_arterial'
  if (mensaje === MSG_COMBINACION) return 'imc'
  if (mensaje === MSG_TOMA_VACIA) return 'toma'
  const m = /^Signo vital fuera de rango: (\w+) /.exec(mensaje)
  return m && m[1] in RANGOS_VITALES ? (m[1] as CampoVitalNumerico) : null
}

/** "74 lpm", "36.6 °C", "90 mg/dL". El peso NO pasa por acá: usa formatPeso (kg/lb por país). */
export function formatVital(campo: Exclude<CampoVitalNumerico, 'peso_kg'>, valor: number | string): string {
  return `${valor} ${RANGOS_VITALES[campo].unidad}`
}

export function formatPA(pa: string): string {
  return `${pa} ${PRESION_ARTERIAL.unidad}`
}
