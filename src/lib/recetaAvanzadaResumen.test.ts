import { describe, it, expect } from 'vitest'
import { resumenRecetaAvanzada } from './recetaAvanzadaResumen'

const items = [
  { receta_id: 8927, nombre_medicamento: 'Penicilina G benzatínica', dosis: '1.200.000 UI' },
  { receta_id: 8927, nombre_medicamento: 'Paracetamol', dosis: null },
  { receta_id: 8894, nombre_medicamento: 'Ibuprofeno', dosis: '400 mg' },
]

describe('resumenRecetaAvanzada (H24)', () => {
  it('folio oficial y solo los medicamentos de esa receta', () => {
    const r = resumenRecetaAvanzada(
      8927,
      { id: 8927, folio: 'QA-12345-000013-20261119', numero_correlativo: 13, created_at: '2026-11-19T20:36:47Z' },
      items,
    )
    expect(r).toEqual({
      folio: 'QA-12345-000013-20261119',
      medicamentos: ['Penicilina G benzatínica — 1.200.000 UI', 'Paracetamol'],
    })
  })

  it('sin folio guardado: lo reconstruye con la cédula (mismo criterio que H12)', () => {
    const r = resumenRecetaAvanzada(8894, { id: 8894, folio: null, numero_correlativo: 12, created_at: '2026-11-19T15:00:00Z' }, items, 'QA-12345')
    expect(r.folio).toBe('QA-12345-000012-20261119')
    expect(r.medicamentos).toEqual(['Ibuprofeno — 400 mg'])
  })

  it('receta base no legible: «Receta #id» y sin medicamentos, nunca la firma', () => {
    expect(resumenRecetaAvanzada(42, undefined, [])).toEqual({ folio: 'Receta #42', medicamentos: [] })
  })
})
