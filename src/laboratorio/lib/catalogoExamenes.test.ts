import { describe, it, expect } from 'vitest'
import { mensajeErrorCatalogo, esExamenReferenciado, CODIGO_EXAMEN_REFERENCIADO } from './catalogoExamenes'

// Mig 369: los rechazos de las RPCs del catálogo (EX035-EX039) traen el mensaje para el usuario; el resto (42501 incluido)
// se muestra con un texto genérico. EX038 (ya ordenado) es el caso en que la pantalla ofrece desactivar.
describe('mensajeErrorCatalogo', () => {
  it('EX035-EX039: el mensaje tal cual', () => {
    for (const code of ['EX035', 'EX036', 'EX037', 'EX038', 'EX039']) {
      expect(mensajeErrorCatalogo({ code, message: `mensaje ${code}` }, 'generico')).toBe(`mensaje ${code}`)
    }
  })

  it('cualquier otro código: el texto genérico, sin detalles internos', () => {
    expect(mensajeErrorCatalogo({ code: '42501', message: 'permission denied for table examenes_catalogo' }, 'No se pudo eliminar'))
      .toBe('No se pudo eliminar')
    expect(mensajeErrorCatalogo({ code: '23505', message: 'duplicate key value violates unique constraint "ux_…"' }, 'No se pudo agregar el examen'))
      .toBe('No se pudo agregar el examen')
    expect(mensajeErrorCatalogo({ code: 'PGRST202', message: 'Could not find the function' }, 'generico')).toBe('generico')
  })

  it('sin error (la RPC no devolvió id) o sin mensaje: el genérico', () => {
    expect(mensajeErrorCatalogo(null, 'generico')).toBe('generico')
    expect(mensajeErrorCatalogo(undefined, 'generico')).toBe('generico')
    expect(mensajeErrorCatalogo({ code: 'EX036', message: '' }, 'generico')).toBe('generico')
  })
})

describe('esExamenReferenciado', () => {
  it('solo EX038 ofrece desactivar', () => {
    expect(CODIGO_EXAMEN_REFERENCIADO).toBe('EX038')
    expect(esExamenReferenciado({ code: 'EX038' })).toBe(true)
    expect(esExamenReferenciado({ code: '23503' })).toBe(false)
    expect(esExamenReferenciado({ code: 'EX036' })).toBe(false)
    expect(esExamenReferenciado(null)).toBe(false)
  })
})
