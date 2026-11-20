import { supabase } from '@/lib/supabase'
import type { DespachoReceta } from '@/webapp/types/webapp.types'

// Token de despacho (QR) de las recetas del paciente — mig 396.
//
// El token ya NO se lee por SELECT directo de recetas_avanzadas: lo devuelve la RPC mis_despachos_receta() (SECURITY
// DEFINER), que solo responde al paciente dueño y solo con tokens VIGENTES. Del embed de recetas_avanzadas quedan las
// columnas que no son secretas (vencimiento y estado), con las que QRDespacho decide «vencido» / «ya despachada».
// El token es secreto del paciente: vive solo en memoria (nunca en console, storage ni URL).

export interface FilaDespachoRpc {
  receta_id: number
  dispatch_token: string
  dispatch_token_expira_at: string | null
  estado_dispensacion: string | null
}

export type FilaAvanzadaPublica = {
  dispatch_token_expira_at: string | null
  estado_dispensacion: DespachoReceta['estado_dispensacion']
}

/** receta_id → token, a partir de la respuesta de la RPC. Si hubiera más de una fila por receta, gana la primera. */
export function tokensPorReceta(filas: FilaDespachoRpc[] | null | undefined): Map<number, string> {
  const m = new Map<number, string>()
  for (const f of filas || []) {
    if (f?.dispatch_token && !m.has(Number(f.receta_id))) m.set(Number(f.receta_id), f.dispatch_token)
  }
  return m
}

/**
 * Arma el despacho de una receta: la fila avanzada (sin token) + el token de la RPC si está vigente. Sin fila avanzada
 * (receta legada) → null. Con fila pero sin token en la RPC (vencido, o la RPC falló) → token null.
 */
export function armarDespacho(
  recetaId: number,
  av: FilaAvanzadaPublica | FilaAvanzadaPublica[] | null | undefined,
  tokens: Map<number, string>,
): DespachoReceta | null {
  const fila = Array.isArray(av) ? av[0] : av
  if (!fila) return null
  return {
    token: tokens.get(recetaId) ?? null,
    expira_at: fila.dispatch_token_expira_at ?? null,
    estado_dispensacion: fila.estado_dispensacion,
  }
}

/** Llama a la RPC. Nunca tira: si falla, devuelve un mapa vacío y ok=false (el QR muestra que no se pudo cargar). */
export async function cargarTokensDespacho(): Promise<{ tokens: Map<number, string>; ok: boolean }> {
  try {
    const { data, error } = await supabase.rpc('mis_despachos_receta')
    if (error) {
      console.error('Error cargando el código de despacho:', error.code ?? 'sin code')
      return { tokens: new Map(), ok: false }
    }
    return { tokens: tokensPorReceta(data as FilaDespachoRpc[]), ok: true }
  } catch {
    return { tokens: new Map(), ok: false }
  }
}
