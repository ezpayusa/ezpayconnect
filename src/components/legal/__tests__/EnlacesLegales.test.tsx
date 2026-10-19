import { describe, it, expect, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { TEXTOS_LEGALES } from '@/legal/catalogo'
import { CasillaTextosLegales, DECLARACION_MAYORIA_EDAD } from '../CasillaTextosLegales'

const rpc = vi.fn()
const from = vi.fn()
vi.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a), from: (...a: unknown[]) => from(...a) } }))

const obtenerPendientes = vi.fn()
const aceptarTextos = vi.fn()
const aceptarEnRegistro = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  obtenerPendientes: (...a: unknown[]) => obtenerPendientes(...a),
  aceptarTextos: (...a: unknown[]) => aceptarTextos(...a),
  aceptarEnRegistro: (...a: unknown[]) => aceptarEnRegistro(...a),
}))

const { EnlacesLegales } = await import('../EnlacesLegales')

const texto = (codigo: string) => TEXTOS_LEGALES.find((t) => t.codigo === codigo)!
const linkDe = (codigo: string) => screen.queryByRole('link', { name: new RegExp(texto(codigo).titulo) })

describe('EnlacesLegales', () => {
  it('paciente → términos, privacidad y consentimiento de salud con las rutas del catálogo; sin condiciones profesionales', () => {
    render(<EnlacesLegales para="paciente" />)
    expect(screen.getAllByRole('link')).toHaveLength(3)
    for (const c of ['terminos', 'privacidad', 'consentimiento_salud']) expect(linkDe(c)).toHaveAttribute('href', texto(c).ruta)
    expect(linkDe('condiciones_profesionales')).toBeNull()
  })

  it('profesional → términos, privacidad y condiciones profesionales; sin consentimiento de salud', () => {
    render(<EnlacesLegales para="profesional" />)
    expect(screen.getAllByRole('link')).toHaveLength(3)
    for (const c of ['terminos', 'privacidad', 'condiciones_profesionales']) expect(linkDe(c)).toHaveAttribute('href', texto(c).ruta)
    expect(linkDe('consentimiento_salud')).toBeNull()
  })

  it('target y rel iguales a los de CasillaTextosLegales', () => {
    const casilla = render(<CasillaTextosLegales para="profesional" checked={false} onChange={() => {}} />)
    const deCasilla = casilla.getAllByRole('link').map((a) => [a.getAttribute('target'), a.getAttribute('rel')])
    casilla.unmount()
    render(<EnlacesLegales para="profesional" />)
    const deEnlaces = screen.getAllByRole('link').map((a) => [a.getAttribute('target'), a.getAttribute('rel')])
    expect(deEnlaces).toEqual(deCasilla)
    expect(deEnlaces[0]).toEqual(['_blank', 'noopener noreferrer'])
  })

  it('va dentro de un nav con aria-label "Textos legales"', () => {
    render(<EnlacesLegales para="paciente" className="mt-6" />)
    const nav = screen.getByRole('navigation', { name: 'Textos legales' })
    expect(within(nav).getAllByRole('link')).toHaveLength(3)
    expect(nav).toHaveClass('mt-6')
  })

  it('no muestra la declaración de mayoría de edad', () => {
    render(<EnlacesLegales para="paciente" />)
    expect(screen.queryByText(DECLARACION_MAYORIA_EDAD, { exact: false })).toBeNull()
  })

  it('no llama a supabase ni a @/lib/textosLegales', () => {
    render(<EnlacesLegales para="paciente" />)
    render(<EnlacesLegales para="profesional" />)
    for (const f of [rpc, from, obtenerPendientes, aceptarTextos, aceptarEnRegistro]) expect(f).not.toHaveBeenCalled()
  })
})
