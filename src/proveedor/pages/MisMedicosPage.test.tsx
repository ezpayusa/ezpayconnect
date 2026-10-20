import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { puedeRol } from '@/proveedor/lib/permisos'
import { puedeEnrolarEmpresa } from '@/visitador/lib/visibilidadEnrolamiento'

// Gate de la página: laboratorio_farmaceutico + módulo 'enrolamiento' + visitadores.gestionar (admin y supervisor),
// con la matriz real de permisos.ts y el predicado real de visibilidadEnrolamiento.ts.
let rol = 'admin'
let tipo = 'laboratorio_farmaceutico'
let enrolamiento = true
const listarMisMedicos = vi.fn()
const toastError = vi.fn()

vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a) } }))
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({ loading: false, puede: (p: Parameters<typeof puedeRol>[1]) => puedeRol(rol, p) }),
}))
vi.mock('@/visitador/hooks/usePuedeEnrolar', () => ({
  usePuedeEnrolar: () => ({ puedeEnrolar: puedeEnrolarEmpresa(tipo, enrolamiento), loading: false }),
}))
vi.mock('@/visitador/hooks/useEnrolamiento', () => ({ useEnrolamiento: () => ({ listarMisMedicos }) }))

const { default: MisMedicosPage } = await import('./MisMedicosPage')

const MEDICOS = [
  { medico_id: 'm1', nombre_completo: 'Dra. Activa', especialidad: 'Pediatría', lab_enrolador_fecha: '2026-10-01T15:00:00Z',
    prioridad_activa: true, visitas_completadas: 2, visitas_limite: 8, prioridad_vence_el: '2028-04-01', dias_ventaja: 5 },
  { medico_id: 'm2', nombre_completo: 'Dr. Vencido', especialidad: null, lab_enrolador_fecha: '2025-01-10T15:00:00Z',
    prioridad_activa: false, visitas_completadas: 8, visitas_limite: 8, prioridad_vence_el: '2026-07-10', dias_ventaja: 5 },
]

const montar = () =>
  render(
    <MemoryRouter initialEntries={['/proveedor/mis-medicos']}>
      <Routes>
        <Route path="/proveedor/mis-medicos" element={<MisMedicosPage />} />
        <Route path="/proveedor/dashboard" element={<p>PANTALLA DASHBOARD</p>} />
      </Routes>
    </MemoryRouter>,
  )

beforeEach(() => {
  rol = 'admin'
  tipo = 'laboratorio_farmaceutico'
  enrolamiento = true
  listarMisMedicos.mockReset()
  toastError.mockReset()
  listarMisMedicos.mockResolvedValue({ ok: true, data: MEDICOS })
})

describe('MisMedicosPage — gate', () => {
  it.each(['admin', 'supervisor'])('rol %s de un lab farmacéutico con el módulo entra', async (r) => {
    rol = r
    montar()
    expect(await screen.findByText('Dra. Activa')).toBeInTheDocument()
  })

  it.each(['visitador_medico', 'catalogo', 'marketing', 'finanzas', 'lectura'])('rol %s vuelve al dashboard', (r) => {
    rol = r
    montar()
    expect(screen.getByText('PANTALLA DASHBOARD')).toBeInTheDocument()
    expect(listarMisMedicos).not.toHaveBeenCalled()
  })

  it.each(['farmacia', 'laboratorio_clinico', 'empresa_afin'])('empresa %s vuelve al dashboard', (t) => {
    tipo = t
    montar()
    expect(screen.getByText('PANTALLA DASHBOARD')).toBeInTheDocument()
  })

  it('sin el módulo enrolamiento vuelve al dashboard', () => {
    enrolamiento = false
    montar()
    expect(screen.getByText('PANTALLA DASHBOARD')).toBeInTheDocument()
  })
})

describe('MisMedicosPage — tabla', () => {
  it('columnas sin correo ni teléfono', async () => {
    montar()
    await screen.findByText('Dra. Activa')
    const cabeceras = screen.getAllByRole('columnheader').map((th) => th.textContent)
    expect(cabeceras).toEqual(['Nombre', 'Especialidad', 'Enrolado el', 'Prioridad', 'Visitas', 'Vence el', 'Días de ventaja'])
    expect(screen.queryByText(/correo|tel[eé]fono|email/i)).toBeNull()
  })

  it('badge activa/vencida, visitas X de Y, vence el y días de ventaja', async () => {
    montar()
    await screen.findByText('Dra. Activa')
    const [activa, vencida] = screen.getAllByTestId('medico-enrolado').map((tr) => within(tr))
    expect(activa.getByTestId('badge-prioridad')).toHaveTextContent('Activa')
    expect(activa.getByText('2 de 8')).toBeInTheDocument()
    expect(activa.getByText('01/04/2028')).toBeInTheDocument()
    expect(activa.getByText('5')).toBeInTheDocument()
    expect(vencida.getByTestId('badge-prioridad')).toHaveTextContent('Vencida')
    expect(vencida.getByText('8 de 8')).toBeInTheDocument()
  })

  it('estado vacío', async () => {
    listarMisMedicos.mockResolvedValue({ ok: true, data: [] })
    montar()
    expect(await screen.findByText('Todavía no tienes médicos enrolados.')).toBeInTheDocument()
  })

  it('error de la RPC: toast con el mensaje', async () => {
    listarMisMedicos.mockResolvedValue({ ok: false, error: { code: 'PV017', mensaje: 'Tu rol en la empresa no te permite ver los médicos enrolados.', destino: 'toast', reportar: false } })
    montar()
    expect(await screen.findByTestId('error-mis-medicos')).toHaveTextContent('Tu rol en la empresa no te permite ver los médicos enrolados.')
    expect(toastError).toHaveBeenCalledWith('Tu rol en la empresa no te permite ver los médicos enrolados.')
    expect(screen.queryByText('Todavía no tienes médicos enrolados.')).toBeNull()
  })
})
