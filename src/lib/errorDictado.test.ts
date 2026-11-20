import { describe, it, expect } from 'vitest'
import { mensajeErrorDictado, MENSAJES_DICTADO, MENSAJE_GENERICO_DICTADO } from './errorDictado'

const httpError = (body: unknown) => ({
  name: 'FunctionsHttpError',
  message: 'Edge Function returned a non-2xx status code',
  context: { json: async () => body },
})

describe('mensajeErrorDictado (H14)', () => {
  it('sin respuesta del edge («Failed to send a request…»): mensaje de conexión, no el texto crudo', async () => {
    const m = await mensajeErrorDictado({ name: 'FunctionsFetchError', message: 'Failed to send a request to the Edge Function' })
    expect(m).toBe(MENSAJES_DICTADO.red)
    expect(m).not.toContain('Failed to send')
  })

  it('códigos del edge', async () => {
    expect(await mensajeErrorDictado(httpError({ error: 'consentimiento_revocado' }))).toBe(MENSAJES_DICTADO.consentimiento_revocado)
    expect(await mensajeErrorDictado(httpError({ error: 'no_pertenencia' }))).toBe(MENSAJES_DICTADO.no_pertenencia)
    expect(await mensajeErrorDictado(httpError({ error: 'OPENAI_API_KEY no configurada', needsConfig: true }))).toBe(MENSAJES_DICTADO.needs_config)
    expect(await mensajeErrorDictado(httpError({ error: 'Archivo de audio demasiado grande (max 10MB)' }))).toBe(MENSAJES_DICTADO.audio_grande)
  })

  it('un mensaje crudo de Whisper o interno no se muestra: sale el genérico', async () => {
    expect(await mensajeErrorDictado(httpError({ error: 'Whisper HTTP 429' }))).toBe(MENSAJE_GENERICO_DICTADO)
    expect(await mensajeErrorDictado(new Error('algo raro'))).toBe(MENSAJE_GENERICO_DICTADO)
  })

  it('un 2xx con { error } en data también se traduce', async () => {
    expect(await mensajeErrorDictado(null, { error: 'no_auth' })).toBe(MENSAJES_DICTADO.no_auth)
  })
})
