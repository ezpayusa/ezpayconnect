import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, within, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Agendar del visitador + enrolamiento (pieza 3): indicador de prioridad, turnos reservados antes de fecha_minima,
// salto de semana, "sin resultados" con el link a solicitar alta detrás del gate, y enrolar con 'libre'.

let medicos: { id: string; nombre_completo: string; especialidad: string | null }[] = []
// Un turno 09:00-10:00 todos los días de la semana.
const disponibilidad = [0, 1, 2, 3, 4, 5, 6].map((d) => ({
  id: `d${d}`, medico_id: 'med-1', dia_semana: d, hora_inicio: '09:00', hora_fin: '10:00', duracion_slot: 60, activo: true,
}))
let puedeEnrolar = true
const prioridadParaAgendar = vi.fn()
const enrolarMedico = vi.fn()
const toastError = vi.fn()
const toastSuccess = vi.fn()

vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a), success: (...a: unknown[]) => toastSuccess(...a) } }))
vi.mock('@/lib/supabase', () => ({ supabase: { rpc: async () => ({ data: [], error: null }) } }))
vi.mock('@/proveedor/hooks/useMedicosDisponibles', () => ({
  useMedicosDisponibles: () => ({
    medicos, disponibilidad, loading: false, buscarMedicos: vi.fn(), fetchDisponibilidadMedico: vi.fn(async () => {}),
  }),
}))
vi.mock('@/proveedor/hooks/useVisitasAgendadas', () => ({
  useVisitasAgendadas: () => ({ agendarVisita: vi.fn(), saving: false, fetchSlotsOcupados: async () => [] }),
}))
vi.mock('@/proveedor/hooks/usePlanesVisitador', () => ({ usePlanesVisitador: () => ({ visitasDisponibles: 10 }) }))
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({ useProveedorAuth: () => ({ puede: () => false }) }))
vi.mock('@/visitador/hooks/useEnrolamiento', () => ({ useEnrolamiento: () => ({ prioridadParaAgendar, enrolarMedico }) }))
vi.mock('@/visitador/hooks/usePuedeEnrolar', () => ({ usePuedeEnrolar: () => ({ puedeEnrolar, loading: false }) }))

const { default: VisitadorAgendarPage } = await import('./VisitadorAgendarPage')

const montar = async () => {
  render(
    <MemoryRouter>
      <VisitadorAgendarPage />
    </MemoryRouter>,
  )
  await act(async () => {}) // deja resolver estado_plan_visitas del montaje
}

const elegirMedico = async () => {
  fireEvent.click(screen.getByRole('button', { name: 'Seleccionar' }))
  await screen.findByText('Horarios disponibles')
}

const turnos = () => screen.getAllByRole('button', { name: /09:00 – 10:00/ })

beforeEach(() => {
  // Miércoles 21-oct-2026 (solo se falsea Date: las promesas y los timers siguen reales).
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(2026, 9, 21, 10, 0))
  medicos = [{ id: 'med-1', nombre_completo: 'Dra. Ana Pérez', especialidad: 'Cardiología' }]
  puedeEnrolar = true
  prioridadParaAgendar.mockReset()
  enrolarMedico.mockReset()
  toastError.mockReset()
  toastSuccess.mockReset()
})
afterEach(() => vi.useRealTimers())

