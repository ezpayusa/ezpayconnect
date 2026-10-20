import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { ESTADOS_SOLICITUD } from '@/visitador/lib/enrolamiento'
import { mapearErrorRpc } from '@/lib/erroresRpc'

const listar = vi.fn()
const aprobar = vi.fn()
const rechazar = vi.fn()
const reenviar = vi.fn()
const toastError = vi.fn()
const toastSuccess = vi.fn()

vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a), success: (...a: unknown[]) => toastSuccess(...a) } }))
vi.mock('@/hooks/admin/useSolicitudesAlta', () => ({ useSolicitudesAlta: () => ({ listar, aprobar, rechazar, reenviar }) }))

const { default: SolicitudesAltaMedicosPage } = await import('./SolicitudesAltaMedicosPage')

const GT = 'pais-gt'
const HN = 'pais-hn'
const fila = (id: string, estado: string, pais = GT, extra: Record<string, unknown> = {}) => ({
  id, pais_id: pais, nombre_completo: `Médico ${id}`, email: `${id}@x.co`, telefono: '5555-1234',
  especialidad_nombre: 'Cardiología', numero_colegiado: 'C-1', nombre_clinica: 'Clínica QA', empresa_nombre: 'Lab QA',
  solicitante_nombre: 'Visitador QA', estado, motivo_rechazo: null, created_at: '2026-10-20T10:00:00Z', ...extra,
})
const TODAS = [
  fila('p', 'pendiente'), fila('i', 'invitada'), fila('g', 'registrada'),
  fila('r', 'rechazada', GT, { motivo_rechazo: 'El colegiado no coincide.' }), fila('c', 'cancelada'),
  fila('hn', 'pendiente', HN),
]

const montar = async (ruta = `/admin-ezpay/pais/${GT}/solicitudes-alta-medicos`) => {
  render(
    <MemoryRouter initialEntries={[ruta]}>
      <Routes>
        <Route path="/admin-ezpay/pais/:paisId/solicitudes-alta-medicos" element={<SolicitudesAltaMedicosPage />} />
        <Route path="/admin-ezpay/solicitudes-alta-medicos" element={<SolicitudesAltaMedicosPage />} />
      </Routes>
    </MemoryRouter>,
  )
  await screen.findAllByTestId('solicitud-alta').catch(() => null)
}
const tarjeta = (nombre: string) => screen.getByText(nombre).closest('[data-testid="solicitud-alta"]') as HTMLElement
const nombres = () => screen.queryAllByTestId('solicitud-alta').map((t) => within(t).getByText(/^Médico /).textContent)
const errorPV = (code: string, message: string) => ({ ok: false, error: mapearErrorRpc({ code, message }) })

beforeEach(() => {
  for (const f of [listar, aprobar, rechazar, reenviar, toastError, toastSuccess]) f.mockReset()
  listar.mockResolvedValue({ ok: true, data: TODAS })
})

describe('SolicitudesAltaMedicosPage — filtros', () => {
  it('arranca en Pendiente y pide p_estado al servidor; cambiar el filtro vuelve a pedir', async () => {
    await montar()
    expect(listar).toHaveBeenNthCalledWith(1, 'pendiente')
    fireEvent.change(screen.getByLabelText('Filtrar por estado'), { target: { value: 'invitada' } })
    await waitFor(() => expect(listar).toHaveBeenLastCalledWith('invitada'))
    fireEvent.change(screen.getByLabelText('Filtrar por estado'), { target: { value: 'todas' } })
    await waitFor(() => expect(listar).toHaveBeenLastCalledWith(null))
  })

  it('modo país: solo las del paisId de la URL', async () => {
    await montar()
    expect(nombres()).not.toContain('Médico hn')
    expect(nombres()).toHaveLength(5)
  })

  it('menú global (sin paisId): todas', async () => {
    await montar('/admin-ezpay/solicitudes-alta-medicos')
    expect(nombres()).toContain('Médico hn')
    expect(nombres()).toHaveLength(6)
  })

  it('pinta los datos de la solicitud y el badge desde el mapa único', async () => {
    await montar()
    const t = within(tarjeta('Médico p'))
    for (const txt of ['p@x.co', '5555-1234', 'Cardiología', 'C-1', 'Clínica QA', 'Lab QA', 'Visitador QA']) {
      expect(t.getByText(txt)).toBeInTheDocument()
    }
    for (const s of TODAS.filter((x) => x.pais_id === GT)) {
      expect(within(tarjeta(s.nombre_completo)).getByTestId('badge-estado'))
        .toHaveTextContent(ESTADOS_SOLICITUD[s.estado as keyof typeof ESTADOS_SOLICITUD].label)
    }
    expect(within(tarjeta('Médico r')).getByTestId('motivo-rechazo')).toHaveTextContent('El colegiado no coincide.')
  })
})

