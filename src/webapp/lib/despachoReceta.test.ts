import { describe, it, expect, vi, beforeEach } from 'vitest'

let rpcResp: { data: unknown; error: unknown } = { data: [], error: null }
const llamadas: string[] = []
vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string) => { llamadas.push(nombre); return rpcResp },
  },
}))

const { tokensPorReceta, armarDespacho, cargarTokensDespacho } = await import('./despachoReceta')

const TOKEN = 'a'.repeat(64)
beforeEach(() => { rpcResp = { data: [], error: null }; llamadas.length = 0 })

describe('despacho de la receta del paciente (mig 396)', () => {
  it('el token sale de la RPC mis_despachos_receta, por receta_id', async () => {
    rpcResp = { data: [{ receta_id: 8927, dispatch_token: TOKEN, dispatch_token_expira_at: '2026-12-01T00:00:00Z', estado_dispensacion: 'pendiente' }], error: null }
    const { tokens, ok } = await cargarTokensDespacho()
    expect(llamadas).toEqual(['mis_despachos_receta'])
    expect(ok).toBe(true)
    expect(tokens.get(8927)).toBe(TOKEN)
  })

  it('si la RPC falla: mapa vacío y ok=false, sin tirar', async () => {
    rpcResp = { data: null, error: { code: 'PGRST202', message: 'no existe' } }
    const r = await cargarTokensDespacho()
    expect(r.ok).toBe(false)
    expect(r.tokens.size).toBe(0)
  })

  it('armarDespacho: fila avanzada + token vigente', () => {
    const d = armarDespacho(8927, { dispatch_token_expira_at: '2026-12-01T00:00:00Z', estado_dispensacion: 'pendiente' }, tokensPorReceta([
      { receta_id: 8927, dispatch_token: TOKEN, dispatch_token_expira_at: '2026-12-01T00:00:00Z', estado_dispensacion: 'pendiente' },
    ]))
    expect(d).toEqual({ token: TOKEN, expira_at: '2026-12-01T00:00:00Z', estado_dispensacion: 'pendiente' })
  })

  it('armarDespacho: fila avanzada sin token en la RPC (vencido) → token null, conserva vencimiento y estado', () => {
    const d = armarDespacho(8894, [{ dispatch_token_expira_at: '2026-10-01T00:00:00Z', estado_dispensacion: 'pendiente' }], new Map())
    expect(d).toEqual({ token: null, expira_at: '2026-10-01T00:00:00Z', estado_dispensacion: 'pendiente' })
  })

  it('armarDespacho: sin fila avanzada (receta legada) → null', () => {
    expect(armarDespacho(1, null, new Map([[1, TOKEN]]))).toBeNull()
    expect(armarDespacho(1, [], new Map([[1, TOKEN]]))).toBeNull()
  })
})
