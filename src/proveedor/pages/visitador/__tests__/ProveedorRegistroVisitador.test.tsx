import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { textosPara, DECLARACION_MAYORIA_EDAD } from '@/components/legal/CasillaTextosLegales'

const invoke = vi.fn()
const signUp = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    functions: { invoke: (...a: unknown[]) => invoke(...a) },
    auth: { signUp: (...a: unknown[]) => signUp(...a) },
  },
}))

const guardarTokenInvitacion = vi.fn()
const aceptarInvitacionPendiente = vi.fn()
vi.mock('@/lib/invitacionProveedor', () => ({
  guardarTokenInvitacion: (...a: unknown[]) => guardarTokenInvitacion(...a),
  aceptarInvitacionPendiente: () => aceptarInvitacionPendiente(),
}))

const aceptarEnRegistro = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  aceptarEnRegistro: (...a: unknown[]) => aceptarEnRegistro(...a),
}))

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: ProveedorRegistroVisitador } = await import('../ProveedorRegistroVisitador')

const INVITACION = { email: 'visitador@x.com', rol: 'visitador', empresa_nombre: 'Empresa X', nombre_completo: 'Vis Uno' }

async function montar() {
  const r = render(
    <MemoryRouter initialEntries={['/proveedor/registro-visitador?token=tok-1']}>
      <ProveedorRegistroVisitador />
    </MemoryRouter>,
  )
  await screen.findByRole('button', { name: /Crear mi cuenta/ })
  return r
}

const boton = () => screen.getByRole('button', { name: /Crear mi cuenta/ })
const casilla = () => screen.getByRole('checkbox')

function completar(container: HTMLElement) {
  fireEvent.change(container.querySelector('#password')!, { target: { value: 'secreta123' } })
  fireEvent.change(container.querySelector('#confirmPassword')!, { target: { value: 'secreta123' } })
}

async function enviarMarcado() {
  const { container } = await montar()
  completar(container)
  fireEvent.click(casilla())
  // act asíncrono: el flujo sin sesión termina en microtareas, fuera del act síncrono del click.
  await act(async () => {
    fireEvent.click(boton())
  })
}

const exito = () => screen.findByText('¡Registro exitoso!')

beforeEach(() => {
  invoke.mockReset().mockResolvedValue({ data: INVITACION, error: null })
  signUp.mockReset()
  guardarTokenInvitacion.mockReset()
  aceptarInvitacionPendiente.mockReset()
  aceptarEnRegistro.mockReset()
})

describe('ProveedorRegistroVisitador: casilla de textos legales', () => {
  it('con invitación válida se ve la casilla profesional (3 links, sin la declaración de mayoría de edad) y el submit arranca deshabilitado', async () => {
    await montar()
    expect(casilla()).not.toBeChecked()
    const links = textosPara('profesional')
    expect(links).toHaveLength(3)
    for (const t of links) expect(screen.getByRole('link', { name: new RegExp(t.titulo) })).toBeInTheDocument()
    expect(screen.queryByText(DECLARACION_MAYORIA_EDAD, { exact: false })).toBeNull()
    expect(boton()).toBeDisabled()
  })

  it('marcar la casilla habilita el submit', async () => {
    await montar()
    fireEvent.click(casilla())
    expect(boton()).toBeEnabled()
  })

  it('submit del form sin marcar → no llama a signUp', async () => {
    const { container } = await montar()
    completar(container)
    fireEvent.submit(container.querySelector('form')!)
    await new Promise((r) => setTimeout(r, 0))
    expect(signUp).not.toHaveBeenCalled()
  })

  it('signUp con sesión + invitación aceptada → aceptarEnRegistro con el uid del signUp, DESPUÉS de aceptar la invitación; pantalla de éxito', async () => {
    signUp.mockResolvedValue({ data: { user: { id: 'uid-vis' }, session: { access_token: 'x' } }, error: null })
    aceptarInvitacionPendiente.mockResolvedValue(true)
    aceptarEnRegistro.mockResolvedValue('grabado')
    await enviarMarcado()
    expect(await exito()).toBeInTheDocument()
    expect(aceptarEnRegistro).toHaveBeenCalledTimes(1)
    expect(aceptarEnRegistro).toHaveBeenCalledWith(textosPara('profesional'), 'uid-vis')
    expect(aceptarInvitacionPendiente.mock.invocationCallOrder[0]).toBeLessThan(aceptarEnRegistro.mock.invocationCallOrder[0])
  })

  it('signUp SIN sesión → no llama a aceptarEnRegistro; igual llega a la pantalla de éxito', async () => {
    signUp.mockResolvedValue({ data: { user: { id: 'uid-vis' }, session: null }, error: null })
    await enviarMarcado()
    expect(await exito()).toBeInTheDocument()
    expect(aceptarInvitacionPendiente).not.toHaveBeenCalled()
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
  })

  it('aceptarInvitacionPendiente con error → no llama a aceptarEnRegistro ni llega a la pantalla de éxito', async () => {
    signUp.mockResolvedValue({ data: { user: { id: 'uid-vis' }, session: { access_token: 'x' } }, error: null })
    aceptarInvitacionPendiente.mockResolvedValue(false)
    await enviarMarcado()
    await waitFor(() => expect(aceptarInvitacionPendiente).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(boton()).toBeEnabled())
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
    expect(screen.queryByText('¡Registro exitoso!')).toBeNull()
  })

  it("aceptarEnRegistro devuelve 'fallo' → igual llega a la pantalla de éxito", async () => {
    signUp.mockResolvedValue({ data: { user: { id: 'uid-vis' }, session: { access_token: 'x' } }, error: null })
    aceptarInvitacionPendiente.mockResolvedValue(true)
    aceptarEnRegistro.mockResolvedValue('fallo')
    await enviarMarcado()
    expect(await exito()).toBeInTheDocument()
  })

  it('signUp con error → ni aceptarInvitacionPendiente ni aceptarEnRegistro', async () => {
    signUp.mockResolvedValue({ data: { user: null, session: null }, error: { message: 'User already registered' } })
    await enviarMarcado()
    await waitFor(() => expect(signUp).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(boton()).toBeEnabled())
    expect(aceptarInvitacionPendiente).not.toHaveBeenCalled()
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
    expect(screen.queryByText('¡Registro exitoso!')).toBeNull()
  })
})
