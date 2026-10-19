import { describe, it, expect, vi } from 'vitest'
import type { ComponentType } from 'react'
import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { textosPara } from '@/components/legal/CasillaTextosLegales'

// Mocks mínimos de lo que importan los 5 logins (sin tocar los componentes).
vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser: async () => ({ data: { user: null } }) },
    from: () => ({ select: () => ({ eq: () => ({ single: async () => ({ data: null }), maybeSingle: async () => ({ data: null }) }) }) }),
  },
}))
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ login: vi.fn() }) }))
vi.mock('@/webapp/hooks/useWebAppAuth', () => ({ useWebAppAuth: () => ({ login: vi.fn() }) }))
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({ useProveedorAuth: () => ({ login: vi.fn() }) }))
vi.mock('@/webapp/hooks/useReferidoAmigo', () => ({ useCapturarReferido: () => {} }))
vi.mock('@/lib/enviarReset', () => ({ enviarReset: vi.fn() }))
vi.mock('@/lib/invitacionProveedor', () => ({ aceptarInvitacionPendiente: vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: LoginPage } = await import('@/pages/LoginPage')
const { default: WebAppLoginPage } = await import('@/webapp/pages/WebAppLoginPage')
const { default: ProveedorLogin } = await import('@/proveedor/pages/ProveedorLogin')
const { default: FarmaciaLogin } = await import('@/farmacia/pages/FarmaciaLogin')
const { default: LabLogin } = await import('@/laboratorio/pages/LabLogin')

type Caso = {
  nombre: string
  Pagina: ComponentType
  para: 'paciente' | 'profesional'
  // Elementos del pie que ya existían (además de "¿Olvidaste tu contraseña?").
  previos: (RegExp | string)[]
}

const CASOS: Caso[] = [
  { nombre: 'LoginPage (/login)', Pagina: LoginPage, para: 'profesional', previos: ['El acceso a EzPayConnect es por invitación.'] },
  { nombre: 'WebAppLoginPage (/paciente/login)', Pagina: WebAppLoginPage, para: 'paciente', previos: [/Regístrate/] },
  { nombre: 'ProveedorLogin (/proveedor/login)', Pagina: ProveedorLogin, para: 'profesional', previos: [/Registra tu empresa/, /Volver al portal médico/] },
  { nombre: 'FarmaciaLogin (/farmacia/login)', Pagina: FarmaciaLogin, para: 'profesional', previos: [/Registra tu farmacia/, /Volver al portal médico/] },
  { nombre: 'LabLogin (/laboratorio/login)', Pagina: LabLogin, para: 'profesional', previos: [/Registra tu laboratorio/, /Volver al portal médico/] },
]

function montar(Pagina: ComponentType) {
  return render(
    <MemoryRouter>
      <Pagina />
    </MemoryRouter>,
  )
}

describe('EnlacesLegales al pie de los 5 logins', () => {
  it.each(CASOS)('$nombre: hay un nav "Textos legales"', ({ Pagina }) => {
    montar(Pagina)
    expect(screen.getByRole('navigation', { name: 'Textos legales' })).toBeInTheDocument()
  })

  it.each(CASOS)('$nombre: sus links son exactamente los de textosPara($para), con las rutas del catálogo', ({ Pagina, para }) => {
    montar(Pagina)
    const nav = screen.getByRole('navigation', { name: 'Textos legales' })
    const links = within(nav).getAllByRole('link')
    const esperados = textosPara(para)
    expect(links.map((a) => a.getAttribute('href'))).toEqual(esperados.map((t) => t.ruta))
    links.forEach((a, i) => expect(a.textContent).toContain(esperados[i].titulo))
  })

  it.each(CASOS)('$nombre: el pie de antes sigue (olvido de contraseña y sus links)', ({ Pagina, previos }) => {
    montar(Pagina)
    expect(screen.getByRole('button', { name: '¿Olvidaste tu contraseña?' })).toBeInTheDocument()
    for (const p of previos) expect(screen.getByText(p)).toBeInTheDocument()
  })
})
