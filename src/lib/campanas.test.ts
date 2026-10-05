import { describe, it, expect, vi, afterEach } from 'vitest'
import { esCampanaVigente } from './campanas'

const HOY = '2026-10-05'
const camp = (activa: boolean | null | undefined, fecha_inicio: string | null | undefined, fecha_fin: string | null | undefined) =>
  ({ activa, fecha_inicio, fecha_fin })

describe('esCampanaVigente — rango de fechas', () => {
  it('vigente en el medio del rango', () => {
    expect(esCampanaVigente(camp(true, '2026-10-01', '2026-10-10'), HOY)).toBe(true)
  })

  it('hoy = fecha_inicio cuenta como vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-10-05', '2026-10-19'), HOY)).toBe(true)
  })

  it('hoy = fecha_fin cuenta como vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-09-20', '2026-10-05'), HOY)).toBe(true)
  })

  it('un día antes del inicio no es vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-10-06', '2026-10-19'), HOY)).toBe(false)
  })

  it('un día después del fin no es vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-09-20', '2026-10-04'), HOY)).toBe(false)
  })
})

describe('esCampanaVigente — fail-closed', () => {
  it('activa false no es vigente', () => {
    expect(esCampanaVigente(camp(false, '2026-10-01', '2026-10-10'), HOY)).toBe(false)
  })

  it('activa null no es vigente', () => {
    expect(esCampanaVigente(camp(null, '2026-10-01', '2026-10-10'), HOY)).toBe(false)
  })

  it('fecha_inicio null no es vigente', () => {
    expect(esCampanaVigente(camp(true, null, '2026-10-10'), HOY)).toBe(false)
  })

  it('fecha_fin null o vacía no es vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-10-01', null), HOY)).toBe(false)
    expect(esCampanaVigente(camp(true, '2026-10-01', ''), HOY)).toBe(false)
  })

  it('inicio > fin no es vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-10-10', '2026-10-01'), HOY)).toBe(false)
  })
})

describe('esCampanaVigente — formato', () => {
  it('con sufijo de hora compara solo los primeros 10 caracteres', () => {
    expect(esCampanaVigente(camp(true, '2026-10-05T23:59:59', '2026-10-19T00:00:00'), HOY)).toBe(true)
    expect(esCampanaVigente(camp(true, '2026-09-20T00:00:00', '2026-10-04T23:59:59'), HOY)).toBe(false)
  })
})

describe('esCampanaVigente — hoy por defecto (hoyISO, día local)', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('sin pasar hoy usa la fecha local del sistema', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 9, 5, 12, 0, 0)) // 5-oct-2026 al mediodía, hora local
    expect(esCampanaVigente(camp(true, '2026-10-05', '2026-10-19'))).toBe(true)
    expect(esCampanaVigente(camp(true, '2026-10-06', '2026-10-19'))).toBe(false)
  })
})

describe('esCampanaVigente — datos reales del recon (prod, 5-oct-2026)', () => {
  it('id 3226 activa 05→19-10 es vigente', () => {
    expect(esCampanaVigente(camp(true, '2026-10-05', '2026-10-19'), HOY)).toBe(true)
  })

  it('id 9 activa 01→31-07 está vencida', () => {
    expect(esCampanaVigente(camp(true, '2026-07-01', '2026-07-31'), HOY)).toBe(false)
  })

  it('id 3183 pausada 04→19-10 no es vigente', () => {
    expect(esCampanaVigente(camp(false, '2026-10-04', '2026-10-19'), HOY)).toBe(false)
  })
})
