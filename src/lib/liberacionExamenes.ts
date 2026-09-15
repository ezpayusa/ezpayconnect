import { supabase } from '@/lib/supabase'
import { mapearErrorRpc } from '@/lib/erroresRpc'

// ############################################################################################
// Liberar resultados de examen al paciente
// ############################################################################################
// El gate existe para que un resultado NO le llegue al paciente antes de que el médico decida
// hablarlo. Por eso cada liberación es por EXAMEN, con su id, y la liberación de varios es la misma
// operación repetida sobre una lista que el médico vio y confirmó.
//
// POR QUÉ NO SE USA liberar_orden_al_paciente PARA "LIBERAR LOS N LISTOS"
// -----------------------------------------------------------------------
// Esa RPC libera TODO examen completado y no liberado de la orden que su gate autoriza, y su gate
// (medico_id / medico_atiende_paciente / es_admin_clinica(clinica_id) / super_admin) NO es el mismo
// predicado que las policies de SELECT de `examenes` (medico_id / medico_es_de_mi_clinica(medico_id)
// / lab / super_admin / paciente). O sea: puede liberar exámenes que no están en la lista que el
// médico está viendo. Medido 15-sep: hoy ninguna orden mezcla médicos ni clínicas, así que en la
// práctica coincide — pero ese invariante NO lo impone la base. Liberando por id, lo liberado es
// EXACTAMENTE lo que se nombró en la confirmación, por construcción.
// Costo aceptado: el paciente recibe una notificación por examen en vez de una por orden.
//
// "YA LIBERADO" NO ES UN ERROR: liberar_examen_al_paciente devuelve { ya_liberado: true } sin
// excepción. Pasa si otro médico lo liberó entre que se cargó la lista y el clic.

export interface ExamenLiberable {
  id: number
  tipo: string
  fecha_resultado?: string | null
}

export type ResultadoUno =
  | { estado: 'liberado' }
  | { estado: 'ya_liberado' }
  | { estado: 'error'; mensaje: string }

// PT002 en ESTE contexto es uno de tres: examen inexistente, sin autoridad, o sin resultado cargado.
// El código no los distingue (medido en el cuerpo vivo de la RPC), así que el texto no elige uno.
export const MENSAJE_PT002_LIBERAR =
  'No se pudo liberar: no tenés permiso sobre este examen o todavía no tiene resultado cargado.'

export async function liberarUnExamen(examenId: number): Promise<ResultadoUno> {
  const { data, error } = await supabase.rpc('liberar_examen_al_paciente', { p_examen_id: examenId })
  if (error) {
    const m = mapearErrorRpc(error)
    return { estado: 'error', mensaje: m.code === 'PT002' ? MENSAJE_PT002_LIBERAR : m.mensaje }
  }
  if (data && typeof data === 'object' && (data as Record<string, unknown>).ya_liberado === true) {
    return { estado: 'ya_liberado' }
  }
  return { estado: 'liberado' }
}

export interface ResultadoVarios {
  liberados: ExamenLiberable[]
  yaLiberados: ExamenLiberable[]
  fallidos: { examen: ExamenLiberable; mensaje: string }[]
}

/**
 * Libera, uno por uno y por id, EXACTAMENTE la lista confirmada. No corta al primer error: si el
 * tercero de cinco falla, los otros cuatro igual se procesan y el resultado dice cuál falló y por
 * qué. Cortar al primero dejaba al médico sin saber qué quedó liberado y qué no.
 */
export async function liberarExamenes(examenes: ExamenLiberable[]): Promise<ResultadoVarios> {
  const r: ResultadoVarios = { liberados: [], yaLiberados: [], fallidos: [] }
  for (const ex of examenes) {
    const uno = await liberarUnExamen(ex.id)
    if (uno.estado === 'liberado') r.liberados.push(ex)
    else if (uno.estado === 'ya_liberado') r.yaLiberados.push(ex)
    else r.fallidos.push({ examen: ex, mensaje: uno.mensaje })
  }
  return r
}
