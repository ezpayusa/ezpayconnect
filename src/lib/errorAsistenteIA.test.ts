import { describe, it, expect } from 'vitest'
import {
  codigoErrorAsistenteIA, mensajeErrorAsistenteIA, motivoErrorAsistenteIA,
  MENSAJES_ASISTENTE_IA, MENSAJE_GENERICO_ASISTENTE_IA,
} from './errorAsistenteIA'

// Forma real de supabase-js ante un no-2xx: FunctionsHttpError con la Response en `context`.
const httpError = (status: number, body: unknown) => ({
  name: 'FunctionsHttpError',
  message: 'Edge Function returned a non-2xx status code',
  context: new Response(typeof body === 'string' ? body : JSON.stringify(body), { status }),
})

describe('codigoErrorAsistenteIA', () => {
  it.each([
    [401, 'no_auth'], [403, 'no_pertenencia'], [403, 'consentimiento_revocado'], [403, 'sin_permiso'],
    [404, 'paciente_no_encontrado'], [502, 'respuesta_ia_invalida'], [500, 'error_contexto'],
    [504, 'asistente_timeout'], [400, 'consulta_invalida'],
  ])('HTTP %i { error: %s } → ese código', async (status, codigo) => {
    expect(await codigoErrorAsistenteIA(httpError(status, { error: codigo }))).toBe(codigo)
  })

  it('needsConfig → needs_config', async () => {
    expect(await codigoErrorAsistenteIA(httpError(503, { error: 'OPENAI_API_KEY no configurada.', needsConfig: true }))).toBe('needs_config')
  })

  it('sin respuesta del edge (fetch / relay) → red', async () => {
    expect(await codigoErrorAsistenteIA({ name: 'FunctionsFetchError', context: new TypeError('Failed to fetch') })).toBe('red')
    expect(await codigoErrorAsistenteIA({ name: 'FunctionsRelayError', context: {} })).toBe('red')
  })

  it('body no JSON, código desconocido o error sin context → null (genérico)', async () => {
    expect(await codigoErrorAsistenteIA(httpError(500, '<html>'))).toBeNull()
    expect(await codigoErrorAsistenteIA(httpError(500, { error: 'algo_nuevo' }))).toBeNull()
    expect(await codigoErrorAsistenteIA(new Error('boom'))).toBeNull()
    expect(await codigoErrorAsistenteIA(null)).toBeNull()
    expect(await codigoErrorAsistenteIA(httpError(500, { error: 'constructor' }))).toBeNull()
  })

  it('un 2xx con { error } en data también se lee', async () => {
    expect(await codigoErrorAsistenteIA(null, { error: 'no_pertenencia' })).toBe('no_pertenencia')
  })
})

describe('mensajes', () => {
  it('cada código tiene su motivo; lo desconocido cae al genérico y nunca dice non-2xx', async () => {
    for (const [codigo, msg] of Object.entries(MENSAJES_ASISTENTE_IA)) expect(mensajeErrorAsistenteIA(codigo)).toBe(msg)
    expect(mensajeErrorAsistenteIA(null)).toBe(MENSAJE_GENERICO_ASISTENTE_IA)
    expect(mensajeErrorAsistenteIA('constructor')).toBe(MENSAJE_GENERICO_ASISTENTE_IA)
    const m = await motivoErrorAsistenteIA(httpError(403, { error: 'consentimiento_revocado' }))
    expect(m).toBe('El paciente revocó el consentimiento para el uso de IA.')
    expect(await motivoErrorAsistenteIA(httpError(500, 'x'))).not.toMatch(/non-2xx/)
  })
})