describe('SolicitudesAltaMedicosPage — acciones por estado', () => {
  it('Pendiente: aprobar y rechazar; Invitada: reenviar; el resto, ninguna', async () => {
    await montar()
    const botones = (n: string) => within(tarjeta(n)).queryAllByRole('button').map((b) => b.textContent?.trim())
    expect(botones('Médico p')).toEqual(['Aprobar y enviar invitación', 'Rechazar'])
    expect(botones('Médico i')).toEqual(['Reenviar invitación'])
    for (const n of ['Médico g', 'Médico r', 'Médico c']) expect(botones(n)).toEqual([])
  })

  it('aprobar pide confirmación con el correo; si no confirma, no llama a la RPC', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    await montar()
    fireEvent.click(within(tarjeta('Médico p')).getByRole('button', { name: 'Aprobar y enviar invitación' }))
    expect(confirm).toHaveBeenCalledWith(expect.stringContaining('p@x.co'))
    expect(aprobar).not.toHaveBeenCalled()
    confirm.mockRestore()
  })

  it('aprobar confirmado: llama a la RPC, toast y recarga', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    aprobar.mockResolvedValue({ ok: true, data: true })
    await montar()
    fireEvent.click(within(tarjeta('Médico p')).getByRole('button', { name: 'Aprobar y enviar invitación' }))
    await waitFor(() => expect(aprobar).toHaveBeenCalledWith('p'))
    await waitFor(() => expect(listar).toHaveBeenCalledTimes(2))
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('p@x.co'))
    confirm.mockRestore()
  })

  it('reenviar pide confirmación con el correo y recarga', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    reenviar.mockResolvedValue({ ok: true, data: true })
    await montar()
    fireEvent.click(within(tarjeta('Médico i')).getByRole('button', { name: 'Reenviar invitación' }))
    expect(confirm).toHaveBeenCalledWith(expect.stringContaining('i@x.co'))
    await waitFor(() => expect(reenviar).toHaveBeenCalledWith('i'))
    await waitFor(() => expect(listar).toHaveBeenCalledTimes(2))
    expect(toastSuccess).toHaveBeenCalled()
    confirm.mockRestore()
  })

  it.each([
    ['PV022', 'La solicitud ya no está pendiente.'],
    ['PV023', 'La solicitud no existe o no puedes gestionarla.'],
    ['PV024', 'Este correo ya tiene cuenta en MED: rechaza la solicitud o pide al visitador que enrole al médico.'],
    ['PV025', 'Este correo ya tiene una invitación vigente de MED. Espera a que el médico la use o a que venza.'],
  ])('error %s: toast con el mensaje del servidor y recarga', async (code, message) => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    aprobar.mockResolvedValue(errorPV(code, message))
    await montar()
    fireEvent.click(within(tarjeta('Médico p')).getByRole('button', { name: 'Aprobar y enviar invitación' }))
    await waitFor(() => expect(toastError).toHaveBeenCalledWith(message))
    await waitFor(() => expect(listar).toHaveBeenCalledTimes(2))
    expect(toastSuccess).not.toHaveBeenCalled()
    confirm.mockRestore()
  })
})

describe('SolicitudesAltaMedicosPage — rechazo con motivo', () => {
  const abrir = async () => {
    await montar()
    fireEvent.click(within(tarjeta('Médico p')).getByRole('button', { name: 'Rechazar' }))
    return screen.getByRole('dialog')
  }

  it('el botón queda deshabilitado sin motivo, con menos de 5 caracteres o solo espacios', async () => {
    const dlg = within(await abrir())
    const boton = dlg.getByRole('button', { name: 'Confirmar rechazo' })
    expect(boton).toBeDisabled()
    fireEvent.change(dlg.getByLabelText(/Motivo del rechazo/), { target: { value: 'abcd' } })
    expect(boton).toBeDisabled()
    fireEvent.change(dlg.getByLabelText(/Motivo del rechazo/), { target: { value: '     abcd     ' } })
    expect(boton).toBeDisabled()
    fireEvent.click(boton)
    expect(rechazar).not.toHaveBeenCalled()
  })

  it('con motivo válido: llama a la RPC con el motivo recortado, toast, cierra y recarga', async () => {
    rechazar.mockResolvedValue({ ok: true, data: true })
    const dlg = within(await abrir())
    fireEvent.change(dlg.getByLabelText(/Motivo del rechazo/), { target: { value: '  El colegiado no existe.  ' } })
    const boton = dlg.getByRole('button', { name: 'Confirmar rechazo' })
    expect(boton).toBeEnabled()
    fireEvent.click(boton)
    await waitFor(() => expect(rechazar).toHaveBeenCalledWith('p', 'El colegiado no existe.'))
    await waitFor(() => expect(listar).toHaveBeenCalledTimes(2))
    expect(toastSuccess).toHaveBeenCalledWith('Solicitud rechazada.')
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  })

  it('error PV022 al rechazar: toast con el mensaje del servidor y el dialog sigue abierto', async () => {
    rechazar.mockResolvedValue(errorPV('PV022', 'La solicitud ya no está pendiente.'))
    const dlg = within(await abrir())
    fireEvent.change(dlg.getByLabelText(/Motivo del rechazo/), { target: { value: 'Motivo suficiente' } })
    fireEvent.click(dlg.getByRole('button', { name: 'Confirmar rechazo' }))
    await waitFor(() => expect(toastError).toHaveBeenCalledWith('La solicitud ya no está pendiente.'))
    await waitFor(() => expect(listar).toHaveBeenCalledTimes(2))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(toastSuccess).not.toHaveBeenCalled()
  })
})
