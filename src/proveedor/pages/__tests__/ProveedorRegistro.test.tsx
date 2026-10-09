import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
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

const { default: ProveedorRegistro } = await import('../ProveedorRegistro')
const { toast } = await import('sonner')
const { MENSAJE_CONFIRMA_CORREO } = await import('@/proveedor/lib/registroDiferido')

// Los valores del selector "Tipo de empresa" (tiposEmpresa en ProveedorRegistro.tsx).
const TIPOS = ['farmacia', 'laboratorio_farmaceutico', 'laboratorio_clinico', 'empresa_afin']

function montar() {
  return render(
    <MemoryRouter>
      <ProveedorRegistro />
    </MemoryRouter>,
  )
}

const continuar = () => screen.getByRole('button', { name: /Continuar/ })
const registrar = () => screen.getByRole('button', { name: /Registrar empresa/ })
const casilla = () => screen.getByRole('checkbox')

function completarPaso1(container: HTMLElement, tipo = 'farmacia') {
  fireEvent.change(container.querySelector('#nombre_empresa')!, { target: { value: 'Empresa X' } })
  fireEvent.change(container.querySelector('#tipo')!, { target: { value: tipo } })
  fireEvent.change(container.querySelector('#pais')!, { target: { value: 'pais-gt' } })
  fireEvent.change(container.querySelector('#email_contacto')!, { target: { value: 'contacto@x.com' } })
  fireEvent.click(continuar())
}

function completarPaso2(container: HTMLElement) {
  fireEvent.change(container.querySelector('#nombre_completo')!, { target: { value: 'Rep Uno' } })
  fireEvent.change(container.querySelector('#email')!, { target: { value: 'rep@x.com' } })
  fireEvent.change(container.querySelector('#password')!, { target: { value: 'secreta123' } })
  fireEvent.change(container.querySelector('#confirmPassword')!, { target: { value: 'secreta123' } })
}

async function hastaPaso2(tipo?: string) {
  const r = montar()
  completarPaso1(r.container, tipo)
  await screen.findByRole('button', { name: /Registrar empresa/ })
  return r
}

beforeEach(() => {
  navigate.mockReset()
  register.mockReset()
  aceptarEnRegistro.mockReset()
})

describe('ProveedorRegistro: casilla de textos legales', () => {
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
    expect(await screen.findByRole('button', { name: /Registrar empresa/ })).toBeInTheDocument()
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

  it('alta OK → aceptarEnRegistro con los textos de profesional y el userId, después navega a /proveedor/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('grabado')
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/proveedor/login'))
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
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/proveedor/login'))
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

  it.each(TIPOS)('tipo %s: el alta OK llama a aceptarEnRegistro con los textos de profesional', async (tipo) => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('grabado')
    const { container } = await hastaPaso2(tipo)
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/proveedor/login'))
    expect(register.mock.calls[0][3]).toMatchObject({ tipo })
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-nuevo')
  })
})

describe('ProveedorRegistro: aviso de confirmar el correo (alta diferida)', () => {
  beforeEach(() => {
    vi.mocked(toast.success).mockReset()
    vi.mocked(toast.error).mockReset()
  })

  // El click final va en el test, seguido del waitFor: un await entre los dos deja el setState fuera de act.
  async function preparar() {
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
  }

  it('pendienteConfirmacion true → toast con MENSAJE_CONFIRMA_CORREO, aceptarEnRegistro con el userId y navega a /proveedor/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo', pendienteConfirmacion: true })
    aceptarEnRegistro.mockResolvedValue('omitido')
    await preparar()
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/proveedor/login'))
    expect(toast.success).toHaveBeenCalledTimes(1)
    expect(toast.success).toHaveBeenCalledWith(MENSAJE_CONFIRMA_CORREO)
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-nuevo')
  })

  it('pendienteConfirmacion false → el toast de éxito de siempre, aceptarEnRegistro con el userId y navega a /proveedor/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo', pendienteConfirmacion: false })
    aceptarEnRegistro.mockResolvedValue('grabado')
    await preparar()
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/proveedor/login'))
    expect(toast.success).toHaveBeenCalledTimes(1)
    expect(toast.success).toHaveBeenCalledWith('Empresa registrada. Tu cuenta está en revisión.')
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-nuevo')
  })

  it('error → toast.error con el mensaje del hook, sin toast de éxito ni navigate', async () => {
    register.mockResolvedValue({ data: {}, error: { message: 'Este correo ya está registrado. Usa otro email o inicia sesión.' } })
    await preparar()
    fireEvent.click(registrar())
    await waitFor(() => expect(register).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(registrar()).toBeEnabled())
    expect(toast.error).toHaveBeenCalledWith('Error al registrar', { description: 'Este correo ya está registrado. Usa otro email o inicia sesión.' })
    expect(toast.success).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })
})
