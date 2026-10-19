import { describe, it, expect } from 'vitest'
import { enlacesNavegacion, type Destino } from './navegacion'

const DIR = 'Calle 5 #3-21, Ñuñoa / Zona 10'
const DIR_Q = encodeURIComponent(DIR)

describe('enlacesNavegacion — coordenada válida', () => {
  it('arma las dos URLs exactas por coordenada', () => {
    expect(enlacesNavegacion({ lat: 14.6567083, lng: -90.4967467 })).toEqual({
      googleMaps: 'https://www.google.com/maps/dir/?api=1&destination=14.6567083,-90.4967467&travelmode=driving',
      waze: 'https://waze.com/ul?ll=14.6567083,-90.4967467&navigate=yes',
      porDireccion: false,
    })
  })

  it('con coordenada válida ignora la dirección', () => {
    expect(enlacesNavegacion({ lat: 14.6567083, lng: -90.4967467, direccion: DIR })?.porDireccion).toBe(false)
  })
})

describe('enlacesNavegacion — coordenada inválida cae a la dirección (o a null)', () => {
  it('(0,0) con dirección -> por dirección', () => {
    expect(enlacesNavegacion({ lat: 0, lng: 0, direccion: DIR })?.porDireccion).toBe(true)
  })

  it('(0,0) sin dirección -> null', () => {
    expect(enlacesNavegacion({ lat: 0, lng: 0 })).toBeNull()
  })

  it('lat como string es inválida', () => {
    expect(enlacesNavegacion({ lat: '14.6', lng: -90.5, direccion: DIR })?.porDireccion).toBe(true)
    expect(enlacesNavegacion({ lat: '14.6', lng: -90.5 })).toBeNull()
  })

  it('una sola coordenada es inválida', () => {
    expect(enlacesNavegacion({ lat: 14.6, direccion: DIR })?.porDireccion).toBe(true)
    expect(enlacesNavegacion({ lng: -90.5 })).toBeNull()
    expect(enlacesNavegacion({ lat: 14.6, lng: null })).toBeNull()
  })

  it('fuera de rango o no finita es inválida', () => {
    expect(enlacesNavegacion({ lat: 91, lng: -90.5 })).toBeNull()
    expect(enlacesNavegacion({ lat: 14.6, lng: -181 })).toBeNull()
    expect(enlacesNavegacion({ lat: NaN, lng: -90.5 })).toBeNull()
    expect(enlacesNavegacion({ lat: Infinity, lng: -90.5 })).toBeNull()
  })
})

describe('enlacesNavegacion — por dirección', () => {
  it('espacios, #, ñ y / van encodeURIComponent-eados en las dos URLs (comparación exacta)', () => {
    expect(enlacesNavegacion({ direccion: DIR })).toEqual({
      googleMaps: `https://www.google.com/maps/dir/?api=1&destination=${DIR_Q}&travelmode=driving`,
      waze: `https://waze.com/ul?q=${DIR_Q}&navigate=yes`,
      porDireccion: true,
    })
    // y el encoding es el esperado, no solo "el mismo que usa la función"
    expect(DIR_Q).toBe('Calle%205%20%233-21%2C%20%C3%91u%C3%B1oa%20%2F%20Zona%2010')
  })

  it('la dirección se recorta antes de codificar', () => {
    expect(enlacesNavegacion({ direccion: `  ${DIR}  ` })?.waze).toBe(`https://waze.com/ul?q=${DIR_Q}&navigate=yes`)
  })

  it("dirección '   ' sin coordenada -> null", () => {
    expect(enlacesNavegacion({ direccion: '   ' })).toBeNull()
    expect(enlacesNavegacion({ direccion: null })).toBeNull()
    expect(enlacesNavegacion({})).toBeNull()
  })
})

describe("ninguna URL contiene 'undefined' ni 'null'", () => {
  const casos: Destino[] = [
    { lat: 14.6567083, lng: -90.4967467 },
    { lat: 14.6567083, lng: -90.4967467, direccion: null },
    { lat: 0, lng: 0, direccion: DIR },
    { lat: '14.6', lng: -90.5, direccion: DIR },
    { lat: 14.6, direccion: DIR },
    { lat: null, lng: null, direccion: DIR },
    { direccion: DIR },
  ]
  for (const d of casos) {
    it(JSON.stringify(d), () => {
      const r = enlacesNavegacion(d)
      expect(r).not.toBeNull()
      for (const url of [r!.googleMaps, r!.waze]) {
        expect(url).not.toMatch(/undefined|null/)
      }
    })
  }
})
