import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom'

let auth: { user: unknown; perfil: unknown; loading: boolean } = { user: null, perfil: null, loading: false }
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => auth }))

const esPacienteActual = vi.fn()
vi.mock('@/lib/esPaciente', () => ({ esPacienteActual: (...a: unknown[]) => esPacienteActual(...a) }))

const { default: RootRedirect } = await import('../RootRedirect')

function Destino() {
  return <div data-testid="destino">{useLocation().pathname}</div>
}

function montar() {
  return render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route path="/" element={<RootRedirect />} />
        <Route path="*" element={<Destino />} />
      </Routes>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  esPacienteActual.mockReset()
})

describe('RootRedirect', () => {
  it('perfil con rol medico → /medico sin llamar a esPacienteActual', async () => {
    auth = { user: { id: 'uid-med' }, perfil: { rol: 'medico', pais_id: 'gt' }, loading: false }
    montar()
    expect((await screen.findByTestId('destino')).textContent).toBe('/medico')
    expect(esPacienteActual).not.toHaveBeenCalled()
  })

  it('perfil null + paciente → /paciente', async () => {
    auth = { user: { id: 'uid-pac' }, perfil: null, loading: false }
    esPacienteActual.mockResolvedValue(true)
    montar()
    expect((await screen.findByTestId('destino')).textContent).toBe('/paciente')
    expect(esPacienteActual).toHaveBeenCalledWith('uid-pac')
  })

  it('perfil null + no paciente → /sin-panel', async () => {
    auth = { user: { id: 'uid-x' }, perfil: null, loading: false }
    esPacienteActual.mockResolvedValue(false)
    montar()
    expect((await screen.findByTestId('destino')).textContent).toBe('/sin-panel')
    expect(esPacienteActual).toHaveBeenCalledWith('uid-x')
  })

  it('sin user → /login sin consultar', async () => {
    auth = { user: null, perfil: null, loading: false }
    montar()
    expect((await screen.findByTestId('destino')).textContent).toBe('/login')
    expect(esPacienteActual).not.toHaveBeenCalled()
  })

  it('mientras carga la sesión → spinner, sin navegar ni consultar', () => {
    auth = { user: null, perfil: null, loading: true }
    montar()
    expect(screen.queryByTestId('destino')).toBeNull()
    expect(esPacienteActual).not.toHaveBeenCalled()
  })
})
