import { describe, it, expect } from 'vitest'
import {
  mensajeErrorCompraPlan, MENSAJES_SOLICITAR, MENSAJES_APROBAR, MENSAJE_GENERICO_COMPRA,
  esBolsaVigente, configComprable, enteroPositivo, hoyISO, normalizarMoneda, advertenciaMonedaCuenta,
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

describe('esBolsaVigente', () => {
  it('fecha_fin hoy o futura -> vigente; pasada o vacia -> no', () => {
    expect(esBolsaVigente('2026-10-03', '2026-10-03')).toBe(true)
    expect(esBolsaVigente('2027-06-12', '2026-10-03')).toBe(true)
    expect(esBolsaVigente('2026-10-02', '2026-10-03')).toBe(false)
    expect(esBolsaVigente(null, '2026-10-03')).toBe(false)
    expect(esBolsaVigente('', '2026-10-03')).toBe(false)
  })
  it('acepta timestamps (compara solo la fecha)', () => {
    expect(esBolsaVigente('2026-10-03T00:00:00Z', '2026-10-03')).toBe(true)
  })
  it('hoyISO usa la fecha local', () => {
    expect(hoyISO(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05')
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
