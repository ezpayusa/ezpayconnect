import { supabase } from '@/lib/supabase'
import { mensajeErrorOrden } from '@/lib/ordenesExamen'

// ############################################################################################
// Corrección de resultados de examen (mig 335/336)
// ############################################################################################
// La barrera es la RPC corregir_resultado_examen (EX023-EX034): todo lo de acá es cortesía para
// no mandar al servidor lo que ya se sabe que va a rechazar, y para pintar sus rechazos.
//
// EL TEXTO SE MANDA SIEMPRE: la RPC guarda `resultados = btrim(p_resultados)` también cuando viene
// vacío, así que corregir solo el archivo con el textarea en blanco BORRA el texto vigente. Por eso
// el modal lo precarga con el resultado actual.

export const MOTIVO_MAX = 500

/** Lo que el bucket resultados-examenes admite (allowed_mime_types: pdf, jpeg, png). */
export const ACCEPT_RESULTADO = '.pdf,.jpg,.jpeg,.png'

/** Fila de public.examen_revisiones: los valores ANTERIORES a cada corrección. */
export interface RevisionExamen {
  id: number
  examen_id: number
  revision: number
  resultados_anterior: string | null
  archivo_url_anterior: string | null
  fecha_resultado_anterior: string | null
  liberado_al_corregir: boolean
  motivo: string
  corregido_at: string
}

/** Retorno de corregir_resultado_examen. */
export interface ResultadoCorreccion {
  examen_id: number
  revision: number
  notificado: boolean
}

export function leerResultadoCorreccion(data: unknown): ResultadoCorreccion | null {
  if (!data || typeof data !== 'object') return null
  const d = data as Record<string, unknown>
  if (typeof d.examen_id !== 'number' || typeof d.revision !== 'number') return null
  return { examen_id: d.examen_id, revision: d.revision, notificado: d.notificado === true }
}

// Mismos espacios que la RPC normaliza (btrim(x, E' \t\r\n')).
const normalizar = (s: string | null | undefined) => (s ?? '').replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '')

export interface BorradorCorreccion {
  motivo: string
  resultados: string
  hayArchivoNuevo: boolean
}

export interface ResultadoVigente {
  resultados: string | null
  archivo_url: string | null
}

/** Validación de cortesía (espeja EX027/EX034/EX028). null = se puede enviar. */
export function validarCorreccion(b: BorradorCorreccion, vigente: ResultadoVigente): string | null {
  const motivo = b.motivo.trim()
  if (!motivo) return 'El motivo de la corrección es obligatorio.'
  if (motivo.length > MOTIVO_MAX) return `El motivo no puede superar ${MOTIVO_MAX} caracteres.`
  const texto = normalizar(b.resultados)
  if (!texto && !b.hayArchivoNuevo && !vigente.archivo_url) return 'El resultado corregido no puede quedar vacío.'
  if (!b.hayArchivoNuevo && texto === normalizar(vigente.resultados)) return 'La corrección no cambia el resultado.'
  return null
}

/** EX0xx traen el mensaje para el usuario en español: se muestran tal cual. */
export function mensajeErrorCorreccion(error: { code?: string; message: string }): string {
  if (error.code === '42501') return 'No tenés permiso para corregir este resultado.'
  return mensajeErrorOrden(error, 'No se pudo corregir el resultado: ')
}

/** Historial de revisiones de varios exámenes en UNA query. La RLS decide quién lo ve (no el paciente). */
export async function cargarRevisiones(examenIds: number[]): Promise<RevisionExamen[]> {
  if (examenIds.length === 0) return []
  const { data, error } = await supabase
    .from('examen_revisiones')
    .select('id, examen_id, revision, resultados_anterior, archivo_url_anterior, fecha_resultado_anterior, liberado_al_corregir, motivo, corregido_at')
    .in('examen_id', examenIds)
    .order('revision', { ascending: false })
  if (error) {
    console.error('[cargarRevisiones]', error.code ?? error.message)
    return []
  }
  return (data ?? []) as RevisionExamen[]
}

/** Agrupa por examen, cada lista de la revisión más nueva a la más vieja. */
export function revisionesPorExamen(filas: RevisionExamen[]): Map<number, RevisionExamen[]> {
  const m = new Map<number, RevisionExamen[]>()
  for (const f of filas) {
    const l = m.get(f.examen_id)
    if (l) l.push(f)
    else m.set(f.examen_id, [f])
  }
  for (const l of m.values()) l.sort((a, b) => b.revision - a.revision)
  return m
}
