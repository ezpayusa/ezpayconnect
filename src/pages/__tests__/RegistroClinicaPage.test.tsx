import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { textosPara, DECLARACION_MAYORIA_EDAD } from '@/components/legal/CasillaTextosLegales'

const invoke = vi.fn()
const getSession = vi.fn()
vi.mock('@/lib/supabase', () => ({
  supabase: {
    functions: { invoke: (...a: unknown[]) => invoke(...a) },
    auth: { getSession: () => getSession() },
  },
}))

const aceptarEnRegistro = vi.fn()
const aceptarTextos = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  aceptarEnRegistro: (...a: unknown[]) => aceptarEnRegistro(...a),
  aceptarTextos: (...a: unknown[]) => aceptarTextos(...a),
}))

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: RegistroClinicaPage } = await import('../RegistroClinicaPage')

const INVITACION = { nombre_clinica: 'Clínica Central', nombre_contacto: 'Luis Gómez', email: 'luis@x.com' }

function responderEdges(registro: { data: unknown; error: unknown } = { data: { success: true }, error: null }) {
  invoke.mockImplementation(async (fn: string) => {
    if (fn === 'validar-invitacion-clinica') return { data: { data: INVITACION }, error: null }
    if (fn === 'registrar-clinica-invitacion') return registro
    throw new Error(`edge inesperada: ${fn}`)
  })
}

async function montar() {
  const r = render(
    <MemoryRouter initialEntries={['/registro-clinica?token=tok-cli']}>
      <RegistroClinicaPage />
    </MemoryRouter>,
  )
  await screen.findByRole('button', { name: /Completar Registro/ })
  return r
}

const boton = () => screen.getByRole('button', { name: /Completar Registro/ })
const casilla = () => screen.getByRole('checkbox')
const llamadasRegistro = () => invoke.mock.calls.filter((c) => c[0] === 'registrar-clinica-invitacion')

function completar(container: HTMLElement) {
  fireEvent.change(container.querySelector('#password')!, { target: { value: 'secreta123' } })
  fireEvent.change(container.querySelector('#confirmPassword')!, { target: { value: 'secreta123' } })
}

async function enviarMarcado() {
  const { container } = await montar()
  completar(container)
  fireEvent.click(casilla())
  await act(async () => {
    fireEvent.click(boton())
  })
}

beforeEach(() => {
  invoke.mockReset()
  getSession.mockReset().mockResolvedValue({ data: { session: null }, error: null })
  aceptarEnRegistro.mockReset()
  aceptarTextos.mockReset()
  responderEdges()
})

describe('RegistroClinicaPage: casilla de textos legales (solo UI)', () => {
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

  it('submit del form sin marcar → no llama a registrar-clinica-invitacion', async () => {
    const { container } = await montar()
    completar(container)
    fireEvent.submit(container.querySelector('form')!)
    await new Promise((r) => setTimeout(r, 0))
    expect(llamadasRegistro()).toHaveLength(0)
  })

  it('marcado + submit OK → la edge recibe el body de siempre y aparece la pantalla de éxito', async () => {
    await enviarMarcado()
    expect(await screen.findByText('¡Registro Completado!')).toBeInTheDocument()
    expect(llamadasRegistro()).toHaveLength(1)
    expect(llamadasRegistro()[0][1]).toEqual({
      body: { token: 'tok-cli', password: 'secreta123', nombre_contacto: INVITACION.nombre_contacto },
    })
  })

  it('con una sesión ajena activa en el navegador, no se llama a aceptarEnRegistro ni a aceptarTextos', async () => {
    getSession.mockResolvedValue({ data: { session: { user: { id: 'otra-persona' } } }, error: null })
    await enviarMarcado()
    await waitFor(() => expect(screen.getByText('¡Registro Completado!')).toBeInTheDocument())
    expect(aceptarEnRegistro).not.toHaveBeenCalled()
    expect(aceptarTextos).not.toHaveBeenCalled()
  })
})
