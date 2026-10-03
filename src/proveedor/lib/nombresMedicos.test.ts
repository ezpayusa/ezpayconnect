import { describe, it, expect } from 'vitest'
import { idsUnicos, mapaNombres, nombreMedico, SIN_NOMBRE } from './nombresMedicos'

describe('idsUnicos', () => {
  it('saca vacios y repetidos, conserva el orden', () => {
    expect(idsUnicos(['a', null, 'b', 'a', undefined, '', 'c', 'b'])).toEqual(['a', 'b', 'c'])
    expect(idsUnicos([])).toEqual([])
    expect(idsUnicos([null, undefined])).toEqual([])
  })
})

describe('mapaNombres', () => {
  it('mapea id -> nombre y especialidad, recorta espacios y descarta filas sin id', () => {
    const m = mapaNombres([
      { medico_id: 'm1', nombre_completo: ' Ana Pérez ', especialidad: ' Cardiología ' },
      { medico_id: 'm2', nombre_completo: 'Luis Gómez', especialidad: null },
      { medico_id: '', nombre_completo: 'Sin id', especialidad: 'X' },
    ])
    expect(m).toEqual({
      m1: { nombre_completo: 'Ana Pérez', especialidad: 'Cardiología' },
      m2: { nombre_completo: 'Luis Gómez', especialidad: null },
    })
  })
  it('null o vacio -> mapa vacio; especialidad en blanco -> null', () => {
    expect(mapaNombres(null)).toEqual({})
    expect(mapaNombres(undefined)).toEqual({})
    expect(mapaNombres([{ medico_id: 'm1', nombre_completo: 'A', especialidad: '  ' }]).m1.especialidad).toBeNull()
  })
})

describe('nombreMedico', () => {
  const mapa = mapaNombres([{ medico_id: 'm1', nombre_completo: 'Ana Pérez', especialidad: null }, { medico_id: 'm2', nombre_completo: '  ', especialidad: null }])
  it('el nombre resuelto; si no, "Sin nombre" (nunca "Desconocido")', () => {
    expect(nombreMedico(mapa, 'm1')).toBe('Ana Pérez')
    expect(nombreMedico(mapa, 'm9')).toBe(SIN_NOMBRE)
    expect(nombreMedico(mapa, 'm2')).toBe(SIN_NOMBRE)
    expect(nombreMedico(mapa, null)).toBe(SIN_NOMBRE)
    expect(nombreMedico(mapa, undefined)).toBe(SIN_NOMBRE)
    expect(SIN_NOMBRE).toBe('Sin nombre')
  })
})
