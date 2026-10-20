import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Pestaña "Solicitudes" (pieza 6): solo con laboratorio_farmaceutico + capacidad 'enrolamiento'. Se monta el
// hook real del gate (usePuedeEnrolar) sobre los dos hooks de datos mockeados.
let tipo: string = 'laboratorio_farmaceutico'
let capacidades: string[] = ['visitadores', 'enrolamiento']
let cargando = false

vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({ loading: cargando, empresa: { id: 'e1', tipo }, logout: vi.fn() }),
}))
vi.mock('@/proveedor/hooks/useCapacidades', () => ({
  useCapacidades: () => ({ loading: false, tieneCapacidad: (c: string) => capacidades.includes(c) }),
}))

const { default: VisitadorLayout } = await import('./VisitadorLayout')

const montar = () =>
  render(
    <MemoryRouter initialEntries={['/visitador/agendar']}>
      <VisitadorLayout />
    </MemoryRouter>,
  )

beforeEach(() => {
  tipo = 'laboratorio_farmaceutico'
  capacidades = ['visitadores', 'enrolamiento']
  cargando = false
})

describe('VisitadorLayout — pestaña Solicitudes', () => {
  it('lab farmacéutico con el módulo: 5 pestañas, con Solicitudes', () => {
    montar()
    for (const t of ['Agendar', 'Visitas', 'Ruta', 'Planes', 'Solicitudes']) {
      expect(screen.getByRole('button', { name: t })).toBeInTheDocument()
    }
  })

  it.each(['farmacia', 'laboratorio_clinico', 'empresa_afin'])('%s (aunque tuviera el módulo) no la ve', (t) => {
    tipo = t
    montar()
    expect(screen.queryByRole('button', { name: 'Solicitudes' })).toBeNull()
    expect(screen.getByRole('button', { name: 'Planes' })).toBeInTheDocument()
  })

  it('lab farmacéutico sin el módulo enrolamiento no la ve', () => {
    capacidades = ['visitadores']
    montar()
    expect(screen.queryByRole('button', { name: 'Solicitudes' })).toBeNull()
  })

  it('mientras carga la cuenta no la muestra (sin parpadeo)', () => {
    cargando = true
    montar()
    expect(screen.queryByRole('button', { name: 'Solicitudes' })).toBeNull()
  })
})
