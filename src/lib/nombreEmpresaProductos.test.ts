import { describe, it, expect } from 'vitest'
import { conNombreEmpresa, idsEmpresa } from './nombreEmpresaProductos'

const prod = (id: string, empresa_id: string | null, empresa: { nombre_empresa?: string | null } | null = null) => ({ id, empresa_id, empresa })

describe('idsEmpresa', () => {
  it('ids distintos y no vacios', () => {
    expect(idsEmpresa([prod('1', 'e1'), prod('2', 'e2'), prod('3', 'e1'), prod('4', null)])).toEqual(['e1', 'e2'])
    expect(idsEmpresa([])).toEqual([])
  })
})

describe('conNombreEmpresa', () => {
  it('completa el nombre del laboratorio (el embed le llega null al medico)', () => {
    const r = conNombreEmpresa([prod('1', 'e1'), prod('2', 'e2', { nombre_empresa: null })], [{ empresa_id: 'e1', nombre_empresa: 'Lab Uno' }, { empresa_id: 'e2', nombre_empresa: 'Lab Dos' }])
    expect(r.map((p) => p.empresa?.nombre_empresa)).toEqual(['Lab Uno', 'Lab Dos'])
  })
  it('best-effort: sin respuesta o sin la empresa, el producto queda igual (no se pierde)', () => {
    const lista = [prod('1', 'e1'), prod('2', 'e9')]
    expect(conNombreEmpresa(lista, null)).toBe(lista)
    expect(conNombreEmpresa(lista, [])).toBe(lista)
    const r = conNombreEmpresa(lista, [{ empresa_id: 'e1', nombre_empresa: 'Lab Uno' }])
    expect(r).toHaveLength(2)
    expect(r[1]).toEqual(prod('2', 'e9'))
  })
  it('una fila sin nombre no pisa nada', () => {
    const lista = [prod('1', 'e1', { nombre_empresa: 'Original' })]
    expect(conNombreEmpresa(lista, [{ empresa_id: 'e1', nombre_empresa: null }])[0].empresa?.nombre_empresa).toBe('Original')
  })
})
