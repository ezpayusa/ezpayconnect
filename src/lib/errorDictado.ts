// H14: errores del edge dictado-voz → mensaje claro en español (en tú) para el médico.
//
// Mismo criterio que src/lib/errorAsistenteIA.ts: supabase-js, ante una respuesta no-2xx, devuelve un
// FunctionsHttpError con un `message` genérico y deja la Response en `error.context`; el código que
// manda el edge ({ error: '<codigo>' }) se lee de ahí. FunctionsFetchError / FunctionsRelayError = no
// hubo respuesta («Failed to send a request to the Edge Function»: red, CORS, relay). Nunca se muestra
// el texto crudo del error: el edge también puede devolver mensajes de Whisper o internos.

export const MENSAJES_DICTADO: Record<string, string> = {
  red: 'No se pudo conectar con el servicio de dictado. Revisa tu conexión e intenta de nuevo.',
  no_auth: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  no_pertenencia: 'No tienes acceso a este paciente para usar el dictado.',
  consentimiento_revocado: 'El paciente revocó el consentimiento para grabar la consulta.',
  gate_denegado: 'No tienes permiso para usar el dictado con este paciente.',
  needs_config: 'El dictado no está configurado. Contacta al administrador.',
  audio_grande: 'El audio es demasiado largo (máximo 10 MB). Graba un fragmento más corto.',
}

export const MENSAJE_GENERICO_DICTADO = 'No se pudo transcribir el audio. Intenta de nuevo.'

type ErrorInvoke = { name?: string; context?: unknown } | null | undefined

/** Código a partir del `error` de functions.invoke (y del `data`, por si un 2xx trae { error }). Nunca tira. */
export async function codigoErrorDictado(error: unknown, data?: unknown): Promise<string | null> {
  const e = error as ErrorInvoke
  if (e?.name === 'FunctionsFetchError' || e?.name === 'FunctionsRelayError') return 'red'

  let body: unknown = data
  const ctx = e?.context as { json?: () => Promise<unknown> } | undefined
  if (ctx && typeof ctx.json === 'function') {
    try { body = await ctx.json() } catch { body = null }
  }
  if (body && typeof body === 'object') {
    const b = body as { error?: unknown; needsConfig?: unknown }
    if (b.needsConfig === true || b.error === 'config_supabase') return 'needs_config'
    if (typeof b.error === 'string') {
      if (Object.prototype.hasOwnProperty.call(MENSAJES_DICTADO, b.error)) return b.error
      if (/demasiado grande/i.test(b.error)) return 'audio_grande'
    }
  }
  return null
}

export async function mensajeErrorDictado(error: unknown, data?: unknown): Promise<string> {
  const codigo = await codigoErrorDictado(error, data)
  return codigo ? MENSAJES_DICTADO[codigo] : MENSAJE_GENERICO_DICTADO
}
