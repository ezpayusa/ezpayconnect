// Errores del edge asistente-ia → motivo en español para el médico.
//
// supabase-js, ante una respuesta no-2xx, NO entrega el body en `data`: devuelve un FunctionsHttpError
// cuyo `message` es el genérico "Edge Function returned a non-2xx status code" y deja la Response en
// `error.context`. El código que manda el edge ({ error: '<codigo>' }) hay que leerlo de ahí.
// FunctionsFetchError / FunctionsRelayError = no hubo respuesta del edge (red, relay).

export const MENSAJES_ASISTENTE_IA: Record<string, string> = {
  no_auth: 'Tu sesión expiró. Volvé a iniciar sesión.',
  no_pertenencia: 'No tenés acceso a este paciente para usar el asistente de IA.',
  consentimiento_revocado: 'El paciente revocó el consentimiento para el uso de IA.',
  sin_permiso: 'Tu usuario no tiene permiso para usar el asistente de IA.',
  paciente_no_encontrado: 'No se encontró el paciente.',
  consulta_invalida: 'La nota de la consulta no corresponde a este paciente.',
  respuesta_ia_invalida: 'La IA devolvió una respuesta con formato inválido. Probá volver a generar.',
  error_contexto: 'No se pudo leer el expediente del paciente. Intentá de nuevo.',
  asistente_timeout: 'El asistente de IA tardó demasiado en responder. Intentá de nuevo.',
  asistente_no_disponible: 'El asistente de IA no está disponible en este momento (límite de uso). Intentá más tarde.',
  error_openai: 'El asistente de IA tuvo un error. Intentá de nuevo en unos minutos.',
  needs_config: 'El asistente de IA no está configurado. Contactá al administrador.',
  red: 'No se pudo conectar con el asistente de IA. Revisá tu conexión e intentá de nuevo.',
}

export const MENSAJE_GENERICO_ASISTENTE_IA = 'El asistente de IA tuvo un error inesperado. Intentá de nuevo.'

const esCodigoConocido = (c: unknown): c is string =>
  typeof c === 'string' && Object.prototype.hasOwnProperty.call(MENSAJES_ASISTENTE_IA, c)

export function mensajeErrorAsistenteIA(codigo: string | null | undefined): string {
  return esCodigoConocido(codigo) ? MENSAJES_ASISTENTE_IA[codigo] : MENSAJE_GENERICO_ASISTENTE_IA
}

type ErrorInvoke = { name?: string; context?: unknown } | null | undefined

// Código de error a partir del `error` de functions.invoke (y del `data`, por si un 2xx trae { error }).
// Nunca tira: lo que no se reconoce devuelve null y se pinta el genérico.
export async function codigoErrorAsistenteIA(error: unknown, data?: unknown): Promise<string | null> {
  const e = error as ErrorInvoke
  if (e?.name === 'FunctionsFetchError' || e?.name === 'FunctionsRelayError') return 'red'

  let body: unknown = data
  const ctx = e?.context as { json?: () => Promise<unknown> } | undefined
  if (ctx && typeof ctx.json === 'function') {
    try { body = await ctx.json() } catch { body = null }
  }
  if (body && typeof body === 'object') {
    const b = body as { error?: unknown; needsConfig?: unknown }
    if (b.needsConfig === true) return 'needs_config'
    if (esCodigoConocido(b.error)) return b.error
  }
  return null
}

export async function motivoErrorAsistenteIA(error: unknown, data?: unknown): Promise<string> {
  return mensajeErrorAsistenteIA(await codigoErrorAsistenteIA(error, data))
}
