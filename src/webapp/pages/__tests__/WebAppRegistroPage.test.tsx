import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, renderHook, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { textosPara, DECLARACION_MAYORIA_EDAD } from '@/components/legal/CasillaTextosLegales'

const navigate = vi.fn()
vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => navigate,
}))

const register = vi.fn()
vi.mock('@/webapp/hooks/useWebAppAuth', () => ({
  useWebAppAuth: () => ({ register }),
}))

const aceptarEnRegistro = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  aceptarEnRegistro: (...a: unknown[]) => aceptarEnRegistro(...a),
}))

vi.mock('@/hooks/usePaisesRegistro', () => ({ usePaisesRegistro: () => ({ paises: [], error: null }) }))
vi.mock('@/webapp/hooks/useReferidoAmigo', () => ({ useCapturarReferido: () => {} }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

// Para el test del hook real (g): supabase simulado.
const signUp = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      signUp: (...a: unknown[]) => signUp(...a),
      getSession: async () => ({ data: { session: null } }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    },
  },
}))

const { default: WebAppRegistroPage } = await import('../WebAppRegistroPage')

function montar() {
  return render(
    <MemoryRouter>
      <WebAppRegistroPage />
    </MemoryRouter>,
  )
}

const boton = () => screen.getByRole('button', { name: /Registrarme/ })
const casilla = () => screen.getByRole('checkbox')

function completar(container: HTMLElement) {
  const textos = container.querySelectorAll<HTMLInputElement>('input:not([type])')
  fireEvent.change(textos[0], { target: { value: 'Ana' } })
  fireEvent.change(textos[1], { target: { value: 'Pérez' } })
  fireEvent.change(container.querySelector('input[type="email"]')!, { target: { value: 'ana@example.com' } })
  fireEvent.change(container.querySelector('input[type="password"]')!, { target: { value: 'secreta123' } })
}

beforeEach(() => {
  navigate.mockReset()
  register.mockReset()
  aceptarEnRegistro.mockReset()
  signUp.mockReset()
})

describe('WebAppRegistroPage: casilla de textos legales', () => {
  it('renderiza la casilla de paciente (con la declaración de mayoría de edad) y el submit arranca deshabilitado', () => {
    montar()
    expect(casilla()).not.toBeChecked()
    expect(screen.getByText(DECLARACION_MAYORIA_EDAD, { exact: false })).toBeInTheDocument()
    for (const t of textosPara('paciente')) expect(screen.getByRole('link', { name: new RegExp(t.titulo) })).toBeInTheDocument()
    expect(boton()).toBeDisabled()
  })

  it('marcar la casilla habilita el submit', () => {
    montar()
    fireEvent.click(casilla())
    expect(boton()).toBeEnabled()
  })

  it('submit del form sin marcar → no llama a register', async () => {
    const { container } = montar()
    completar(container)
    fireEvent.submit(container.querySelector('form')!)
    await new Promise((r) => setTimeout(r, 0))
    expect(register).not.toHaveBeenCalled()
  })

  it('alta OK → aceptarEnRegistro con los textos de paciente y el uid de register, después navega a /paciente/login', async () => {
    register.mockResolvedValue({ error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('grabado')
    const { container } = montar()
    completar(container)
    fireEvent.click(casilla())
    fireEvent.click(boton())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/paciente/login'))
    expect(aceptarEnRegistro).toHaveBeenCalledTimes(1)
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('paciente'), 'uid-nuevo')
    expect(aceptarEnRegistro.mock.invocationCallOrder[0]).toBeLessThan(navigate.mock.invocationCallOrder[0])
  })

  it("aceptarEnRegistro devuelve 'fallo' → igual navega", async () => {
    register.mockResolvedValue({ error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('fallo')
    const { container } = montar()
    completar(container)
    fireEvent.click(casilla())
    fireEvent.click(boton())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/paciente/login'))
  })

  it('register con error → no llama a aceptarEnRegistro ni navega', async () => {
    register.mockResolvedValue({ error: { message: 'User already registered' } })
    const { container } = montar()
    completar(container)
    fireEvent.click(casilla())
    fireEvent.click(boton())
    await waitFor(() => expect(register).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(boton()).toBeEnabled())
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })
})

describe('useWebAppAuth.register (hook real)', () => {
  it('devuelve el uid del usuario creado por signUp', async () => {
    const { useWebAppAuth } = await vi.importActual<typeof import('@/webapp/hooks/useWebAppAuth')>(
      '@/webapp/hooks/useWebAppAuth',
    )
    signUp.mockResolvedValue({ data: { user: { id: 'uid-signup' }, session: null }, error: null })
    const { result } = renderHook(() => useWebAppAuth())
    let r: unknown
    await act(async () => {
      r = await result.current.register('ana@example.com', 'secreta123', { nombre: 'Ana', apellido: 'Pérez' })
    })
    expect(r).toEqual({ error: null, userId: 'uid-signup' })
  })
})
