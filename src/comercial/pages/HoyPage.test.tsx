import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Botón Navegar de /comercial/hoy: se arma con enlacesNavegacion a partir del prospecto que trae
// visitasDeHoyConUbicacion, solo para visitas que todavía se hacen, y FUERA del <Link> de la fila.

const prospecto = (nombre: string, direccion: string | null, lat: number | null, lng: number | null) =>
  ({ nombre, direccion, lat, lng })

const VISITAS = [
  { id: 'v1', estado: 'planificada', prospecto: prospecto('Con pin', 'X', 14.6567083, -90.4967467) },
  { id: 'v2', estado: 'en_curso', prospecto: prospecto('Sin pin', '8A Avenida 15-08, Zona 10', null, null) },
  { id: 'v3', estado: 'realizada', prospecto: prospecto('Cerrada', 'Y', 14.6, -90.5) },
  { id: 'v4', estado: 'planificada', prospecto: prospecto('Sin nada', null, null, null) },
].map(v => ({ ...v, checkin_at: null, checkin_verificado: null, fecha_planificada: '2026-10-19', hora_planificada: null }))

const visitasDeHoyConUbicacion = vi.fn(async (_fecha: string) => ({ data: VISITAS, error: null }))

vi.mock('../lib/api', () => ({
  jornadaDeHoy: async () => ({ data: null, error: null }),
  configVisitasEfectiva: async () => ({ data: [{ precision_max_m: 50 }], error: null }),
  visitasProximas: async () => ({ data: [], error: null }),
  visitasDeHoyConUbicacion: (fecha: string) => visitasDeHoyConUbicacion(fecha),
  abrirJornada: async () => ({ error: null }),
  cerrarJornada: async () => ({ error: null }),
}))
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ perfil: { id: 'ase-1', rol: 'asesor_comercial' } }) }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn(), info: vi.fn() } }))

const { default: HoyPage } = await import('./HoyPage')

const pintar = async () => {
  render(<MemoryRouter><HoyPage /></MemoryRouter>)
  await screen.findByText('Con pin')
}
const fila = (nombre: string) => screen.getByText(nombre).closest('li') as HTMLElement

beforeEach(() => { visitasDeHoyConUbicacion.mockClear() })

describe('HoyPage — botón Navegar', () => {
  it('V1 (planificada, con pin): Navegar y Waze por coordenada, en pestaña nueva, sin aviso de dirección', async () => {
    await pintar()
    const f = within(fila('Con pin'))
    const nav = f.getByRole('link', { name: /navegar/i })
    expect(nav).toHaveAttribute('href',
      'https://www.google.com/maps/dir/?api=1&destination=14.6567083,-90.4967467&travelmode=driving')
    expect(nav).toHaveAttribute('target', '_blank')
    expect(nav).toHaveAttribute('rel', 'noopener noreferrer')
    expect(f.getByRole('link', { name: /waze/i })).toHaveAttribute('href',
      'https://waze.com/ul?ll=14.6567083,-90.4967467&navigate=yes')
    expect(f.queryByText(/Por dirección/)).not.toBeInTheDocument()
  })

  it('V2 (en curso, sin pin): links por dirección y el aviso en la fila', async () => {
    await pintar()
    const f = within(fila('Sin pin'))
    const q = encodeURIComponent('8A Avenida 15-08, Zona 10')
    expect(f.getByRole('link', { name: /navegar/i }).getAttribute('href')).toContain(q)
    expect(f.getByRole('link', { name: /waze/i }).getAttribute('href')).toContain(q)
    expect(f.getByText('Por dirección: este prospecto no tiene ubicación cargada')).toBeInTheDocument()
  })

  it('V3 (realizada): su fila no tiene Navegar ni Waze', async () => {
    await pintar()
    const f = within(fila('Cerrada'))
    expect(f.queryByRole('link', { name: /navegar/i })).not.toBeInTheDocument()
    expect(f.queryByRole('link', { name: /waze/i })).not.toBeInTheDocument()
  })

  it('V4 (planificada, sin coordenada ni dirección): su fila no tiene Navegar', async () => {
    await pintar()
    expect(within(fila('Sin nada')).queryByRole('link', { name: /navegar/i })).not.toBeInTheDocument()
  })

  it('estructura: ningún Navegar está anidado en el Link de la fila, y el Link sigue a la ficha', async () => {
    await pintar()
    // por href y no por nombre: si el <a> quedara dentro del <Link>, el Link de la fila también se
    // llamaría "Navegar" y el conteo fallaría antes de llegar a la pregunta que importa (closest).
    const navegar = Array.from(document.querySelectorAll<HTMLAnchorElement>('a[href^="https://www.google.com/maps/"]'))
    expect(navegar).toHaveLength(2)   // V1 y V2
    for (const a of navegar) {
      expect(a.closest('a[href^="/comercial/visitas/"]')).toBeNull()
    }
    expect(screen.getByText('Con pin').closest('a')).toHaveAttribute('href', '/comercial/visitas/v1')
  })

  it('pide las visitas de hoy una sola vez, con la fecha de hoy', async () => {
    await pintar()
    expect(visitasDeHoyConUbicacion).toHaveBeenCalledTimes(1)
    expect(visitasDeHoyConUbicacion).toHaveBeenCalledWith(new Date().toISOString().slice(0, 10))
  })
})
