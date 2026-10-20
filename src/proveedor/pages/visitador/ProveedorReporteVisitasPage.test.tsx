import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { puedeRol } from '@/proveedor/lib/permisos'

// Gate del reporte de visitas: entra el visitador (visitas.propias) y quien gestiona visitadores (admin, supervisor);
// el resto vuelve al dashboard. Título y destino de "volver" dependen del rol. Los permisos salen de la matriz real
// (permisos.ts): si alguien cambia la matriz, el test lo nota.

let rolActual: string | null = 'admin'

vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({
    loading: false,
    empresa: { id: 'emp-1' },
    rol: rolActual,
    puede: (p: Parameters<typeof puedeRol>[1]) => puedeRol(rolActual, p),
  }),
}))
vi.mock('@/lib/supabase', () => {
  const q = {
    select: () => q,
    eq: () => q,
    order: async () => ({ data: [], error: null }),
  }
  return { supabase: { from: () => q } }
})
vi.mock('@/proveedor/lib/nombresMedicos', () => ({
  resolverNombresMedicos: async () => ({ mapa: {}, error: null }),
  nombreMedico: () => 'Médico',
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: ProveedorReporteVisitasPage } = await import('./ProveedorReporteVisitasPage')

const pintar = () =>
  render(
    <MemoryRouter initialEntries={['/proveedor/visitador/reporte']}>
      <Routes>
        <Route path="/proveedor/visitador/reporte" element={<ProveedorReporteVisitasPage />} />
        <Route path="/proveedor/dashboard" element={<p>PANTALLA DASHBOARD</p>} />
        <Route path="/visitador/mis-visitas" element={<p>PANTALLA MIS VISITAS</p>} />
      </Routes>
    </MemoryRouter>
  )

// Cuando la página entra, espera a que termine la carga (lista vacía del mock) para no dejar updates fuera de act.
const pintarYCargar = async () => {
  pintar()
  await screen.findByText('No hay visitas en el período seleccionado')
}

beforeEach(() => {
  rolActual = 'admin'
})

describe('ProveedorReporteVisitasPage — gate', () => {
  it.each(['catalogo', 'marketing', 'finanzas', 'lectura', null])('rol %s sin permisos → redirect al dashboard', (rol) => {
    rolActual = rol
    pintar()
    expect(screen.getByText('PANTALLA DASHBOARD')).toBeInTheDocument()
    expect(screen.queryByRole('heading', { level: 1 })).toBeNull()
  })

  it.each(['admin', 'supervisor', 'visitador_medico'])('rol %s entra', async (rol) => {
    rolActual = rol
    await pintarYCargar()
    expect(screen.queryByText('PANTALLA DASHBOARD')).toBeNull()
    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument()
  })
})

describe('ProveedorReporteVisitasPage — título por rol', () => {
  it.each([
    ['admin', 'Reporte de Visitas'],
    ['supervisor', 'Reporte de Visitas'],
    ['visitador_medico', 'Mi Reporte'],
  ])('rol %s → "%s"', async (rol, titulo) => {
    rolActual = rol
    await pintarYCargar()
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(titulo)
  })
})

describe('ProveedorReporteVisitasPage — botón volver', () => {
  it.each([
    ['visitador_medico', 'PANTALLA MIS VISITAS'],
    ['admin', 'PANTALLA DASHBOARD'],
    ['supervisor', 'PANTALLA DASHBOARD'],
  ])('rol %s → %s', async (rol, destino) => {
    rolActual = rol
    await pintarYCargar()
    fireEvent.click(screen.getByRole('button', { name: 'Volver' }))
    expect(screen.getByText(destino)).toBeInTheDocument()
  })
})
