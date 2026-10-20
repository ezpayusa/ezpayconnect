import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { ESTADOS_SOLICITUD } from '@/visitador/lib/enrolamiento'

const listarSolicitudes = vi.fn()
const cancelarSolicitud = vi.fn()
const toastError = vi.fn()
const toastSuccess = vi.fn()

vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a), success: (...a: unknown[]) => toastSuccess(...a) } }))
vi.mock('@/visitador/hooks/useEnrolamiento', () => ({ useEnrolamiento: () => ({ listarSolicitudes, cancelarSolicitud }) }))

const { default: SolicitudesPage } = await import('./SolicitudesPage')

const fila = (id: string, estado: string, extra: Record<string, unknown> = {}) => ({
  id, nombre_completo: `Médico ${id}`, email: `${id}@x.co`, especialidad_nombre: null, estado,
  motivo_rechazo: null, created_at: '2026-10-20T10:00:00Z', ...extra,
})
const TODAS = [
  fila('p', 'pendiente'), fila('i', 'invitada'), fila('g', 'registrada'),
  fila('r', 'rechazada', { motivo_rechazo: 'El colegiado no coincide.' }), fila('c', 'cancelada'),
]

const montar = async () => {
  render(
    <MemoryRouter initialEntries={['/visitador/solicitudes']}>
      <Routes>
        <Route path="/visitador/solicitudes" element={<SolicitudesPage />} />
        <Route path="/visitador/solicitar-alta" element={<p>PANTALLA SOLICITAR</p>} />
      </Routes>
    </MemoryRouter>,
  )
  await screen.findAllByTestId('solicitud').catch(() => null)
}
const tarjeta = (nombre: string) => screen.getByText(nombre).closest('[data-testid="solicitud"]') as HTMLElement

beforeEach(() => {
  listarSolicitudes.mockReset()
  cancelarSolicitud.mockReset()
  toastError.mockReset()
  toastSuccess.mockReset()
  listarSolicitudes.mockResolvedValue({ ok: true, data: TODAS })
})

describe('SolicitudesPage', () => {
  it('badge de cada estado desde el mapa único', async () => {
    await montar()
    for (const s of TODAS) {
      const badge = within(tarjeta(s.nombre_completo)).getByTestId('badge-estado')
      expect(badge).toHaveTextContent(ESTADOS_SOLICITUD[s.estado as keyof typeof ESTADOS_SOLICITUD].label)
    }
  })

  it('el motivo solo aparece en la rechazada', async () => {
    await montar()
    expect(screen.getAllByTestId('motivo-rechazo')).toHaveLength(1)
    expect(within(tarjeta('Médico r')).getByTestId('motivo-rechazo')).toHaveTextContent('El colegiado no coincide.')
  })

  it('Cancelar solo en la pendiente', async () => {
    await montar()
    expect(screen.getAllByRole('button', { name: 'Cancelar' })).toHaveLength(1)
    expect(within(tarjeta('Médico p')).getByRole('button', { name: 'Cancelar' })).toBeInTheDocument()
  })

  it('Cancelar pide confirmación; si no confirma, no llama a la RPC', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    await montar()
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(confirm).toHaveBeenCalled()
    expect(cancelarSolicitud).not.toHaveBeenCalled()
    confirm.mockRestore()
  })

  it('confirmado: cancela y recarga la lista', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    cancelarSolicitud.mockResolvedValue({ ok: true, data: true })
    await montar()
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    await waitFor(() => expect(cancelarSolicitud).toHaveBeenCalledWith('p'))
    await waitFor(() => expect(listarSolicitudes).toHaveBeenCalledTimes(2))
    expect(toastSuccess).toHaveBeenCalled()
    confirm.mockRestore()
  })

  it('PV022 (ya no está pendiente) muestra el mensaje y recarga', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    cancelarSolicitud.mockResolvedValue({ ok: false, error: { code: 'PV022', mensaje: 'La solicitud ya no está pendiente.', recargar: 'solicitudes' } })
    await montar()
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    await waitFor(() => expect(toastError).toHaveBeenCalledWith('La solicitud ya no está pendiente.'))
    await waitFor(() => expect(listarSolicitudes).toHaveBeenCalledTimes(2))
    confirm.mockRestore()
  })

  it('"Solicitar alta" lleva al formulario', async () => {
    await montar()
    fireEvent.click(screen.getByRole('button', { name: /Solicitar alta/ }))
    expect(screen.getByText('PANTALLA SOLICITAR')).toBeInTheDocument()
  })

  it('lista vacía', async () => {
    listarSolicitudes.mockResolvedValue({ ok: true, data: [] })
    await montar()
    expect(await screen.findByText('Todavía no tienes solicitudes de alta.')).toBeInTheDocument()
  })
})
