import { describe, it, expect, vi } from 'vitest'

vi.mock('@/lib/supabase', () => ({ supabase: {} }))

const { filtroBusquedaMedicamento } = await import('./useRecetas')

describe('filtroBusquedaMedicamento (H22)', () => {
  it('busca por genérico O comercial', () => {
    expect(filtroBusquedaMedicamento('bactrim')).toBe(
      'nombre_generico.ilike.%bactrim%,nombre_comercial.ilike.%bactrim%',
    )
  })

  it('sin texto no filtra', () => {
    expect(filtroBusquedaMedicamento('')).toBeNull()
    expect(filtroBusquedaMedicamento('   ')).toBeNull()
  })

  it('quita los separadores de la sintaxis or: el texto no rompe ni amplía el filtro', () => {
    expect(filtroBusquedaMedicamento('amox,nombre_generico.ilike.%')).toBe(
      'nombre_generico.ilike.%amox nombre_generico.ilike.%%,nombre_comercial.ilike.%amox nombre_generico.ilike.%%',
    )
    expect(filtroBusquedaMedicamento('pen (g) "x"\\')).toBe(
      'nombre_generico.ilike.%pen g x%,nombre_comercial.ilike.%pen g x%',
    )
  })
})
