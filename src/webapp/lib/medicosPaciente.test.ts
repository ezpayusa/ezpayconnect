import { describe, it, expect, vi } from 'vitest'
import { nombresMedicosParaPaciente } from './medicosPaciente'
import { formatMedicoNombre } from './formatMedico'

const A = '09d243d5-b222-482a-9762-94a582e9e752'
const B = 'e56879c0-0000-0000-0000-000000000000'

function cliente(rpcRows: unknown[] | null, medRows: unknown[] | null) {
  const inFn = vi.fn(async () => ({ data: medRows, error: null }))
  const select = vi.fn(() => ({ in: inFn }))
  const from = vi.fn(() => ({ select }))
  const rpc = vi.fn(async () => ({ data: rpcRows, error: rpcRows ? null : { message: 'x' } }))
  return { c: { rpc, from } as never, rpc, from, select, inFn }
}

describe('nombresMedicosParaPaciente', () => {
  it('usa la RPC y no consulta medicos si resolvió todos', async () => {
    const k = cliente([{ id: A, nombre_completo: 'Dr. Médico QA', especialidad: null }], [])
    expect(await nombresMedicosParaPaciente([A, A, ''], k.c)).toEqual({ [A]: 'Dr. Médico QA' })
    expect(k.rpc).toHaveBeenCalledWith('obtener_medicos_por_ids', { p_medico_ids: [A] })
    expect(k.from).not.toHaveBeenCalled()
  })

  it('completa con medicos (columnas explícitas) los que la RPC no devolvió', async () => {
    const k = cliente([{ id: A, nombre_completo: 'Ana' }], [{ id: B, nombre_completo: 'Beto' }])
    expect(await nombresMedicosParaPaciente([A, B], k.c)).toEqual({ [A]: 'Ana', [B]: 'Beto' })
    expect(k.from).toHaveBeenCalledWith('medicos')
    expect(k.select).toHaveBeenCalledWith('id, nombre_completo')
    expect(k.inFn).toHaveBeenCalledWith('id', [B])
  })

  it('sin fuentes deja el id sin nombre (el hook pone el placeholder)', async () => {
    const k = cliente(null, null)
    expect(await nombresMedicosParaPaciente([A], k.c)).toEqual({})
  })

  it('sin ids no consulta nada', async () => {
    const k = cliente([], [])
    expect(await nombresMedicosParaPaciente([], k.c)).toEqual({})
    expect(k.rpc).not.toHaveBeenCalled()
  })
})

describe('formatMedicoNombre — sin «Dr. Dr.» ni «Dr.» delante del placeholder', () => {
  it.each([
    ['Médico asignado', 'Médico asignado'],
    ['Médico por asignar', 'Médico por asignar'],
    ['Dr. Médico QA', 'Dr. Médico QA'],
    ['Dra. Ana López', 'Dra. Ana López'],
    ['Ana López', 'Dr. Ana López'],
    [null, 'Médico'],
  ])('%s -> %s', (entrada, esperado) => {
    expect(formatMedicoNombre(entrada)).toBe(esperado)
  })
})
