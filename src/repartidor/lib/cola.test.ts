import { describe, it, expect } from 'vitest'
import {
  haversineMetros, ordenarCola, estadoRepartidor, debeRecalcular, formatoDistancia, textoEntregasNuevas, UMBRAL_RECALCULO_M,
} from './cola'
import type { EstadoEntrega } from '@/repartidor/types'

// Zona 10 de Ciudad de Guatemala como referencia
const AQUI = { lat: 14.6000, lng: -90.5100 }
const e = (id: number, estado: EstadoEntrega, lat: number | null, lng: number | null, asignado_at: string | null = null) =>
  ({ entrega_id: id, estado, lat, lng, asignado_at })

describe('haversineMetros', () => {
  it('0 en el mismo punto y ~111 km por grado de latitud', () => {
    expect(haversineMetros(AQUI, AQUI)).toBe(0)
    const d = haversineMetros({ lat: 0, lng: 0 }, { lat: 1, lng: 0 })
    expect(d).toBeGreaterThan(111000)
    expect(d).toBeLessThan(111400)
  })
  it('es simetrica', () => {
    const b = { lat: 14.62, lng: -90.53 }
    expect(haversineMetros(AQUI, b)).toBeCloseTo(haversineMetros(b, AQUI), 6)
  })
})

describe('ordenarCola', () => {
  const lejos = e(1, 'asignada', 14.65, -90.51, '2026-10-03T14:00:00Z')    // ~5,5 km
  const cerca = e(2, 'en_camino', 14.601, -90.51, '2026-10-03T16:00:00Z')  // ~110 m
  const medio = e(3, 'asignada', 14.61, -90.51, '2026-10-03T15:00:00Z')    // ~1,1 km
  const sinCoords = e(4, 'asignada', null, null, '2026-10-03T13:00:00Z')
  const entregada = e(5, 'entregada', 14.6, -90.51, '2026-10-03T12:00:00Z')

  it('con ubicacion: por cercania; sin coordenadas al final; solo asignadas y en camino', () => {
    const r = ordenarCola([lejos, cerca, sinCoords, medio, entregada], AQUI)
    expect(r.criterio).toBe('cercania')
    expect(r.entregas.map((x) => x.entrega_id)).toEqual([2, 3, 1, 4])
    expect(r.distancias.get(2)).toBeLessThan(200)
    expect(r.distancias.has(4)).toBe(false)
  })
  it('sin ubicacion: por hora de asignacion (la mas vieja primero), sin hora al final', () => {
    const sinHora = e(6, 'asignada', 14.6, -90.5, null)
    const r = ordenarCola([lejos, cerca, sinHora, medio, sinCoords], null)
    expect(r.criterio).toBe('asignacion')
    expect(r.entregas.map((x) => x.entrega_id)).toEqual([4, 1, 3, 2, 6])
    expect(r.distancias.size).toBe(0)
  })
  it('una entrega nueva mas cercana pasa a ser la siguiente', () => {
    const nueva = e(7, 'asignada', 14.6002, -90.5101, '2026-10-03T17:00:00Z')
    expect(ordenarCola([lejos, cerca, medio], AQUI).entregas[0].entrega_id).toBe(2)
    expect(ordenarCola([lejos, cerca, medio, nueva], AQUI).entregas[0].entrega_id).toBe(7)
  })
  it('cola sin pendientes -> vacia', () => {
    expect(ordenarCola([entregada], AQUI).entregas).toEqual([])
  })
})

describe('estadoRepartidor', () => {
  it('libre sin asignadas ni en camino; en ruta con alguna', () => {
    expect(estadoRepartidor([])).toBe('libre')
    expect(estadoRepartidor([{ estado: 'entregada' }, { estado: 'fallida' }])).toBe('libre')
    expect(estadoRepartidor([{ estado: 'entregada' }, { estado: 'asignada' }])).toBe('en_ruta')
    expect(estadoRepartidor([{ estado: 'en_camino' }])).toBe('en_ruta')
  })
})

describe('debeRecalcular (umbral de 200 m)', () => {
  it('la primera posicion siempre; despues solo si se movio mas de 200 m', () => {
    expect(UMBRAL_RECALCULO_M).toBe(200)
    expect(debeRecalcular(null, AQUI)).toBe(true)
    expect(debeRecalcular(AQUI, { lat: 14.6010, lng: -90.5100 })).toBe(false)  // ~111 m
    expect(debeRecalcular(AQUI, { lat: 14.6025, lng: -90.5100 })).toBe(true)   // ~278 m
  })
})

describe('textos', () => {
  it('distancia legible y aviso de entregas nuevas', () => {
    expect(formatoDistancia(347)).toBe('350 m')
    expect(formatoDistancia(2400)).toBe('2,4 km')
    expect(textoEntregasNuevas(1)).toBe('Tenés 1 entrega nueva')
    expect(textoEntregasNuevas(3)).toBe('Tenés 3 entregas nuevas')
  })
})
