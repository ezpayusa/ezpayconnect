import { describe, it, expect } from 'vitest'
import { contarPorEstado, filtrarPorEstado } from './conteoCitas'

const lista = [
  { id: 1, estado: 'solicitada' },
  { id: 2, estado: 'solicitada' },
  { id: 3, estado: 'agendada' },
  { id: 4, estado: 'completada' },
  { id: 5, estado: 'completada' },
  { id: 6, estado: 'en_espera' },
]

describe('contarPorEstado', () => {
  it('cuenta la lista completa: todos = total y uno por estado', () => {
    expect(contarPorEstado(lista)).toEqual({ todos: 6, solicitada: 2, agendada: 1, completada: 2, en_espera: 1 })
  })

  it('lista vacía: todos = 0', () => {
    expect(contarPorEstado([])).toEqual({ todos: 0 })
  })
})

describe('filtrarPorEstado', () => {
  it("'todos' devuelve la lista entera", () => {
    expect(filtrarPorEstado(lista, 'todos')).toHaveLength(6)
  })

  it('un estado devuelve solo esas citas', () => {
    expect(filtrarPorEstado(lista, 'solicitada').map(c => c.id)).toEqual([1, 2])
  })

  it('el caso reportado: con «Solicitadas» activo los contadores siguen siendo los de la lista completa', () => {
    const visibles = filtrarPorEstado(lista, 'solicitada')
    expect(visibles).toHaveLength(2)
    expect(contarPorEstado(lista).todos).toBe(6)
  })
})
