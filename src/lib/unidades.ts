// Unidad de peso corporal por país. Canónico = kg (lo que se guarda en signos_vitales y con lo
// que el trigger trg_calcular_imc calcula el IMC). lb es solo capa de input/display; NUNCA se guarda lb.
export type UnidadPeso = 'kg' | 'lb'

const LB_POR_KG = 2.2046226218

// Países que usan libras para peso corporal (extensible). Guatemala arranca el set.
export const PAISES_LB = new Set<string>(['GT'])

export function unidadPesoPorPais(codigo: string | null | undefined): UnidadPeso {
  return codigo && PAISES_LB.has(codigo) ? 'lb' : 'kg'
}

export function kgALb(kg: number): number { return kg * LB_POR_KG }
export function lbAKg(lb: number): number { return lb / LB_POR_KG }

export function kgAInput(kgStr: string, unidad: UnidadPeso): string {
  if (kgStr.trim() === '') return ''
  const kg = parseFloat(kgStr)
  if (Number.isNaN(kg)) return ''
  return unidad === 'lb' ? kgALb(kg).toFixed(1) : kgStr
}

export function inputAKg(valStr: string, unidad: UnidadPeso): string {
  if (valStr.trim() === '') return ''
  const v = parseFloat(valStr)
  if (Number.isNaN(v)) return ''
  return unidad === 'lb' ? lbAKg(v).toFixed(2) : valStr
}

export function formatPeso(kg: number | null | undefined, unidad: UnidadPeso): string {
  if (kg == null) return ''
  return unidad === 'lb' ? kgALb(kg).toFixed(1) + ' lb' : kg + ' kg'
}
