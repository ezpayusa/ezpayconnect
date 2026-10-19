import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom'
import { TEXTOS_LEGALES } from '@/legal/catalogo'

const sesion = { user: { id: 'u1' } } as { user: { id: string } } | null
let sesionActual: typeof sesion = sesion
const signOut = vi.fn(async () => ({ error: null }))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({ data: { session: sesionActual }, error: null }),
      signOut: () => signOut(),
    },
  },
}))

const obtenerPendientes = vi.fn()
const aceptarTextos = vi.fn()
vi.mock('@/lib/textosLegales', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/lib/textosLegales')>()
  return {
    ...real,
    obtenerPendientes: () => obtenerPendientes(),
    aceptarTextos: (...a: unknown[]) => aceptarTextos(...a),
  }
})

const { default: AceptarTextosPage, nextSeguro, loginPara } = await import('./AceptarTextosPage')
const { DECLARACION_MAYORIA_EDAD } = await import('@/components/legal/CasillaTextosLegales')

const terminos = TEXTOS_LEGALES.find((t) => t.codigo === 'terminos')!
const privacidad = TEXTOS_LEGALES.find((t) => t.codigo === 'privacidad')!
const consentimiento = TEXTOS_LEGALES.find((t) => t.codigo === 'consentimiento_salud')!

function Ubicacion() {
  const l = useLocation()
  return <div data-testid="ubicacion">{l.pathname + l.search}</div>
}

function montar(entrada = '/aceptar-textos?next=/medico') {
  return render(
    <MemoryRouter initialEntries={[entrada]}>
      <Routes>
        <Route path="/aceptar-textos" element={<AceptarTextosPage />} />
        <Route path="*" element={<Ubicacion />} />
      </Routes>
    </MemoryRouter>,
  )
}

const ubicacion = () => screen.findByTestId('ubicacion').then((e) => e.textContent)

beforeEach(() => {
  sesionActual = sesion
  signOut.mockClear()
  obtenerPendientes.mockReset()
  aceptarTextos.mockReset()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('nextSeguro', () => {
  it('ruta interna → se respeta', () => {
    expect(nextSeguro('/medico')).toBe('/medico')
    expect(nextSeguro('/paciente/citas?x=1#a')).toBe('/paciente/citas?x=1#a')
  })

  it.each(['//evil.com', '/\\evil.com', 'https://evil.com', 'javascript:alert(1)', '/\t/evil.com', '/x?u=https://evil.com', null, ''])(
    '%j → /',
    (raw) => {
      expect(nextSeguro(raw)).toBe('/')
    },
  )
})

describe('AceptarTextosPage', () => {
  it('sin sesión → navega al login del destino (/medico → /login) sin consultar pendientes', async () => {
    sesionActual = null
    montar()
    expect(await ubicacion()).toBe('/login')
    expect(obtenerPendientes).not.toHaveBeenCalled()
  })

  it('0 pendientes → navega al next', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [] })
    montar()
    expect(await ubicacion()).toBe('/medico')
  })

  it('2 pendientes → 2 casillas; el botón espera las 2; acepta con via login y navega al next', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos, privacidad] })
    aceptarTextos.mockResolvedValue({ ok: true, data: { aceptados: 2, ya_aceptados: 0, pendientes: [] } })
    montar()
    const casillas = await screen.findAllByRole('checkbox')
    expect(casillas).toHaveLength(2)
    expect(screen.getByRole('link', { name: new RegExp(terminos.titulo) })).toHaveAttribute('target', '_blank')
    const boton = screen.getByRole('button', { name: 'Aceptar y continuar' })
    expect(boton).toBeDisabled()
    fireEvent.click(casillas[0])
    expect(boton).toBeDisabled()
    fireEvent.click(casillas[1])
    expect(boton).toBeEnabled()
    fireEvent.click(boton)
    expect(await ubicacion()).toBe('/medico')
    expect(aceptarTextos).toHaveBeenCalledTimes(1)
    expect(aceptarTextos).toHaveBeenCalledWith(
      [
        { codigo: 'terminos', version: '0.1' },
        { codigo: 'privacidad', version: '0.1' },
      ],
      'login',
    )
  })

  it('next malicioso → navega a /', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [] })
    montar('/aceptar-textos?next=' + encodeURIComponent('//evil.com/robar'))
    expect(await ubicacion()).toBe('/')
  })

  it('error LG006 → muestra su mensaje y no navega', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos] })
    aceptarTextos.mockResolvedValue({ ok: false, error: { code: 'LG006', message: 'Este texto no corresponde a tu cuenta.' } })
    montar()
    fireEvent.click(await screen.findByRole('checkbox'))
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar y continuar' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Este texto no corresponde a tu cuenta.')
    expect(screen.queryByTestId('ubicacion')).toBeNull()
    expect(obtenerPendientes).toHaveBeenCalledTimes(1)
  })

  it('error LG003 → recarga los pendientes', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos] })
    aceptarTextos.mockResolvedValue({ ok: false, error: { code: 'LG003', message: 'La versión ya no está vigente.' } })
    montar()
    fireEvent.click(await screen.findByRole('checkbox'))
    fireEvent.click(screen.getByRole('button', { name: 'Aceptar y continuar' }))
    await waitFor(() => expect(obtenerPendientes).toHaveBeenCalledTimes(2))
    expect(await screen.findByRole('alert')).toHaveTextContent('La versión ya no está vigente.')
    expect(screen.queryByTestId('ubicacion')).toBeNull()
  })

  it('obtenerPendientes ok:false → falla cerrada; Reintentar vuelve a llamar', async () => {
    obtenerPendientes.mockResolvedValue({ ok: false, error: { code: null, message: null } })
    montar()
    expect(await screen.findByText('No pudimos verificar tus aceptaciones')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aceptar y continuar' })).toBeNull()
    expect(screen.queryByTestId('ubicacion')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await waitFor(() => expect(obtenerPendientes).toHaveBeenCalledTimes(2))
  })

  it('Cerrar sesión → signOut y navega al login del destino (/medico → /login)', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos] })
    montar()
    await screen.findByRole('checkbox')
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar sesión' }))
    expect(await ubicacion()).toBe('/login')
    expect(signOut).toHaveBeenCalledTimes(1)
  })
})

