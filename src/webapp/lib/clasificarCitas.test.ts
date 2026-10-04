import { describe, it, expect } from 'vitest'
import { clasificarCitas, citaSinCerrar } from './clasificarCitas'

// "ahora" fijo: 4-oct-2026 a las 10:00 hora LOCAL del entorno del test (combinar arma Dates locales; la comparación es
// consistente en cualquier zona).
const AHORA = new Date(2026, 9, 4, 10, 0, 0)

type C = { id: number; fecha: string; hora_inicio: string; hora_fin: string | null; estado: string }
const cita = (id: number, fecha: string, hora_inicio: string, hora_fin: string | null, estado: string): C =>
  ({ id, fecha, hora_inicio, hora_fin, estado })

describe('clasificarCitas', () => {
  it('(a) confirmada de hace 3 meses va a Pasadas y queda "sin cerrar"', () => {
    const vieja = cita(1, '2026-07-04', '09:00:00', '09:30:00', 'confirmada')
    const r = clasificarCitas([vieja], AHORA)
    expect(r.proximas).toEqual([])
    expect(r.pasadas).toEqual([vieja])
    expect(citaSinCerrar(vieja)).toBe(true)
  })

  it('(b) agendada de hoy cuya hora_fin ya pasó va a Pasadas', () => {
    const c = cita(2, '2026-10-04', '08:00:00', '08:30:00', 'agendada')
    const r = clasificarCitas([c], AHORA)
    expect(r.pasadas).toEqual([c])
    expect(r.proximas).toEqual([])
  })

  it('(c) agendada de hoy que todavía no terminó va a Próximas', () => {
    const empezo = cita(3, '2026-10-04', '09:45:00', '10:15:00', 'agendada')
    const despues = cita(4, '2026-10-04', '15:00:00', null, 'agendada')
    const r = clasificarCitas([empezo, despues], AHORA)
    expect(r.proximas.map((x) => x.id)).toEqual([3, 4])
    expect(r.pasadas).toEqual([])
  })

  it('(d) en_espera de ayer va a Pasadas, sin cerrar', () => {
    const c = cita(5, '2026-10-03', '16:00:00', '16:30:00', 'en_espera')
    const r = clasificarCitas([c], AHORA)
    expect(r.proximas).toEqual([])
    expect(r.pasadas).toEqual([c])
    expect(citaSinCerrar(c)).toBe(true)
  })

  it('(e) cancelada futura va a Canceladas', () => {
    const c = cita(6, '2026-11-01', '09:00:00', '09:30:00', 'cancelada')
    const r = clasificarCitas([c], AHORA)
    expect(r.canceladas).toEqual([c])
    expect(r.proximas).toEqual([])
    expect(r.pasadas).toEqual([])
  })

  it('(g) en_espera de hoy con hora_fin ya pasada sigue en Próximas', () => {
    const c = cita(7, '2026-10-04', '08:00:00', '08:30:00', 'en_espera')
    const r = clasificarCitas([c], AHORA)
    expect(r.proximas).toEqual([c])
    expect(r.pasadas).toEqual([])
  })

  it('(h) en_curso de hace 3 meses va a Pasadas, sin cerrar', () => {
    const c = cita(8, '2026-07-14', '10:00:00', '10:30:00', 'en_curso')
    const r = clasificarCitas([c], AHORA)
    expect(r.proximas).toEqual([])
    expect(r.pasadas).toEqual([c])
    expect(citaSinCerrar(c)).toBe(true)
  })

  it('(f) Próximas ascendente por fecha y hora; Pasadas descendente', () => {
    const lista = [
      cita(10, '2026-10-06', '11:00:00', null, 'confirmada'),
      cita(11, '2026-10-05', '16:00:00', null, 'agendada'),
      cita(12, '2026-10-05', '09:00:00', null, 'solicitada'),
      cita(20, '2026-09-01', '10:00:00', null, 'completada'),
      cita(21, '2026-09-20', '08:00:00', null, 'completada'),
      cita(22, '2026-09-20', '17:00:00', null, 'confirmada'),
    ]
    const r = clasificarCitas(lista, AHORA)
    expect(r.proximas.map((x) => x.id)).toEqual([12, 11, 10])
    expect(r.pasadas.map((x) => x.id)).toEqual([22, 21, 20])
  })
})
