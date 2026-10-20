import { describe, it, expect, vi, beforeEach } from 'vitest'
import type { ReactNode } from 'react'
import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { puedeRol } from '@/proveedor/lib/permisos'

// Menú del proveedor: "Reporte de Visitas" (visitadores.gestionar) para admin y supervisor, "Mi Reporte"
// (visitas.propias) para el visitador, y nunca los dos a la vez. Permisos de la matriz real (permisos.ts).

let rolActual = 'admin'
// Para el caso hipotético de un rol con los dos permisos (hoy ninguno de permisos.ts los tiene).
let ambosPermisos = false
let tipoEmpresa = 'laboratorio_farmaceutico'
let capacidades = ['visitadores', 'productos', 'publicidad', 'enrolamiento']

vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({
    loading: false,
    empresa: { id: 'emp-1', tipo: tipoEmpresa, nombre_empresa: 'Lab QA' },
    cuenta: { rol_en_empresa: rolActual },
    logout: vi.fn(),
    puede: (p: Parameters<typeof puedeRol>[1]) =>
      (ambosPermisos && (p === 'visitas.propias' || p === 'visitadores.gestionar')) || puedeRol(rolActual, p),
  }),
}))
vi.mock('@/proveedor/hooks/useCapacidades', () => ({
  useCapacidades: () => ({ tieneCapacidad: (c: string) => capacidades.includes(c), loading: false }),
}))
vi.mock('@/components/theme/TenantThemeProvider', () => ({
  TenantThemeProvider: ({ children }: { children: ReactNode }) => <>{children}</>,
}))
vi.mock('@/components/theme/TenantThemeContext', () => ({ useTema: () => ({ logoUrl: '/logo-qa.png' }) }))
vi.mock('@/proveedor/context/ProveedorNotificacionesContext', () => ({
  ProveedorNotificacionesProvider: ({ children }: { children: ReactNode }) => <>{children}</>,
  useProveedorNotificaciones: () => ({ noLeidas: 0 }),
}))
vi.mock('@/webapp/hooks/usePushNotifications', () => ({ usePushNotifications: () => undefined }))
vi.mock('@/components/branding/PoweredBy', () => ({ PoweredBy: () => null }))

const { default: ProveedorLayout } = await import('./ProveedorLayout')

// Sidebar de escritorio (el menú móvil solo se monta al abrirlo).
const menu = () => {
  render(
    <MemoryRouter initialEntries={['/proveedor/dashboard']}>
      <ProveedorLayout />
    </MemoryRouter>
  )
  return within(screen.getByRole('navigation'))
}

beforeEach(() => {
  rolActual = 'admin'
  ambosPermisos = false
  tipoEmpresa = 'laboratorio_farmaceutico'
  capacidades = ['visitadores', 'productos', 'publicidad', 'enrolamiento']
})

describe('ProveedorLayout — ítems de reporte', () => {
  it.each(['admin', 'supervisor'])('rol %s ve "Reporte de Visitas" y no "Mi Reporte"', (rol) => {
    rolActual = rol
    const nav = menu()
    expect(nav.getByRole('link', { name: 'Reporte de Visitas' })).toHaveAttribute('href', '/proveedor/visitador/reporte')
    expect(nav.queryByRole('link', { name: 'Mi Reporte' })).toBeNull()
  })

  it('visitador ve "Mi Reporte" y no "Reporte de Visitas"', () => {
    rolActual = 'visitador_medico'
    const nav = menu()
    expect(nav.getByRole('link', { name: 'Mi Reporte' })).toHaveAttribute('href', '/proveedor/visitador/reporte')
    expect(nav.queryByRole('link', { name: 'Reporte de Visitas' })).toBeNull()
  })

  it.each(['catalogo', 'marketing', 'finanzas', 'lectura'])('rol %s no ve ningún reporte de visitas', (rol) => {
    rolActual = rol
    const nav = menu()
    expect(nav.queryByRole('link', { name: 'Reporte de Visitas' })).toBeNull()
    expect(nav.queryByRole('link', { name: 'Mi Reporte' })).toBeNull()
  })

  it('un rol con visitas.propias y visitadores.gestionar ve solo "Reporte de Visitas"', () => {
    rolActual = 'visitador_medico'
    ambosPermisos = true
    const nav = menu()
    expect(nav.getAllByRole('link', { name: 'Reporte de Visitas' })).toHaveLength(1)
    expect(nav.queryByRole('link', { name: 'Mi Reporte' })).toBeNull()
  })
})

describe('ProveedorLayout — "Mis Médicos"', () => {
  it.each(['admin', 'supervisor'])('rol %s de un lab farmacéutico con el módulo enrolamiento lo ve', (rol) => {
    rolActual = rol
    expect(menu().getByRole('link', { name: 'Mis Médicos' })).toHaveAttribute('href', '/proveedor/mis-medicos')
  })

  it.each(['visitador_medico', 'catalogo', 'marketing', 'finanzas', 'lectura'])('rol %s no lo ve', (rol) => {
    rolActual = rol
    expect(menu().queryByRole('link', { name: 'Mis Médicos' })).toBeNull()
  })

  it.each(['farmacia', 'laboratorio_clinico', 'empresa_afin'])('empresa %s no lo ve (aunque tenga el módulo)', (tipo) => {
    tipoEmpresa = tipo
    expect(menu().queryByRole('link', { name: 'Mis Médicos' })).toBeNull()
  })

  it('sin el módulo enrolamiento no lo ve', () => {
    capacidades = ['visitadores']
    expect(menu().queryByRole('link', { name: 'Mis Médicos' })).toBeNull()
  })
})
