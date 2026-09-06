import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// El selector de asesor tiene que ofrecer SOLO los del país de la URL. La policy de
// asesores_perfil deja ver varios países a un super_admin, así que sin filtro la pantalla invita a
// asignar un asesor de HN a un prospecto de GT — que crear_prospecto después rechaza con
// PA008/PA009. Un rechazo evitable no es una validación: es una pantalla que dejó elegir mal.
const GT = 'gt-uuid'
const HN = 'hn-uuid'
let asesores: unknown[] = []

vi.mock('@/comercial/lib/api', () => ({
  listarProspectosDePais: async () => ({ data: [], error: null }),
  listarAsesores: async () => ({ data: asesores, error: null }),
  listarTipos: async () => ({ data: [{ codigo: 'farmacia', etiqueta: 'Farmacia', orden: 1 }], error: null }),
  listarEstados: async () => ({ data: [{ codigo: 'nuevo', etiqueta: 'Nuevo', orden: 1 }], error: null }),
  crearProspecto: async () => ({ data: null, error: null }),
  reasignarProspecto: async () => ({ data: null, error: null }),
  asesoresConNombre: async () => ({
    data: [
      { id: 'a-gt', codigo_asesor: 'QA-ASE-GT', nombre_completo: 'Asesor GT', activo: true, supervisor_id: null },
      { id: 'a-hn', codigo_asesor: 'QA-ASE-HN', nombre_completo: 'Asesor HN', activo: true, supervisor_id: null },
    ],
    error: null,
  }),
  mapaAsesores: (f: { id: string }[] | null) => new Map((f ?? []).map(a => [a.id, a])),
  nombreAsesor: (id: string | null, m: Map<string, { nombre_completo: string | null; codigo_asesor: string }>, cod?: string | null) => {
    if (!id) return 'sin asesor'
    const a = m.get(id)
    return a?.nombre_completo ?? a?.codigo_asesor ?? cod ?? 'asesor no visible'
  },
}))
vi.mock('@/comercial/lib/reportarError', () => ({ reportarError: vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

const { default: ProspectosPaisPage } = await import('./ProspectosPaisPage')

const pintar = (paisId: string) => render(
  <MemoryRouter initialEntries={[`/admin/pais/${paisId}/prospectos`]}>
    <Routes><Route path="/admin/pais/:paisId/prospectos" element={<ProspectosPaisPage />} /></Routes>
  </MemoryRouter>,
)

const opcionesDeAsesor = () =>
  Array.from((document.getElementById('asesor_id') as HTMLSelectElement).options)
    .map(o => o.textContent ?? '')
    .filter(t => t !== '— elegir —')

beforeEach(() => {
  asesores = [
    { id: 'a-gt', codigo_asesor: 'QA-ASE-GT', pais_id: GT },
    { id: 'a-hn', codigo_asesor: 'QA-ASE-HN', pais_id: HN },
  ]
})

describe('ProspectosPaisPage — el selector de asesor no cruza países', () => {
  it('en GT ofrece al asesor de GT y NO al de HN', async () => {
    pintar(GT)
    await waitFor(() => expect(document.getElementById('asesor_id')).toBeTruthy())
    const opciones = opcionesDeAsesor()
    expect(opciones).toHaveLength(1)
    expect(opciones[0]).toContain('Asesor GT')
    expect(opciones.join(' ')).not.toContain('HN')
  })

  it('en HN ofrece al de HN: el filtro sigue al país de la URL, no a una lista fija', async () => {
    pintar(HN)
    await waitFor(() => expect(document.getElementById('asesor_id')).toBeTruthy())
    const opciones = opcionesDeAsesor()
    expect(opciones).toHaveLength(1)
    expect(opciones[0]).toContain('Asesor HN')
  })

  it('sin asesores del país, lo DICE en vez de dejar un selector mudo', async () => {
    asesores = [{ id: 'a-hn', codigo_asesor: 'QA-ASE-HN', pais_id: HN }]
    pintar(GT)
    await waitFor(() => {
      expect(screen.getByText('No hay asesores activos en este país.')).toBeInTheDocument()
    })
    expect(opcionesDeAsesor()).toHaveLength(0)
  })

  it('con asesores del país, el aviso NO aparece', async () => {
    pintar(GT)
    await waitFor(() => expect(document.getElementById('asesor_id')).toBeTruthy())
    expect(screen.queryByText('No hay asesores activos en este país.')).not.toBeInTheDocument()
  })

  it('el nombre viene de la RPC, no del código: el código va entre paréntesis', async () => {
    pintar(GT)
    await waitFor(() => expect(document.getElementById('asesor_id')).toBeTruthy())
    expect(opcionesDeAsesor()[0]).toBe('Asesor GT (QA-ASE-GT)')
  })
})
