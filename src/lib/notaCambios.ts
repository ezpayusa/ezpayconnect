// H3: ¿la nota de la consulta tiene cambios sin guardar?
//
// `base` es lo que hay guardado: la nota de la base (notaGuardada, con NULL mostrado como '') o, si
// todavía no existe, el estado inicial de la pantalla (vacío con el motivo de la cita). null = la
// pantalla todavía está cargando → sin cambios.
export const CAMPOS_NOTA = ['motivo_consulta', 'subjetivo', 'objetivo', 'analisis', 'plan', 'diagnostico'] as const
export type CampoNota = typeof CAMPOS_NOTA[number]
export type SoapForm = Record<CampoNota, string>

export function hayCambiosNota(p: {
  soap: SoapForm
  base: SoapForm | null
  soloLectura: boolean
  corrigiendo: boolean
  motivoCorreccion: string
}): boolean {
  if (p.soloLectura || !p.base) return false
  // En modo corrección, un motivo escrito también es trabajo que se perdería.
  if (p.corrigiendo && p.motivoCorreccion.trim() !== '') return true
  const base = p.base
  return CAMPOS_NOTA.some(k => p.soap[k] !== base[k])
}
