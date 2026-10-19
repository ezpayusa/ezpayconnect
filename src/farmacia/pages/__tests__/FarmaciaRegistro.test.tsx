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
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({ register }),
}))

const aceptarEnRegistro = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  aceptarEnRegistro: (...a: unknown[]) => aceptarEnRegistro(...a),
}))

vi.mock('@/proveedor/hooks/usePaisesRegistroProveedor', () => ({
  usePaisesRegistroProveedor: () => [{ id: 'pais-gt', nombre: 'Guatemala' }],
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

// Para el test del hook real (h): supabase simulado.
const signUp = vi.fn()
const signOut = vi.fn()
const rpc = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      signUp: (...a: unknown[]) => signUp(...a),
      signOut: (...a: unknown[]) => signOut(...a),
      getSession: async () => ({ data: { session: null } }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    },
    rpc: (...a: unknown[]) => rpc(...a),
  },
}))

const { default: FarmaciaRegistro } = await import('../FarmaciaRegistro')

function montar() {
  return render(
    <MemoryRouter>
      <FarmaciaRegistro />
    </MemoryRouter>,
  )
}

const continuar = () => screen.getByRole('button', { name: /Continuar/ })
const registrar = () => screen.getByRole('button', { name: /Registrar farmacia/ })
const casilla = () => screen.getByRole('checkbox')

function completarPaso1(container: HTMLElement) {
  fireEvent.change(container.querySelector('input[placeholder="Ej: Farmacia San José"]')!, { target: { value: 'Farmacia X' } })
  fireEvent.change(container.querySelector('select')!, { target: { value: 'pais-gt' } })
  fireEvent.change(container.querySelector('input[type="email"]')!, { target: { value: 'contacto@x.com' } })
  fireEvent.click(continuar())
}

function completarPaso2(container: HTMLElement) {
  const textos = container.querySelectorAll<HTMLInputElement>('input:not([type])')
  fireEvent.change(textos[0], { target: { value: 'Rep Uno' } })
  fireEvent.change(container.querySelector('input[type="email"]')!, { target: { value: 'rep@x.com' } })
  const claves = container.querySelectorAll<HTMLInputElement>('input[type="password"]')
  fireEvent.change(claves[0], { target: { value: 'secreta123' } })
  fireEvent.change(claves[1], { target: { value: 'secreta123' } })
}

async function hastaPaso2() {
  const r = montar()
  completarPaso1(r.container)
  await screen.findByRole('button', { name: /Registrar farmacia/ })
  return r
}

beforeEach(() => {
  navigate.mockReset()
  register.mockReset()
  aceptarEnRegistro.mockReset()
  signUp.mockReset()
  signOut.mockReset()
  rpc.mockReset()
})

describe('FarmaciaRegistro: casilla de textos legales', () => {
  it('en el paso 2 está la casilla profesional (3 links, sin la declaración de mayoría de edad) y el submit arranca deshabilitado', async () => {
    await hastaPaso2()
    expect(casilla()).not.toBeChecked()
    const links = textosPara('profesional')
    expect(links).toHaveLength(3)
    for (const t of links) expect(screen.getByRole('link', { name: new RegExp(t.titulo) })).toBeInTheDocument()
    expect(screen.queryByText(DECLARACION_MAYORIA_EDAD, { exact: false })).toBeNull()
    expect(registrar()).toBeDisabled()
  })

  it('el paso 1 avanza sin la casilla', async () => {
    const { container } = montar()
    expect(screen.queryByRole('checkbox')).toBeNull()
    expect(continuar()).toBeEnabled()
    completarPaso1(container)
    expect(await screen.findByRole('button', { name: /Registrar farmacia/ })).toBeInTheDocument()
    expect(register).not.toHaveBeenCalled()
  })

  it('marcar la casilla habilita el submit final', async () => {
    await hastaPaso2()
    fireEvent.click(casilla())
    expect(registrar()).toBeEnabled()
  })

  it('submit del form en el paso 2 sin marcar → no llama a register', async () => {
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.submit(container.querySelector('form')!)
    await new Promise((r) => setTimeout(r, 0))
    expect(register).not.toHaveBeenCalled()
  })

  it('alta OK → aceptarEnRegistro con los textos de profesional y el userId, después navega a /farmacia/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('grabado')
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/farmacia/login'))
    expect(aceptarEnRegistro).toHaveBeenCalledTimes(1)
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-nuevo')
    expect(aceptarEnRegistro.mock.invocationCallOrder[0]).toBeLessThan(navigate.mock.invocationCallOrder[0])
  })

  it("aceptarEnRegistro devuelve 'fallo' → igual navega", async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('fallo')
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/farmacia/login'))
  })

  it('register con error → no llama a aceptarEnRegistro ni navega', async () => {
    register.mockResolvedValue({ data: {}, error: { message: 'Error al crear la empresa: x' } })
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(register).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(registrar()).toBeEnabled())
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })
})

describe('useProveedorAuth.register (hook real)', () => {
  const empresa = { nombre_empresa: 'Farmacia X', tipo: 'farmacia' as const, pais_id: 'pais-gt', email_contacto: 'c@x.com' }

  async function hookReal() {
    const { useProveedorAuth } = await vi.importActual<typeof import('@/proveedor/hooks/useProveedorAuth')>(
      '@/proveedor/hooks/useProveedorAuth',
    )
    const r = renderHook(() => useProveedorAuth())
    await act(async () => {}) // deja terminar el init (getSession) dentro de act
    return r
  }

  it('registrar_proveedor OK → devuelve el userId del signUp; con registrar_proveedor en error hace signOut y no devuelve userId', async () => {
    signUp.mockResolvedValue({ data: { user: { id: 'uid-signup' }, session: {} }, error: null })
    rpc.mockResolvedValue({ data: 'empresa-1', error: null })
    const { result } = await hookReal()
    let ok: Record<string, unknown> = {}
    await act(async () => {
      ok = await result.current.register('rep@x.com', 'secreta123', 'Rep Uno', empresa)
    })
    expect(ok.error).toBeNull()
    expect(ok.userId).toBe('uid-signup')
    expect(signOut).not.toHaveBeenCalled()

    vi.spyOn(console, 'error').mockImplementation(() => {}) // el hook loguea el error de la RPC
    rpc.mockResolvedValue({ data: null, error: { message: 'País no válido para el registro' } })
    let falla: Record<string, unknown> = {}
    await act(async () => {
      falla = await result.current.register('rep@x.com', 'secreta123', 'Rep Uno', empresa)
    })
    expect(falla.error).toBeTruthy()
    expect('userId' in falla).toBe(false)
    expect(signOut).toHaveBeenCalledTimes(1)
  })
})
