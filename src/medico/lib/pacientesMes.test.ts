import { describe, it, expect } from 'vitest'
import { contarPacientesDistintos } from './pacientesMes'

describe('contarPacientesDistintos («Pacientes (mes)»)', () => {
  it('el caso de la demo: 1 cita en curso y 3 recetas del mismo paciente = 1', () => {
    expect(contarPacientesDistintos([{ paciente_id: 23 }], [{ paciente_id: 23 }, { paciente_id: 23 }, { paciente_id: 23 }])).toBe(1)
  })

  it('unión: pacientes solo con cita y solo con receta se suman sin repetir', () => {
    expect(contarPacientesDistintos(
      [{ paciente_id: 1 }, { paciente_id: 2 }],
      [{ paciente_id: 2 }, { paciente_id: 3 }],
    )).toBe(3)
  })

  it('el mismo id como número y como texto es un solo paciente', () => {
    expect(contarPacientesDistintos([{ paciente_id: 7 }], [{ paciente_id: '7' }])).toBe(1)
  })

  it('sin filas da 0 y las filas sin paciente no cuentan', () => {
    expect(contarPacientesDistintos([], [])).toBe(0)
    expect(contarPacientesDistintos([{ paciente_id: null }], [{ paciente_id: 4 }])).toBe(1)
  })
})
