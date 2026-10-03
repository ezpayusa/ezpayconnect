import { describe, it, expect } from 'vitest'
import {
  mensajeErrorCompraPlan, MENSAJES_SOLICITAR, MENSAJES_APROBAR, MENSAJE_GENERICO_COMPRA,
  esBolsaVigente, configComprable, enteroPositivo, hoyUTC, normalizarMoneda, advertenciaMonedaCuenta,
} from './compraPlanVisitador'

const pg = (code: string, message = 'texto de la base') => ({ code, message })

describe('mensajeErrorCompraPlan — solicitar', () => {
  it.each(['42501', 'CP001', 'CP002', 'CP003', 'CP004', 'CP005', 'CP006', 'CP007'])('%s tiene mensaje propio', (code) => {
    const m = mensajeErrorCompraPlan(pg(code), 'solicitar')
    expect(m).toBe(MENSAJES_SOLICITAR[code])
    expect(m).not.toMatch(/texto de la base/)
  })
  it('un CP desconocido muestra el codigo, no el generico', () => {
    expect(mensajeErrorCompraPlan(pg('CP099'), 'solicitar')).toBe('No se pudo completar la operación (CP099).')
  })
  it('sin codigo (red) o codigo ajeno -> generico', () => {
    expect(mensajeErrorCompraPlan(null, 'solicitar')).toBe(MENSAJE_GENERICO_COMPRA)
    expect(mensajeErrorCompraPlan({ message: 'Failed to fetch' }, 'solicitar')).toBe(MENSAJE_GENERICO_COMPRA)
    expect(mensajeErrorCompraPlan(pg('23505'), 'solicitar')).toBe(MENSAJE_GENERICO_COMPRA)
  })
  it('los codigos de aprobar no se cruzan con solicitar', () => {
    expect(mensajeErrorCompraPlan(pg('CP013'), 'solicitar')).toBe('No se pudo completar la operación (CP013).')
  })
})

describe('mensajeErrorCompraPlan — aprobar', () => {
  it.each(['42501', 'CP010', 'CP011', 'CP012', 'CP013', 'CP014', 'CP015', 'CP016', 'CP017'])('%s tiene mensaje propio', (code) => {
    expect(mensajeErrorCompraPlan(pg(code), 'aprobar')).toBe(MENSAJES_APROBAR[code])
  })
  it('42501 dice cosas distintas segun la operacion', () => {
    expect(mensajeErrorCompraPlan(pg('42501'), 'aprobar')).not.toBe(mensajeErrorCompraPlan(pg('42501'), 'solicitar'))
  })
})

describe('esBolsaVigente (criterio UTC del servidor: fecha_inicio <= hoy <= fecha_fin)', () => {
  const bolsa = { fecha_inicio: '2026-09-04', fecha_fin: '2026-10-03' }

  it('hoyUTC toma la fecha en UTC, no la local', () => {
    expect(hoyUTC(new Date('2026-10-04T00:30:00Z'))).toBe('2026-10-04')
    expect(hoyUTC(new Date('2026-10-03T23:59:00Z'))).toBe('2026-10-03')
  })
  it('18:30 hora de Guatemala del ultimo dia (00:30 UTC del dia siguiente) -> NO vigente', () => {
    const ahora = new Date('2026-10-03T18:30:00-06:00')
    expect(esBolsaVigente(bolsa, hoyUTC(ahora))).toBe(false)
  })
  it('23:59 UTC del ultimo dia -> vigente', () => {
    expect(esBolsaVigente(bolsa, hoyUTC(new Date('2026-10-03T23:59:59Z')))).toBe(true)
  })
  it('fecha_inicio manana -> NO vigente', () => {
    expect(esBolsaVigente({ fecha_inicio: '2026-10-04', fecha_fin: '2026-11-03' }, '2026-10-03')).toBe(false)
  })
  it('bordes inclusivos: el dia de inicio y el de fin son vigentes; el anterior y el siguiente no', () => {
    expect(esBolsaVigente(bolsa, '2026-09-04')).toBe(true)
    expect(esBolsaVigente(bolsa, '2026-10-03')).toBe(true)
    expect(esBolsaVigente(bolsa, '2026-09-03')).toBe(false)
    expect(esBolsaVigente(bolsa, '2026-10-04')).toBe(false)
  })
  it('sin fecha_inicio o sin fecha_fin -> NO vigente', () => {
    expect(esBolsaVigente({ fecha_inicio: null, fecha_fin: '2026-10-03' }, '2026-10-01')).toBe(false)
    expect(esBolsaVigente({ fecha_inicio: '2026-09-04', fecha_fin: '' }, '2026-10-01')).toBe(false)
    expect(esBolsaVigente({}, '2026-10-01')).toBe(false)
  })
  it('acepta timestamps (compara solo la fecha)', () => {
    expect(esBolsaVigente({ fecha_inicio: '2026-09-04T00:00:00Z', fecha_fin: '2026-10-03T00:00:00Z' }, '2026-10-03')).toBe(true)
  })
})

describe('configComprable y enteroPositivo', () => {
  it('solo con visitas y duracion > 0', () => {
    expect(configComprable({ visitas_incluidas: 20, duracion_dias: 30 })).toBe(true)
    expect(configComprable({ visitas_incluidas: null, duracion_dias: 30 })).toBe(false)
    expect(configComprable({ visitas_incluidas: 20, duracion_dias: 0 })).toBe(false)
    expect(configComprable({})).toBe(false)
  })
  it('enteroPositivo', () => {
    expect(enteroPositivo('20')).toBe(20)
    expect(enteroPositivo(30)).toBe(30)
    expect(enteroPositivo('')).toBeNull()
    expect(enteroPositivo('0')).toBeNull()
    expect(enteroPositivo('-3')).toBeNull()
    expect(enteroPositivo('2.5')).toBeNull()
    expect(enteroPositivo('abc')).toBeNull()
    expect(enteroPositivo(null)).toBeNull()
  })
})

describe('normalizarMoneda y advertenciaMonedaCuenta', () => {
  it('normaliza a 3 letras mayusculas', () => {
    expect(normalizarMoneda(' gtq ')).toBe('GTQ')
    expect(normalizarMoneda('USD')).toBe('USD')
    expect(normalizarMoneda('US')).toBeNull()
    expect(normalizarMoneda('USDT')).toBeNull()
    expect(normalizarMoneda('')).toBeNull()
    expect(normalizarMoneda(null)).toBeNull()
  })
  it('avisa solo si la cuenta del pais esta en otra moneda', () => {
    expect(advertenciaMonedaCuenta('USD', 'GTQ')).toBe('La compra fallará: la cuenta bancaria del país está en GTQ')
    expect(advertenciaMonedaCuenta('gtq', 'GTQ')).toBeNull()
    expect(advertenciaMonedaCuenta('GTQ', null)).toBeNull()
    expect(advertenciaMonedaCuenta('', 'GTQ')).toBeNull()
  })
})
