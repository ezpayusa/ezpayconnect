import { describe, it, expect, vi, beforeEach } from 'vitest'

// resolverNombresMedicos: contrato con la RPC nombres_medicos_visitas (mig 354).
const llamadas: { nombre: string; args: Record<string, unknown> }[] = []
let respuesta: { data: unknown; error: unknown } = { data: [], error: null }

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: Record<string, unknown>) => { llamadas.push({ nombre, args }); return respuesta },
  },
}))

const { resolverNombresMedicos, SIN_NOMBRE, nombreMedico } = await import('./nombresMedicos')

beforeEach(() => { llamadas.length = 0; respuesta = { data: [], error: null } })

describe('resolverNombresMedicos', () => {
  it('sin ids (vacios, null, repetidos de nada) no llama a la RPC', async () => {
    expect(await resolverNombresMedicos([])).toEqual({ mapa: {}, error: null })
    expect(await resolverNombresMedicos([null, undefined, ''])).toEqual({ mapa: {}, error: null })
    expect(llamadas).toHaveLength(0)
  })
  it('llama a nombres_medicos_visitas con los ids unicos y mapea la respuesta', async () => {
    respuesta = { data: [{ medico_id: 'm1', nombre_completo: 'Ana', especialidad: 'Pediatría' }], error: null }
    const r = await resolverNombresMedicos(['m1', 'm2', 'm1', null])
    expect(llamadas).toEqual([{ nombre: 'nombres_medicos_visitas', args: { p_medico_ids: ['m1', 'm2'] } }])
    expect(r.error).toBeNull()
    expect(nombreMedico(r.mapa, 'm1')).toBe('Ana')
    expect(nombreMedico(r.mapa, 'm2')).toBe(SIN_NOMBRE)
  })
  it('propaga el error de la RPC (no lo traga) y devuelve el mapa vacio', async () => {
    const err = { code: '42883', message: 'function does not exist' }
    respuesta = { data: null, error: err }
    const r = await resolverNombresMedicos(['m1'])
    expect(r.error).toBe(err)
    expect(r.mapa).toEqual({})
  })
})
