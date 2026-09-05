import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'

// La hora de una visita es OPCIONAL. Que el input arranque prefijado la vuelve obligatoria de
// hecho: toda visita nace con una hora que nadie eligió. Estos tests fijan la asimetría —vacío al
// agendar, el valor actual al reprogramar— porque es la clase de detalle que un refactor futuro
// "unifica" sin darse cuenta de que unificar acá es el bug.
const llamadas: { fn: string; args: unknown[] }[] = []
let errorPlanificar: unknown = null

vi.mock('../lib/api', () => ({
  planificarVisita: async (...args: unknown[]) => {
    llamadas.push({ fn: 'planificarVisita', args }); return { data: null, error: errorPlanificar }
  },
  reprogramarVisita: async (...args: unknown[]) => {
    llamadas.push({ fn: 'reprogramarVisita', args }); return { data: null, error: null }
  },
  cancelarVisita: async (...args: unknown[]) => {
    llamadas.push({ fn: 'cancelarVisita', args }); return { data: null, error: null }
  },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

const { AgendarVisita, AccionesVisitaPlanificada, FormFechaHora } = await import('./AgendaVisita')

const visita = (over: Record<string, unknown> = {}) => ({
  id: 'vis-1', prospecto_id: 'pros-1', asesor_id: 'ase-1', pais_id: 'gt', jornada_id: null,
  fecha_planificada: '2026-09-20', hora_planificada: '14:45:00', estado: 'planificada',
  checkin_at: null, checkout_at: null, ...over,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
}) as any

// Los <label> del form no tienen htmlFor, asi que getByLabelText no los asocia. Se va por el id
// que el propio componente expone (`${idPrefix}-hora`), que ademas es el contrato de los e2e.
const campo = (id: string) => document.getElementById(id) as HTMLInputElement

beforeEach(() => { llamadas.length = 0; errorPlanificar = null })

describe('FormFechaHora — la hora opcional no se inventa', () => {
  it('sin `inicial`, el input de hora arranca VACIO', () => {
    render(<FormFechaHora label="Agendar" onSubmit={async () => {}} />)
    expect(campo('agenda-hora').value).toBe('')
  })

  it('con `inicial.hora`, arranca con esa hora recortada a HH:mm', () => {
    render(<FormFechaHora label="Reprogramar" onSubmit={async () => {}}
      inicial={{ fecha: '2026-09-20', hora: '14:45:00' }} />)
    expect(campo('agenda-hora').value).toBe('14:45')
  })

  it('con `inicial` SIN hora, arranca vacio igual: prefijar solo vale si hay valor real', () => {
    render(<FormFechaHora label="Reprogramar" onSubmit={async () => {}}
      inicial={{ fecha: '2026-09-20', hora: null }} />)
    expect(campo('agenda-hora').value).toBe('')
  })

  it('hora vacia se entrega como null, NO como cadena vacia', async () => {
    const vistos: { fecha: string; hora: string | null }[] = []
    render(<FormFechaHora label="Agendar" onSubmit={async (v) => { vistos.push(v) }} />)
    fireEvent.click(screen.getByRole('button', { name: 'Agendar' }))
    await waitFor(() => expect(vistos).toHaveLength(1))
    expect(vistos[0].hora).toBeNull()
  })
})

describe('AgendarVisita — modo agendar', () => {
  it('al abrir el formulario, la hora esta vacia', async () => {
    render(<AgendarVisita prospectoId="pros-1" />)
    fireEvent.click(await screen.findByRole('button', { name: /agendar visita/i }))
    expect(campo('agendar-hora').value).toBe('')
  })

  it('confirmar sin tocar la hora manda hora null a la RPC', async () => {
    render(<AgendarVisita prospectoId="pros-1" />)
    fireEvent.click(await screen.findByRole('button', { name: /agendar visita/i }))
    fireEvent.click(screen.getByRole('button', { name: 'Agendar' }))
    await waitFor(() => expect(llamadas).toHaveLength(1))
    expect(llamadas[0].fn).toBe('planificarVisita')
    expect(llamadas[0].args[2]).toBeNull()
  })

  it('el 23505 dice "visita ACTIVA": desde la mig 282 una cancelada NO bloquea el dia', async () => {
    errorPlanificar = { code: '23505', message: 'duplicate key value violates unique constraint "visitas_com_una_por_dia"' }
    render(<AgendarVisita prospectoId="pros-1" />)
    fireEvent.click(await screen.findByRole('button', { name: /agendar visita/i }))
    fireEvent.click(screen.getByRole('button', { name: 'Agendar' }))
    await waitFor(() => {
      expect(screen.getByText('Ya hay una visita activa para este prospecto ese día.')).toBeInTheDocument()
    })
    // el texto viejo mentia: decia que el dia estaba tomado aunque la unica visita estuviera cancelada
    expect(screen.queryByText('Ya hay una visita para este prospecto ese día.')).not.toBeInTheDocument()
  })
})

describe('AccionesVisitaPlanificada — modo reprogramar', () => {
  it('el formulario arranca con la fecha y la hora que la visita YA tiene', () => {
    render(<AccionesVisitaPlanificada visita={visita()} />)
    fireEvent.click(screen.getByTestId('btn-reprogramar-vis-1'))
    expect(campo('reprog-vis-1-hora').value).toBe('14:45')
    expect(campo('reprog-vis-1-fecha').value).toBe('2026-09-20')
  })

  it('si la visita no tiene hora, el input arranca vacio y se manda null', async () => {
    render(<AccionesVisitaPlanificada visita={visita({ hora_planificada: null })} />)
    fireEvent.click(screen.getByTestId('btn-reprogramar-vis-1'))
    expect(campo('reprog-vis-1-hora').value).toBe('')
    fireEvent.click(screen.getByRole('button', { name: 'Reprogramar' }))
    await waitFor(() => expect(llamadas).toHaveLength(1))
    expect(llamadas[0].fn).toBe('reprogramarVisita')
    expect(llamadas[0].args[2]).toBeNull()
  })
})