describe('AceptarTextosPage: declaración de mayoría de edad (review PR #56 H3)', () => {
  const declaracion = () => screen.queryByRole('checkbox', { name: DECLARACION_MAYORIA_EDAD })
  const boton = () => screen.getByRole('button', { name: 'Aceptar y continuar' })

  it('con consentimiento_salud pendiente aparece la declaración; sin marcarla el botón sigue deshabilitado y no acepta', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos, consentimiento] })
    montar()
    await screen.findAllByRole('checkbox')
    expect(declaracion()).not.toBeNull()
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(terminos.titulo) }))
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(consentimiento.titulo) }))
    expect(declaracion()).not.toBeChecked()
    expect(boton()).toBeDisabled()
    fireEvent.click(boton())
    await new Promise((r) => setTimeout(r, 0))
    expect(aceptarTextos).not.toHaveBeenCalled()
  })

  it('marcando también la declaración → acepta exactamente los pendientes (sin campos nuevos) y navega al next', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos, consentimiento] })
    aceptarTextos.mockResolvedValue({ ok: true, data: { aceptados: 2, ya_aceptados: 0, pendientes: [] } })
    montar()
    await screen.findAllByRole('checkbox')
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(terminos.titulo) }))
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(consentimiento.titulo) }))
    fireEvent.click(declaracion()!)
    expect(boton()).toBeEnabled()
    fireEvent.click(boton())
    expect(await ubicacion()).toBe('/medico')
    expect(aceptarTextos).toHaveBeenCalledWith(
      [
        { codigo: 'terminos', version: '0.1' },
        { codigo: 'consentimiento_salud', version: '0.1' },
      ],
      'login',
    )
  })

  it('sin consentimiento_salud pendiente no hay declaración; marcar los textos alcanza', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos, privacidad] })
    montar()
    const casillas = await screen.findAllByRole('checkbox')
    expect(casillas).toHaveLength(2)
    expect(declaracion()).toBeNull()
    fireEvent.click(casillas[0])
    fireEvent.click(casillas[1])
    expect(boton()).toBeEnabled()
  })

  it('LG003 → al recargar los pendientes la declaración vuelve a quedar desmarcada', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [consentimiento] })
    aceptarTextos.mockResolvedValue({ ok: false, error: { code: 'LG003', message: 'La versión ya no está vigente.' } })
    montar()
    await screen.findAllByRole('checkbox')
    fireEvent.click(screen.getByRole('checkbox', { name: new RegExp(consentimiento.titulo) }))
    fireEvent.click(declaracion()!)
    expect(declaracion()).toBeChecked()
    fireEvent.click(boton())
    await waitFor(() => expect(obtenerPendientes).toHaveBeenCalledTimes(2))
    await waitFor(() => expect(declaracion()).not.toBeChecked())
    expect(boton()).toBeDisabled()
  })
})

describe('loginPara (review PR #56 H4)', () => {
  it.each([
    ['/paciente', '/paciente/login'],
    ['/paciente/recetas', '/paciente/login'],
    ['/proveedor/x', '/proveedor/login'],
    ['/farmacia', '/farmacia/login'],
    ['/laboratorio/ordenes', '/laboratorio/login'],
    ['/', '/login'],
    ['/dashboard', '/login'],
    ['/pacientes', '/login'],
    ['/pacientesx', '/login'],
    // H6: mismos logins que RepartidorPrivateRoute y VisitadorPrivateRoute.
    ['/repartidor', '/farmacia/login'],
    ['/repartidor/entregas/51', '/farmacia/login'],
    ['/visitador', '/proveedor/login'],
    ['/visitador/ruta', '/proveedor/login'],
    // H7: se ignoran query y hash.
    ['/paciente?tab=x', '/paciente/login'],
    ['/farmacia#a', '/farmacia/login'],
    ['/pacientes?x=1', '/login'],
    ['/repartidorx', '/login'],
  ])('%s → %s', (destino, esperado) => {
    expect(loginPara(destino)).toBe(esperado)
  })

  it('Cerrar sesión con next=/paciente/recetas → signOut y /paciente/login', async () => {
    obtenerPendientes.mockResolvedValue({ ok: true, pendientes: [terminos] })
    montar('/aceptar-textos?next=' + encodeURIComponent('/paciente/recetas'))
    await screen.findByRole('checkbox')
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar sesión' }))
    expect(await ubicacion()).toBe('/paciente/login')
    expect(signOut).toHaveBeenCalledTimes(1)
  })

  it('sin sesión con next=/farmacia/inventario → /farmacia/login', async () => {
    sesionActual = null
    montar('/aceptar-textos?next=' + encodeURIComponent('/farmacia/inventario'))
    expect(await ubicacion()).toBe('/farmacia/login')
    expect(obtenerPendientes).not.toHaveBeenCalled()
  })
})
