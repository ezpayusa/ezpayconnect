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

const { default: LabRegistro } = await import('../LabRegistro')
const { toast } = await import('sonner')
const { MENSAJE_CONFIRMA_CORREO } = await import('@/proveedor/lib/registroDiferido')

function montar() {
  return render(
    <MemoryRouter>
      <LabRegistro />
    </MemoryRouter>,
  )
}

const continuar = () => screen.getByRole('button', { name: /Continuar/ })
const registrar = () => screen.getByRole('button', { name: /Registrar laboratorio/ })
const casilla = () => screen.getByRole('checkbox')

function completarPaso1(container: HTMLElement) {
  fireEvent.change(container.querySelector('input[placeholder="Ej: LabClinico Regional"]')!, { target: { value: 'Lab X' } })
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
  await screen.findByRole('button', { name: /Registrar laboratorio/ })
  return r
}

beforeEach(() => {
  navigate.mockReset()
  register.mockReset()
  aceptarEnRegistro.mockReset()
})

describe('LabRegistro: casilla de textos legales', () => {
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
    expect(await screen.findByRole('button', { name: /Registrar laboratorio/ })).toBeInTheDocument()
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

  it('alta OK → aceptarEnRegistro con los textos de profesional y el userId, después navega a /laboratorio/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo' })
    aceptarEnRegistro.mockResolvedValue('grabado')
    const { container } = await hastaPaso2()
    completarPaso2(container)
    fireEvent.click(casilla())
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/laboratorio/login'))
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
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/laboratorio/login'))
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

describe('LabRegistro: aviso de confirmar el correo (alta diferida)', () => {
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

  it('pendienteConfirmacion true → toast con MENSAJE_CONFIRMA_CORREO, aceptarEnRegistro con el userId y navega a /laboratorio/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo', pendienteConfirmacion: true })
    aceptarEnRegistro.mockResolvedValue('omitido')
    await preparar()
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/laboratorio/login'))
    expect(toast.success).toHaveBeenCalledTimes(1)
    expect(toast.success).toHaveBeenCalledWith(MENSAJE_CONFIRMA_CORREO)
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-nuevo')
  })

  it('pendienteConfirmacion false → el toast de éxito de siempre, aceptarEnRegistro con el userId y navega a /laboratorio/login', async () => {
    register.mockResolvedValue({ data: {}, error: null, userId: 'uid-nuevo', pendienteConfirmacion: false })
    aceptarEnRegistro.mockResolvedValue('grabado')
    await preparar()
    fireEvent.click(registrar())
    await waitFor(() => expect(navigate).toHaveBeenCalledWith('/laboratorio/login'))
    expect(toast.success).toHaveBeenCalledTimes(1)
    expect(toast.success).toHaveBeenCalledWith('Laboratorio registrado. Ya puedes iniciar sesión.')
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
