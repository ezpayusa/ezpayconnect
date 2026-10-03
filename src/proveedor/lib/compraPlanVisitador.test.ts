import { describe, it, expect } from 'vitest'
import {
  mensajeErrorCompraPlan, MENSAJES_SOLICITAR, MENSAJES_APROBAR, MENSAJE_GENERICO_COMPRA,
  esBolsaVigente, configComprable, enteroPositivo, hoyUTC, normalizarMoneda, advertenciaMonedaCuenta,
  cupoPorPais, cupoDelPais, hayCupo, paisOperativo, type BolsaCupo,
  MENSAJE_BOLSA_AGOTADA_VISITADOR, RUTA_COMPRA_PLANES_VISITADOR,
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

describe('cupoPorPais (criterio de private.gate_visita_pais)', () => {
  const HOY = '2026-10-03'
  const b = (over: Partial<BolsaCupo>): BolsaCupo => ({
    pais_id: 'GT', pais_nombre: 'Guatemala', estado: 'activo',
    fecha_inicio: '2026-09-01', fecha_fin: '2026-10-31', restante: 10, ilimitado: false, ...over,
  })

  it('2 bolsas vigentes en el mismo pais -> cuenta solo la de fecha_fin mas lejana (no suma)', () => {
    const cupos = cupoPorPais([
      b({ fecha_fin: '2026-10-31', restante: 10 }),
      b({ fecha_fin: '2027-01-15', restante: 3 }),
      b({ fecha_fin: '2026-12-01', restante: 50 }),
    ], HOY)
    expect(cupos).toHaveLength(1)
    expect(cupos[0]).toMatchObject({ pais_id: 'GT', restante: 3, fecha_fin: '2027-01-15', ilimitado: false })
  })
  it('bolsas en 2 paises -> cupo independiente por pais', () => {
    const cupos = cupoPorPais([
      b({ pais_id: 'GT', restante: 0 }),
      b({ pais_id: 'SV', pais_nombre: 'El Salvador', restante: 7 }),
    ], HOY)
    expect(cupoDelPais(cupos, 'GT')).toMatchObject({ restante: 0 })
    expect(cupoDelPais(cupos, 'SV')).toMatchObject({ restante: 7 })
    expect(hayCupo(cupoDelPais(cupos, 'GT'))).toBe(false)
    expect(hayCupo(cupoDelPais(cupos, 'SV'))).toBe(true)
  })
  it('una ilimitada en otro pais no afecta al pais propio', () => {
    const cupos = cupoPorPais([
      b({ pais_id: 'GT', restante: 0 }),
      b({ pais_id: 'SV', restante: null, ilimitado: true }),
    ], HOY)
    expect(hayCupo(cupoDelPais(cupos, 'GT'))).toBe(false)
    expect(cupoDelPais(cupos, 'SV')).toMatchObject({ ilimitado: true, restante: null })
    expect(hayCupo(cupoDelPais(cupos, 'SV'))).toBe(true)
  })
  it('la elegida es la de fecha_fin mas lejana aunque sea ilimitada (o aunque tenga menos restante)', () => {
    const ilim = cupoPorPais([b({ fecha_fin: '2026-10-31', restante: 5 }), b({ fecha_fin: '2026-11-30', restante: null, ilimitado: true })], HOY)
    expect(ilim[0]).toMatchObject({ ilimitado: true })
    const lim = cupoPorPais([b({ fecha_fin: '2026-11-30', restante: 0 }), b({ fecha_fin: '2026-10-31', restante: null, ilimitado: true })], HOY)
    expect(lim[0]).toMatchObject({ ilimitado: false, restante: 0 })
  })
  it('ignora bolsas no vigentes (vencidas, futuras) y no activas', () => {
    const cupos = cupoPorPais([
      b({ fecha_inicio: '2026-08-01', fecha_fin: '2026-09-30', restante: 9 }),   // vencida
      b({ fecha_inicio: '2026-10-04', fecha_fin: '2027-12-31', restante: 9 }),   // empieza manana
      b({ estado: 'expirado', fecha_fin: '2027-06-30', restante: 9 }),          // no activa
    ], HOY)
    expect(cupos).toEqual([])
    expect(cupoDelPais(cupos, 'GT')).toBeNull()
    expect(hayCupo(null)).toBe(false)
  })
  it('sin pais -> null; restante negativo se lleva a 0', () => {
    expect(cupoDelPais(cupoPorPais([b({})], HOY), null)).toBeNull()
    expect(cupoPorPais([b({ restante: -2 })], HOY)[0].restante).toBe(0)
  })
})

describe('textos del visitador', () => {
  it('el visitador no compra: avisa a su administrador; la compra va al panel del admin', () => {
    expect(MENSAJE_BOLSA_AGOTADA_VISITADOR).toBe('Bolsa agotada · avisale a tu administrador para recargarla')
    expect(RUTA_COMPRA_PLANES_VISITADOR).toBe('/proveedor/visitador/planes')
  })
})

describe('paisOperativo (= private.mi_pais: COALESCE(cuenta.pais_id, empresa.pais_id))', () => {
  it('cuenta con pais distinto del de la empresa -> gana la cuenta', () => {
    expect(paisOperativo({ pais_id: 'SV' }, { pais_id: 'GT' })).toBe('SV')
  })
  it('cuenta sin pais -> el de la empresa', () => {
    expect(paisOperativo({ pais_id: null }, { pais_id: 'GT' })).toBe('GT')
    expect(paisOperativo({}, { pais_id: 'GT' })).toBe('GT')
    expect(paisOperativo(null, { pais_id: 'GT' })).toBe('GT')
  })
  it('sin ninguno -> null', () => {
    expect(paisOperativo(null, null)).toBeNull()
    expect(paisOperativo({ pais_id: null }, { pais_id: null })).toBeNull()
  })
})
