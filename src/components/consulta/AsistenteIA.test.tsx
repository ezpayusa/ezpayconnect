import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import AsistenteIA from './AsistenteIA'
import { MENSAJES_ASISTENTE_IA, MENSAJE_GENERICO_ASISTENTE_IA } from '@/lib/errorAsistenteIA'

// H14: un rechazo del edge llega al médico con su motivo (mismo traductor que el Resumen), nunca
// como «Edge Function returned a non-2xx status code».

let invoke: { data: unknown; error: unknown } = { data: null, error: null }

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async () => ({ data: [], error: null }), // consentimientos: sin registros = permitido
    functions: { invoke: async () => invoke },
  },
}))

const httpError = (status: number, body: unknown) => ({
  name: 'FunctionsHttpError',
  message: 'Edge Function returned a non-2xx status code',
  context: new Response(JSON.stringify(body), { status }),
})

const analizar = async () => fireEvent.click(await screen.findByRole('button', { name: /analizar consulta con ia/i }))

beforeEach(() => { invoke = { data: null, error: null } })

describe('AsistenteIA (H14)', () => {
  it('403 no_pertenencia → mensaje traducido, sin el texto crudo', async () => {
    invoke = { data: null, error: httpError(403, { error: 'no_pertenencia' }) }
    render(<AsistenteIA pacienteId={23} />)
    await analizar()
    expect(await screen.findByText(MENSAJES_ASISTENTE_IA.no_pertenencia)).toBeInTheDocument()
    expect(screen.queryByText(/non-2xx/)).toBeNull()
  })

  it('503 needsConfig → aviso «no disponible» para el usuario, sin OPENAI_API_KEY', async () => {
    invoke = { data: null, error: httpError(503, { error: 'OPENAI_API_KEY no configurada', needsConfig: true }) }
    render(<AsistenteIA pacienteId={23} />)
    await analizar()
    expect(await screen.findByText('El asistente no está disponible en este momento. Avisa al administrador.')).toBeInTheDocument()
    expect(screen.queryByText(/OPENAI_API_KEY/)).toBeNull()
  })

  it('sin respuesta del edge → mensaje de conexión', async () => {
    invoke = { data: null, error: { name: 'FunctionsFetchError', message: 'Failed to send a request to the Edge Function' } }
    render(<AsistenteIA pacienteId={23} />)
    await analizar()
    expect(await screen.findByText(MENSAJES_ASISTENTE_IA.red)).toBeInTheDocument()
  })

  it('código desconocido → genérico', async () => {
    invoke = { data: null, error: httpError(500, { error: 'algo_raro' }) }
    render(<AsistenteIA pacienteId={23} />)
    await analizar()
    expect(await screen.findByText(MENSAJE_GENERICO_ASISTENTE_IA)).toBeInTheDocument()
  })
})
