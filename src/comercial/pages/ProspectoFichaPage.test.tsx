import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// El 23505 se mapea GENÉRICO a propósito: el mismo código sale de tres UNIQUE distintos y desde
// erroresRpc no se puede saber cuál fue. El contexto lo pone la PANTALLA. Este test fija que, al
// agendar, el usuario vea el texto del contexto y no el genérico.
let rpcError: unknown = null
const rpcs: string[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string) => {
      rpcs.push(nombre)
      return { data: null, error: nombre === 'planificar_visita' ? rpcError : null }
    },
    from: () => {
      const q: Record<string, unknown> = {}
      for (const m of ['select', 'eq', 'order']) q[m] = () => q
      q.maybeSingle = async () => ({
        data: {
          id: 'pros-1', nombre: 'Farmacia QA', tipo: 'farmacia', estado_pipeline: 'nuevo',
          asesor_id: 'ase-1', pais_id: 'gt', direccion: null, lat: null, lng: null, notas: null,
          motivo_perdida: null, empresa_proveedora_id: null, updated_at: '2026-09-05',
        },
        error: null,
      })
      q.then = (r: (v: { data: unknown[]; error: null }) => unknown) => r({ data: [], error: null })
      return q
    },
  },
}))
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ perfil: { id: 'ase-1', rol: 'asesor_comercial' } }) }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

const { default: ProspectoFichaPage } = await import('./ProspectoFichaPage')

const pintar = () => render(
  <MemoryRouter initialEntries={['/comercial/prospectos/pros-1']}>
    <Routes><Route path="/comercial/prospectos/:id" element={<ProspectoFichaPage />} /></Routes>
  </MemoryRouter>,
)

beforeEach(() => { rpcError = null; rpcs.length = 0 })

describe('ProspectoFichaPage — el 23505 al agendar lleva el contexto de la pantalla', () => {
  it('muestra "Ya hay una visita activa para este prospecto ese día", no el genérico del mapa', async () => {
    rpcError = { code: '23505', message: 'duplicate key value violates unique constraint "visitas_com_una_por_dia"' }
    pintar()

    // fireEvent y no user-event: no se agrega una dependencia nueva por un test.
    fireEvent.click(await screen.findByRole('button', { name: /agendar visita/i }))
    fireEvent.click(await screen.findByRole('button', { name: /^agendar$/i }))

    await waitFor(() => {
      expect(screen.getByText('Ya hay una visita activa para este prospecto ese día.')).toBeInTheDocument()
    })
    // el texto genérico del mapa NO se muestra en este contexto
    expect(screen.queryByText(/Ya existe un registro con esos datos/)).not.toBeInTheDocument()
    expect(rpcs).toContain('planificar_visita')
  })

  it('PA026 sí usa el texto del mapa: ese sí es específico y no necesita contexto', async () => {
    rpcError = { code: 'PA026', message: 'fecha_pasada' }
    pintar()

    // fireEvent y no user-event: no se agrega una dependencia nueva por un test.
    fireEvent.click(await screen.findByRole('button', { name: /agendar visita/i }))
    fireEvent.click(await screen.findByRole('button', { name: /^agendar$/i }))

    await waitFor(() => {
      expect(screen.getByText('La fecha ya pasó. Elegí hoy o una fecha futura.')).toBeInTheDocument()
    })
  })
})
