import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// EL MOCK APLICA EL .eq DE VERDAD. Si devolviera siempre las mismas filas, el test de "no cruza
// países" pasaría igual con una pantalla que se OLVIDÓ el .eq('pais_id', …) — que es justo el bug
// que tiene que atrapar. Acá el filtro se registra y se aplica sobre el set completo, así que una
// pantalla sin filtro muestra las dos clínicas y el test se pone rojo.
const GT = 'gt-uuid'
const HN = 'hn-uuid'

const TODAS = [
  { id: 'c-gt-1', nombre: 'Clinica San Rafael', direccion: 'Zona 10', telefono: '2222-1111', activa: true,  pais_id: GT },
  { id: 'c-gt-2', nombre: 'Clinica Sion',       direccion: null,      telefono: null,        activa: false, pais_id: GT },
  { id: 'c-hn-1', nombre: 'Clinica Tegucigalpa', direccion: 'Centro', telefono: '3333-2222', activa: true,  pais_id: HN },
]

let tablas: string[] = []
let errorDeCarga: unknown = null

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: (tabla: string) => {
      tablas.push(tabla)
      const filtros: [string, unknown][] = []
      const q: Record<string, unknown> = {}
      q.select = () => q
      q.order = () => q
      q.eq = (col: string, val: unknown) => { filtros.push([col, val]); return q }
      q.then = (resolver: (v: { data: unknown[] | null; error: unknown }) => unknown) => {
        if (errorDeCarga) return resolver({ data: null, error: errorDeCarga })
        const data = TODAS.filter(f => filtros.every(([c, v]) => (f as Record<string, unknown>)[c] === v))
        return resolver({ data, error: null })
      }
      return q
    },
  },
}))

const reportarError = vi.fn()
vi.mock('@/comercial/lib/reportarError', () => ({ reportarError: (e: unknown) => reportarError(e) }))

const { default: ClinicasPaisPage } = await import('./ClinicasPaisPage')

const pintar = (paisId: string) => render(
  <MemoryRouter initialEntries={[`/admin-ezpay/pais/${paisId}/clinicas`]}>
    <Routes><Route path="/admin-ezpay/pais/:paisId/clinicas" element={<ClinicasPaisPage />} /></Routes>
  </MemoryRouter>,
)

beforeEach(() => {
  tablas = []
  errorDeCarga = null
  reportarError.mockClear()
})

describe('ClinicasPaisPage', () => {
  it('lista las clínicas del país de la URL', async () => {
    pintar(GT)
    await waitFor(() => expect(screen.getByText('Clinica San Rafael')).toBeInTheDocument())
    expect(screen.getByText('Clinica Sion')).toBeInTheDocument()
    expect(screen.getByText('Zona 10')).toBeInTheDocument()
    expect(screen.getByText('2222-1111')).toBeInTheDocument()
  })

  it('consulta la tabla clinicas, no la RPC', async () => {
    pintar(GT)
    await waitFor(() => expect(screen.getByText('Clinica San Rafael')).toBeInTheDocument())
    expect(tablas).toEqual(['clinicas'])
  })

  it('NO cruza países: en GT no aparece la clínica de HN', async () => {
    pintar(GT)
    await waitFor(() => expect(screen.getByText('Clinica San Rafael')).toBeInTheDocument())
    expect(screen.queryByText('Clinica Tegucigalpa')).not.toBeInTheDocument()
  })

  it('el filtro sigue al país de la URL, no a una lista fija: en HN aparece la de HN', async () => {
    pintar(HN)
    await waitFor(() => expect(screen.getByText('Clinica Tegucigalpa')).toBeInTheDocument())
    expect(screen.queryByText('Clinica San Rafael')).not.toBeInTheDocument()
  })

  it('sin clínicas en el país, lo DICE en vez de dejar una tabla muda', async () => {
    pintar('sv-uuid')
    await waitFor(() => {
      expect(screen.getByText('Todavía no hay clínicas en este país.')).toBeInTheDocument()
    })
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('distingue activa de inactiva en el badge', async () => {
    pintar(GT)
    await waitFor(() => expect(screen.getByTestId('clinica-estado-c-gt-1')).toBeInTheDocument())
    expect(screen.getByTestId('clinica-estado-c-gt-1')).toHaveTextContent('activa')
    expect(screen.getByTestId('clinica-estado-c-gt-2')).toHaveTextContent('inactiva')
  })

  it('un campo vacío se pinta como guión, no como celda en blanco', async () => {
    pintar(GT)
    await waitFor(() => expect(screen.getByText('Clinica Sion')).toBeInTheDocument())
    // Clinica Sion viene con direccion y telefono en null: dos guiones en su fila.
    const fila = screen.getByText('Clinica Sion').closest('tr') as HTMLElement
    expect(Array.from(fila.querySelectorAll('td')).filter(td => td.textContent === '—')).toHaveLength(2)
  })

  it('un error de carga va a reportarError y NO deja la pantalla en "Cargando…"', async () => {
    errorDeCarga = { code: '42501', message: 'no_autorizado' }
    pintar(GT)
    await waitFor(() => expect(reportarError).toHaveBeenCalledTimes(1))
    expect(reportarError).toHaveBeenCalledWith({ code: '42501', message: 'no_autorizado' })
    await waitFor(() => {
      expect(screen.getByText('Todavía no hay clínicas en este país.')).toBeInTheDocument()
    })
    expect(screen.queryByText('Cargando…')).not.toBeInTheDocument()
  })
})
