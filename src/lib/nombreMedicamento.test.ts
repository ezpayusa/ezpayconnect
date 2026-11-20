import { describe, it, expect } from 'vitest'
import { nombreMedicamentoConComercial } from './nombreMedicamento'

describe('nombreMedicamentoConComercial', () => {
  it('genérico con el comercial entre paréntesis', () => {
    expect(nombreMedicamentoConComercial({ nombre_generico: 'Penicilina G benzatínica', nombre_comercial: 'Benzetacil' }))
      .toBe('Penicilina G benzatínica (Benzetacil)')
  })

  it('sin comercial (NULL o vacío), solo el genérico', () => {
    expect(nombreMedicamentoConComercial({ nombre_generico: 'Paracetamol', nombre_comercial: null })).toBe('Paracetamol')
    expect(nombreMedicamentoConComercial({ nombre_generico: 'Paracetamol', nombre_comercial: '  ' })).toBe('Paracetamol')
  })
})
