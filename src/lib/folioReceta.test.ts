import { describe, it, expect } from 'vitest'
import { folioReceta } from './folioReceta'

describe('folioReceta (H12)', () => {
  it('1) si la receta tiene folio guardado (mig 395), devuelve ese', () => {
    expect(folioReceta(
      { id: 8900, folio: '12345-000013-20261119', numero_correlativo: 13, created_at: '2026-11-19T20:00:00+00:00' },
      'OTRA',
    )).toBe('12345-000013-20261119')
  })

  it('2) sin folio y con correlativo: misma fórmula que emitir_receta, fecha en UTC', () => {
    // 18-nov 23:30 en GT (UTC-6) = 19-nov 05:30 UTC → la fecha del folio es la UTC.
    const r = { id: 8893, folio: null, numero_correlativo: 11, created_at: '2026-11-19T05:30:00+00:00' }
    expect(folioReceta(r, '12345')).toBe('12345-000011-20261119')
    expect(folioReceta({ ...r, created_at: '2026-11-18T23:30:00-06:00' }, '12345')).toBe('12345-000011-20261119')
    // formato de PostgREST con microsegundos
    expect(folioReceta({ ...r, created_at: '2026-11-19 18:24:50.007406+00' }, '12345')).toBe('12345-000011-20261119')
  })

  it('2b) sin cédula usa SINCED, como emitir_receta', () => {
    const r = { id: 8893, numero_correlativo: 7, created_at: '2026-09-23T09:08:47Z' }
    expect(folioReceta(r)).toBe('SINCED-000007-20260923')
    expect(folioReceta(r, null)).toBe('SINCED-000007-20260923')
    expect(folioReceta(r, '')).toBe('SINCED-000007-20260923')
  })

  it('3) sin folio ni correlativo: REC-<id> marcado como anterior a la numeración', () => {
    expect(folioReceta({ id: 42, folio: null, numero_correlativo: null, created_at: '2026-06-01T10:00:00Z' }, '12345'))
      .toBe('REC-000042 (anterior a la numeración)')
  })
})
