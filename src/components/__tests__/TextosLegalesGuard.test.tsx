import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation, useNavigate, type NavigateFunction } from 'react-router-dom'
import { TEXTOS_LEGALES } from '@/legal/catalogo'

type Usuario = { id: string; user_metadata?: Record<string, unknown> }
type Sesion = { user: Usuario } | null
type Oyente = (evento: string, sesion: Sesion) => void

let sesionActual: Sesion = null
let oyentes: Oyente[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({ data: { session: sesionActual }, error: null }),
      onAuthStateChange: (cb: Oyente) => {
        oyentes.push(cb)
        return { data: { subscription: { unsubscribe: () => { oyentes = oyentes.filter((o) => o !== cb) } } } }
      },
    },
  },
}))

const obtenerPendientes = vi.fn()
vi.mock('@/lib/textosLegales', () => ({
  obtenerPendientes: () => obtenerPendientes(),
}))

const { default: TextosLegalesGuard, esRutaExenta, resetCacheTextosLegales } = await import('../TextosLegalesGuard')

const CON_PENDIENTES = { ok: true, pendientes: [TEXTOS_LEGALES[0]] }
const SIN_PENDIENTES = { ok: true, pendientes: [] }
const FALLA = { ok: false, error: { code: '42883', message: 'x' } }

const sesion = (id: string, user_metadata: Record<string, unknown> = {}): Sesion => ({ user: { id, user_metadata } })

let navegar: NavigateFunction

function Ubicacion() {
  const l = useLocation()
  navegar = useNavigate()
  return <div data-testid="ubicacion">{l.pathname + l.search}</div>
}

function montar(entrada: string) {
  return render(
    <MemoryRouter initialEntries={[entrada]}>
      <TextosLegalesGuard />
      <Routes>
        <Route path="*" element={<Ubicacion />} />
      </Routes>
    </MemoryRouter>,
  )
}

const ubicacion = () => screen.getByTestId('ubicacion').textContent
// Deja correr getSession, la RPC y su .then.
const tick = () => new Promise((r) => setTimeout(r, 0))
const drenar = () => act(async () => { await tick() })
const emitir = (evento: string, s: Sesion) => act(async () => { oyentes.forEach((o) => o(evento, s)); await tick() })
const ir = (ruta: string) => act(async () => { navegar(ruta); await tick() })

beforeEach(() => {
  resetCacheTextosLegales()
  sesionActual = null
  oyentes = []
  obtenerPendientes.mockReset()
})

describe('esRutaExenta', () => {
  it('tabla de verdad: exentas y no exentas', () => {
    const exentas = [
      '/aceptar-textos', '/set-password', '/confirmar-receta', '/terminos', '/privacidad', '/consentimiento-salud',
      '/condiciones-profesionales', '/planes-visitador', '/planes-clinica', '/login', '/paciente/login',
      '/proveedor/login', '/paciente/registro', '/proveedor/registro-visitador', '/registro-medico', '/registro-clinica',
    ]
    const noExentas = ['/', '/paciente', '/dashboard', '/proveedor', '/admin-ezpay', '/loginx', '/mi-registro-viejo']
    for (const p of exentas) expect(esRutaExenta(p), p).toBe(true)
    for (const p of noExentas) expect(esRutaExenta(p), p).toBe(false)
  })
})

describe('TextosLegalesGuard', () => {
  it('sin usuario → no llama a obtenerPendientes', async () => {
    montar('/dashboard')
    await drenar()
    await emitir('INITIAL_SESSION', null)
    await drenar()
    expect(obtenerPendientes).not.toHaveBeenCalled()
    expect(ubicacion()).toBe('/dashboard')
  })

  it('must_change_password → no llama (MustChangePasswordGuard tiene prioridad)', async () => {
    sesionActual = sesion('u1', { must_change_password: true })
    montar('/dashboard')
    await drenar()
    expect(obtenerPendientes).not.toHaveBeenCalled()
  })

  it('ruta exenta → no llama', async () => {
    sesionActual = sesion('u1')
    montar('/terminos')
    await drenar()
    expect(obtenerPendientes).not.toHaveBeenCalled()
    expect(ubicacion()).toBe('/terminos')
  })

  it('con pendientes → navega a /aceptar-textos?next=<ruta+search codificada>', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValue(CON_PENDIENTES)
    montar('/paciente/citas?x=1&y=2')
    await waitFor(() =>
      expect(ubicacion()).toBe(`/aceptar-textos?next=${encodeURIComponent('/paciente/citas?x=1&y=2')}`),
    )
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
  })

  it('error de la RPC → navega igual (falla cerrada)', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValue(FALLA)
    montar('/dashboard')
    await waitFor(() => expect(ubicacion()).toBe(`/aceptar-textos?next=${encodeURIComponent('/dashboard')}`))
  })

  it('0 pendientes → no navega; otra ruta no exenta no vuelve a llamar (cache por uid)', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValue(SIN_PENDIENTES)
    montar('/dashboard')
    await emitir('INITIAL_SESSION', sesionActual)
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    expect(ubicacion()).toBe('/dashboard')
    await ir('/pacientes')
    await drenar()
    await emitir('TOKEN_REFRESHED', sesionActual)
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    expect(ubicacion()).toBe('/pacientes')
  })

  it('SIGNED_OUT vacía la cache: el mismo uid vuelve a llamar al loguear', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValue(SIN_PENDIENTES)
    montar('/dashboard')
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    await emitir('SIGNED_IN', sesion('u1'))
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    await emitir('SIGNED_OUT', null)
    await drenar()
    await emitir('SIGNED_IN', sesion('u1'))
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(2)
  })

  it('cambio de uid → llama para el uid nuevo', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValueOnce(SIN_PENDIENTES).mockResolvedValueOnce(CON_PENDIENTES)
    montar('/dashboard')
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    await emitir('SIGNED_IN', sesion('u2'))
    await drenar()
    expect(ubicacion()).toBe(`/aceptar-textos?next=${encodeURIComponent('/dashboard')}`)
    expect(obtenerPendientes).toHaveBeenCalledTimes(2)
  })

  it('respuesta tardía tras cambiar a una ruta exenta → no navega', async () => {
    sesionActual = sesion('u1')
    let resolver: (v: unknown) => void = () => {}
    obtenerPendientes.mockReturnValue(new Promise((r) => { resolver = r }))
    montar('/dashboard')
    await emitir('INITIAL_SESSION', sesionActual)
    await drenar()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
    await ir('/terminos')
    await act(async () => { resolver(CON_PENDIENTES) })
    await drenar()
    expect(ubicacion()).toBe('/terminos')
  })

  it('de exenta a no exenta → llama al salir', async () => {
    sesionActual = sesion('u1')
    obtenerPendientes.mockResolvedValue(CON_PENDIENTES)
    montar('/login')
    await drenar()
    expect(obtenerPendientes).not.toHaveBeenCalled()
    await ir('/dashboard')
    await waitFor(() => expect(ubicacion()).toBe(`/aceptar-textos?next=${encodeURIComponent('/dashboard')}`))
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
  })
})