describe('VisitadorAgendarPage — prioridad al agendar', () => {
  it("'propia' muestra el aviso con las visitas y no bloquea turnos", async () => {
    prioridadParaAgendar.mockResolvedValue({ ok: true, data: { estado: 'propia', fecha_minima: null, visitas_completadas: 3, visitas_limite: 8 } })
    await montar()
    await elegirMedico()
    expect(await screen.findByTestId('prioridad-propia')).toHaveTextContent('Tienes prioridad con este médico (3 de 8 visitas)')
    expect(prioridadParaAgendar).toHaveBeenCalledWith('med-1')
    await waitFor(() => expect(turnos().length).toBeGreaterThan(0))
    expect(turnos().every((b) => !(b as HTMLButtonElement).disabled)).toBe(true)
    expect(screen.queryByRole('button', { name: 'Enrolar médico' })).toBeNull()
  })

  it("'otro_laboratorio' salta a la semana de fecha_minima y deshabilita los turnos anteriores", async () => {
    // Viernes 30-oct: la semana siguiente (lun 26 – dom 1).
    prioridadParaAgendar.mockResolvedValue({ ok: true, data: { estado: 'otro_laboratorio', fecha_minima: '2026-10-30', visitas_completadas: null, visitas_limite: null } })
    await montar()
    await elegirMedico()
    expect(await screen.findByTestId('prioridad-otro')).toHaveTextContent(
      'Este médico tiene prioridad de otro laboratorio. Puedes agendar desde 30/10/2026')
    expect(await screen.findByText('26/10 – 01/11')).toBeInTheDocument()
    await waitFor(() => expect(turnos()).toHaveLength(7))
    const estado = turnos().map((b) => (b as HTMLButtonElement).disabled)
    // lun 26, mar 27, mié 28, jue 29 reservados; vie 30, sáb 31, dom 1 libres
    expect(estado).toEqual([true, true, true, true, false, false, false])
    expect(turnos().filter((b) => b.hasAttribute('data-reservado'))).toHaveLength(4)
    expect(screen.queryByRole('button', { name: 'Enrolar médico' })).toBeNull()
  })

  it("'otro_laboratorio' con fecha_minima en la semana actual no mueve la grilla", async () => {
    prioridadParaAgendar.mockResolvedValue({ ok: true, data: { estado: 'otro_laboratorio', fecha_minima: '2026-10-23', visitas_completadas: null, visitas_limite: null } })
    await montar()
    await elegirMedico()
    await screen.findByTestId('prioridad-otro')
    expect(screen.getByText('19/10 – 25/10')).toBeInTheDocument()
    // Hoy es mié 21 (lun y mar no se muestran): mié 21 y jue 22 reservados; vie 23 en adelante libres.
    await waitFor(() => expect(turnos()).toHaveLength(5))
    expect(turnos().map((b) => (b as HTMLButtonElement).disabled)).toEqual([true, true, false, false, false])
  })

  it("'libre' no muestra aviso; con el gate ofrece Enrolar y PV013 muestra el mensaje del servidor", async () => {
    prioridadParaAgendar.mockResolvedValue({ ok: true, data: { estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null } })
    enrolarMedico.mockResolvedValue({ ok: false, error: { code: 'PV013', mensaje: 'Este médico ya fue enrolado por otro laboratorio.' } })
    await montar()
    await elegirMedico()
    const boton = await screen.findByRole('button', { name: 'Enrolar médico' })
    expect(screen.queryByTestId('prioridad-propia')).toBeNull()
    expect(screen.queryByTestId('prioridad-otro')).toBeNull()
    fireEvent.click(boton)
    await waitFor(() => expect(toastError).toHaveBeenCalledWith('Este médico ya fue enrolado por otro laboratorio.'))
    expect(enrolarMedico).toHaveBeenCalledWith('med-1')
  })

  it("'libre' + enrolar OK vuelve a pedir la prioridad", async () => {
    prioridadParaAgendar
      .mockResolvedValueOnce({ ok: true, data: { estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null } })
      .mockResolvedValueOnce({ ok: true, data: { estado: 'propia', fecha_minima: null, visitas_completadas: 0, visitas_limite: 8 } })
    enrolarMedico.mockResolvedValue({ ok: true, data: 'enrolado' })
    await montar()
    await elegirMedico()
    fireEvent.click(await screen.findByRole('button', { name: 'Enrolar médico' }))
    expect(await screen.findByTestId('prioridad-propia')).toHaveTextContent('(0 de 8 visitas)')
    expect(toastSuccess).toHaveBeenCalled()
  })

  it("'libre' sin el gate (farmacia o sin módulo) no ofrece Enrolar", async () => {
    puedeEnrolar = false
    prioridadParaAgendar.mockResolvedValue({ ok: true, data: { estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null } })
    await montar()
    await elegirMedico()
    await waitFor(() => expect(prioridadParaAgendar).toHaveBeenCalled())
    expect(screen.queryByRole('button', { name: 'Enrolar médico' })).toBeNull()
  })

  it('si prioridad_para_agendar falla (PV026) no se muestra indicador ni se bloquea nada', async () => {
    prioridadParaAgendar.mockResolvedValue({ ok: false, error: { code: 'PV026', mensaje: 'No puedes consultar a este médico.' } })
    await montar()
    await elegirMedico()
    await waitFor(() => expect(turnos().length).toBeGreaterThan(0))
    expect(screen.queryByTestId('prioridad-otro')).toBeNull()
    expect(turnos().every((b) => !(b as HTMLButtonElement).disabled)).toBe(true)
  })
})

describe('VisitadorAgendarPage — búsqueda sin resultados', () => {
  const buscar = () => fireEvent.click(screen.getByRole('button', { name: /Buscar/ }))

  it('0 filas muestra el estado vacío con el link a solicitar alta (con el gate)', async () => {
    medicos = []
    await montar()
    expect(screen.queryByTestId('busqueda-sin-resultados')).toBeNull() // antes de buscar, nada
    buscar()
    const vacio = screen.getByTestId('busqueda-sin-resultados')
    expect(within(vacio).getByRole('button', { name: '¿No encuentras al médico? Solicita su alta' })).toBeInTheDocument()
  })

  it('sin el gate, el estado vacío no ofrece solicitar alta', async () => {
    medicos = []
    puedeEnrolar = false
    await montar()
    buscar()
    const vacio = screen.getByTestId('busqueda-sin-resultados')
    expect(within(vacio).queryByRole('button', { name: /Solicita su alta/ })).toBeNull()
  })
})
