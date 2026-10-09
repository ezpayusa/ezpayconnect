import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

const navigate = vi.fn()
vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => navigate,
}))

const login = vi.fn()
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ login }) }))

const esPacienteActual = vi.fn()
vi.mock('@/lib/esPaciente', () => ({ esPacienteActual: (...a: unknown[]) => esPacienteActual(...a) }))

vi.mock('@/lib/enviarReset', () => ({ enviarReset: vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

// supabase simulado: getUser y la consulta a perfiles (from().select().eq().single()).
let perfilRespuesta: { data: unknown; error: unknown } = { data: null, error: null }
const getUser = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser: () => getUser() },
    from: () => ({ select: () => ({ eq: () => ({ single: async () => perfilRespuesta }) }) }),
  },
}))

const { default: LoginPage } = await import('../LoginPage')

function entrar() {
  const { container } = render(
    <MemoryRouter>
      <LoginPage />
    </MemoryRouter>,
  )
  fireEvent.change(container.querySelector('#email')!, { target: { value: 'u@x.com' } })
  fireEvent.change(container.querySelector('#password')!, { target: { value: 'secreta123' } })
  fireEvent.click(screen.getByRole('button', { name: /Iniciar Sesión/ }))
}

beforeEach(() => {
  navigate.mockReset()
  login.mockReset().mockResolvedValue({ error: null })
  esPacienteActual.mockReset()
  getUser.mockReset().mockResolvedValue({ data: { user: { id: 'uid-1' } } })
  perfilRespuesta = { data: null, error: null }
})

describe('LoginPage: destino después del login', () => {
  it('login OK + perfil medico → /medico, sin esPacienteActual', async () => {
    perfilRespuesta = { data: { rol: 'medico', pais_id: 'gt' }, error: null }
    entrar()
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/medico'))
    expect(esPacienteActual).not.toHaveBeenCalled()
    await waitFor(() => expect(screen.getByRole('button', { name: /Iniciar Sesión/ })).toBeEnabled())
  })

  it('sin perfil + paciente → /paciente', async () => {
    perfilRespuesta = { data: null, error: { code: 'PGRST116' } }
    esPacienteActual.mockResolvedValue(true)
    entrar()
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/paciente'))
    expect(esPacienteActual).toHaveBeenCalledWith('uid-1')
    expect(navigate).toHaveBeenCalledTimes(1)
    await waitFor(() => expect(screen.getByRole('button', { name: /Iniciar Sesión/ })).toBeEnabled())
  })

  it('sin perfil + no paciente → /sin-panel', async () => {
    perfilRespuesta = { data: null, error: { code: 'PGRST116' } }
    esPacienteActual.mockResolvedValue(false)
    entrar()
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/sin-panel'))
    expect(esPacienteActual).toHaveBeenCalledWith('uid-1')
    expect(navigate).toHaveBeenCalledTimes(1)
    await waitFor(() => expect(screen.getByRole('button', { name: /Iniciar Sesión/ })).toBeEnabled())
  })

  it('login con error → muestra el error, sin navegar ni consultar', async () => {
    login.mockResolvedValue({ error: { message: 'Invalid login credentials' } })
    entrar()
    expect(await screen.findByText('Invalid login credentials')).toBeInTheDocument()
    expect(navigate).not.toHaveBeenCalled()
    expect(esPacienteActual).not.toHaveBeenCalled()
  })
})
