import { describe, it, expect } from 'vitest'
import { parseFechaLocal, parseFechaFlexible } from './fecha'

// H25: una columna DATE ('YYYY-MM-DD') con new Date() cae a medianoche UTC y en GT (UTC−6) se ve
// como el día anterior. parseFechaLocal la deja en el día correcto en cualquier zona.
describe('parseFechaLocal', () => {
  it('fecha de nacimiento: mismo día, mes y año en hora local', () => {
    const d = parseFechaLocal('1990-03-01')
    expect([d.getFullYear(), d.getMonth() + 1, d.getDate()]).toEqual([1990, 3, 1])
    expect(d.getHours()).toBe(0)
  })
})

describe('parseFechaFlexible', () => {
  it("'YYYY-MM-DD' exacto va por parseFechaLocal", () => {
    expect(parseFechaFlexible('2026-11-01').getTime()).toBe(parseFechaLocal('2026-11-01').getTime())
  })

  it('un timestamp se toma como instante (new Date)', () => {
    const iso = '2026-11-19T19:40:36.477Z'
    expect(parseFechaFlexible(iso).getTime()).toBe(new Date(iso).getTime())
  })
})
