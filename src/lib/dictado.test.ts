import { describe, it, expect } from 'vitest'
import { agregarDictado } from './dictado'

describe('agregarDictado (H4)', () => {
  it('campo vacío: queda el dictado', () => {
    expect(agregarDictado('', 'dolor de cabeza')).toBe('dolor de cabeza')
  })

  it('campo con solo espacios: queda el dictado (sin los espacios)', () => {
    expect(agregarDictado('   \n  ', 'dolor de cabeza')).toBe('dolor de cabeza')
  })

  it('texto con salto final: no deja una línea en blanco de más', () => {
    expect(agregarDictado('Fiebre de 3 días\n', 'tos seca')).toBe('Fiebre de 3 días\ntos seca')
    expect(agregarDictado('Fiebre de 3 días  \n\n ', 'tos seca')).toBe('Fiebre de 3 días\ntos seca')
  })

  it('texto normal: agrega en una línea nueva', () => {
    expect(agregarDictado('Fiebre de 3 días', 'tos seca')).toBe('Fiebre de 3 días\ntos seca')
  })

  it('dos dictados seguidos: se acumulan', () => {
    expect(agregarDictado(agregarDictado('Inicio', 'uno'), 'dos')).toBe('Inicio\nuno\ndos')
  })

  it('dictado vacío o solo espacios: el campo no cambia', () => {
    expect(agregarDictado('Fiebre  ', '')).toBe('Fiebre  ')
    expect(agregarDictado('Fiebre', '   ')).toBe('Fiebre')
    expect(agregarDictado('', '')).toBe('')
  })
})
