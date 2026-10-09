import { supabase } from '@/lib/supabase'
import { TEXTOS_LEGALES, type CodigoTextoLegal, type TextoLegal } from '@/legal/catalogo'

// GL-02 (migs 371/372): capa de datos de los textos legales.
//   textos_legales_pendientes() → filas {codigo, version} que el llamante tiene que aceptar.
//   aceptar_textos_legales(p_textos, p_via, p_user_agent) → {aceptados, ya_aceptados, pendientes}.
// Rechazos de la base con errcode LG001-LG006 y un mensaje ya escrito para el usuario final, sin eco de lo que manda el
// cliente: se muestran tal cual. Cualquier otro error (42501 incluido: su texto es el de Postgres) va con texto fijo.
//   LG001 sin sesión · LG002 código inexistente · LG003 versión no vigente · LG004 entrada inválida
//   LG005 aceptaciones append-only · LG006 el texto no corresponde a la identidad de la cuenta
//
// Falla cerrado: si la base pide un código que el front no conoce, o una versión distinta de la del catálogo de
// src/legal, el front no puede mostrar el texto que se estaría aceptando → error, nunca una lista parcial.

export interface ErrorTextosLegales {
  code?: string | null
  message?: string | null
}

export type ResultadoPendientes =
  | { ok: true; pendientes: TextoLegal[] }
  | { ok: false; error: ErrorTextosLegales }

export interface RespuestaAceptar {
  aceptados: number
  ya_aceptados: number
  pendientes: { codigo: string; version: string }[]
}

export type ResultadoAceptar =
  | { ok: true; data: RespuestaAceptar }
  | { ok: false; error: ErrorTextosLegales }

export type ViaAceptacion = 'registro' | 'login' | 'app'

const ERROR_CATALOGO: ErrorTextosLegales = { code: null, message: 'catálogo de textos legales desincronizado' }

const CODIGOS_CON_MENSAJE = new Set(['LG001', 'LG002', 'LG003', 'LG004', 'LG005', 'LG006'])

export const MENSAJE_SIN_PERMISO = 'No tienes permiso para esta acción.'
export const MENSAJE_GENERICO = 'No pudimos procesar los textos legales. Inténtalo de nuevo.'

export async function obtenerPendientes(): Promise<ResultadoPendientes> {
  try {
    const { data, error } = await supabase.rpc('textos_legales_pendientes')
    if (error) {
      console.error('[textosLegales] pendientes falló', error?.code)
      return { ok: false, error }
    }
    if (!Array.isArray(data)) return { ok: false, error: ERROR_CATALOGO }
    const pendientes: TextoLegal[] = []
    for (const fila of data as { codigo?: unknown; version?: unknown }[]) {
      const texto = TEXTOS_LEGALES.find((t) => t.codigo === fila?.codigo)
      if (!texto || texto.version !== fila?.version) {
        console.error('[textosLegales] catálogo del front desincronizado con la base')
        return { ok: false, error: ERROR_CATALOGO }
      }
      pendientes.push(texto)
    }
    return { ok: true, pendientes }
  } catch (err) {
    console.error('[textosLegales] pendientes lanzó', (err as { code?: string } | null)?.code)
    return { ok: false, error: { code: null, message: null } }
  }
}

export async function aceptarTextos(
  textos: { codigo: CodigoTextoLegal; version: string }[],
  via: ViaAceptacion,
): Promise<ResultadoAceptar> {
  try {
    const p_user_agent = typeof navigator !== 'undefined' ? (navigator.userAgent ?? null) : null
    const p_textos = textos.map((t) => ({ codigo: t.codigo, version: t.version }))
    const { data, error } = await supabase.rpc('aceptar_textos_legales', { p_textos, p_via: via, p_user_agent })
    if (error) {
      console.error('[textosLegales] aceptar falló', error?.code)
      return { ok: false, error }
    }
    return { ok: true, data: data as RespuestaAceptar }
  } catch (err) {
    console.error('[textosLegales] aceptar lanzó', (err as { code?: string } | null)?.code)
    return { ok: false, error: { code: null, message: null } }
  }
}

export function mensajeErrorTextosLegales(error: ErrorTextosLegales | null | undefined): string {
  if (error?.code && CODIGOS_CON_MENSAJE.has(error.code) && error.message) return error.message
  if (error?.code === '42501') return MENSAJE_SIN_PERMISO
  return MENSAJE_GENERICO
}
