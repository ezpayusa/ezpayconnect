import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import {
  GuardiaNavegacionProvider,
  navegarConGuardia,
  useGuardiaNavegacion,
  useNavegarConGuardia,
  type GuardiaNavegacion,
} from './guardiaNavegacion'

describe('navegarConGuardia (puro)', () => {
  it('con guardia registrada: llama a la guardia con el destino y no navega', () => {
    const guardia = vi.fn()
    const navigate = vi.fn()
    navegarConGuardia(guardia, navigate, '/medico/recetas')
    expect(guardia).toHaveBeenCalledWith('/medico/recetas')
    expect(navigate).not.toHaveBeenCalled()
  })

  it('sin guardia: navega', () => {
    const navigate = vi.fn()
    navegarConGuardia(null, navigate, '/medico/recetas')
    expect(navigate).toHaveBeenCalledWith('/medico/recetas')
  })

  // H3b: «Cerrar Sesión» pasa el logout como acción previa.
  it('con guardia y acción previa: la guardia recibe las dos y la acción NO corre todavía', async () => {
    const guardia = vi.fn()
    const navigate = vi.fn()
    const logout = vi.fn()
    await navegarConGuardia(guardia, navigate, '/login', logout)
    expect(guardia).toHaveBeenCalledWith('/login', logout)
    expect(logout).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })

  it('sin guardia y con acción previa: primero la acción, después navega', async () => {
    const orden: string[] = []
    const navigate = vi.fn(() => { orden.push('navigate') })
    const logout = vi.fn(async () => { orden.push('logout') })
    await navegarConGuardia(null, navigate, '/login', logout)
    expect(orden).toEqual(['logout', 'navigate'])
    expect(navigate).toHaveBeenCalledWith('/login')
  })
})

function Pantalla({ guardia }: { guardia: GuardiaNavegacion | null }) {
  useGuardiaNavegacion(guardia)
  return <p>consulta</p>
}

function Barra() {
  const ir = useNavegarConGuardia()
  return <button onClick={() => ir('/medico/recetas')}>Mis Recetas</button>
}

function app(guardia: GuardiaNavegacion | null, conPantalla = true) {
  return (
    <MemoryRouter initialEntries={['/medico/consulta/1']}>
      <GuardiaNavegacionProvider>
        <Barra />
        <Routes>
          <Route path="/medico/consulta/:id" element={conPantalla ? <Pantalla guardia={guardia} /> : <p>consulta</p>} />
          <Route path="/medico/recetas" element={<p>recetas</p>} />
        </Routes>
      </GuardiaNavegacionProvider>
    </MemoryRouter>
  )
}

describe('guardia de navegación (provider + hooks)', () => {
  it('registrada: la barra llama a la guardia y se queda en la consulta', () => {
    const guardia = vi.fn()
    render(app(guardia))
    fireEvent.click(screen.getByText('Mis Recetas'))
    expect(guardia).toHaveBeenCalledWith('/medico/recetas')
    expect(screen.getByText('consulta')).toBeInTheDocument()
  })

  it('sin registrar: navega', () => {
    render(app(null))
    fireEvent.click(screen.getByText('Mis Recetas'))
    expect(screen.getByText('recetas')).toBeInTheDocument()
  })

  it('al quitar la guardia (null) vuelve a navegar normal', () => {
    const guardia = vi.fn()
    const { rerender } = render(app(guardia))
    rerender(app(null))
    fireEvent.click(screen.getByText('Mis Recetas'))
    expect(guardia).not.toHaveBeenCalled()
    expect(screen.getByText('recetas')).toBeInTheDocument()
  })

  it('al desmontar la pantalla que la registró, la guardia se quita', () => {
    const guardia = vi.fn()
    const { rerender } = render(app(guardia))
    rerender(app(guardia, false))
    fireEvent.click(screen.getByText('Mis Recetas'))
    expect(guardia).not.toHaveBeenCalled()
    expect(screen.getByText('recetas')).toBeInTheDocument()
  })

  it('sin provider: navega directo', () => {
    render(
      <MemoryRouter initialEntries={['/x']}>
        <Barra />
        <Routes>
          <Route path="/x" element={<p>x</p>} />
          <Route path="/medico/recetas" element={<p>recetas</p>} />
        </Routes>
      </MemoryRouter>,
    )
    fireEvent.click(screen.getByText('Mis Recetas'))
    expect(screen.getByText('recetas')).toBeInTheDocument()
  })
})
