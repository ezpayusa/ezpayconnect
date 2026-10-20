import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

let puedeEnrolar = true
const solicitarAlta = vi.fn()
const enrolarMedico = vi.fn()
const toastError = vi.fn()
const toastSuccess = vi.fn()

vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a), success: (...a: unknown[]) => toastSuccess(...a) } }))
vi.mock('@/lib/supabase', () => {
  const q = { select: () => q, eq: () => q, order: () => Promise.resolve({ data: [{ id: 'esp-1', nombre: 'Cardiología' }], error: null }) }
  return { supabase: { from: () => q } }
})
vi.mock('@/visitador/hooks/useEnrolamiento', () => ({ useEnrolamiento: () => ({ solicitarAlta, enrolarMedico }) }))
vi.mock('@/visitador/hooks/usePuedeEnrolar', () => ({ usePuedeEnrolar: () => ({ puedeEnrolar, loading: false }) }))

const { default: SolicitarAltaPage } = await import('./SolicitarAltaPage')

const montar = async () => {
  render(
    <MemoryRouter initialEntries={['/visitador/solicitar-alta']}>
      <Routes>
        <Route path="/visitador/solicitar-alta" element={<SolicitarAltaPage />} />
        <Route path="/visitador/solicitudes" element={<p>PANTALLA SOLICITUDES</p>} />
        <Route path="/visitador/agendar" element={<p>PANTALLA AGENDAR</p>} />
      </Routes>
    </MemoryRouter>,
  )
  await act(async () => {})
}

const llenar = (autorizar = true) => {
  fireEvent.change(screen.getByLabelText('Nombre completo *'), { target: { value: 'Dra. Ana Pérez' } })
  fireEvent.change(screen.getByLabelText('Correo *'), { target: { value: 'ana@clinica.com' } })
  if (autorizar) fireEvent.click(screen.getByRole('checkbox'))
}
const enviar = () => fireEvent.click(screen.getByRole('button', { name: 'Enviar solicitud' }))

beforeEach(() => {
  puedeEnrolar = true
  solicitarAlta.mockReset()
  enrolarMedico.mockReset()
  toastError.mockReset()
  toastSuccess.mockReset()
})

describe('SolicitarAltaPage', () => {
  it('trae los campos pedidos y la especialidad del catálogo', async () => {
    await montar()
    for (const l of ['Nombre completo *', 'Correo *', 'Teléfono', 'Especialidad', 'Número de colegiado', 'Nombre de la clínica']) {
      expect(screen.getByLabelText(l)).toBeInTheDocument()
    }
    expect(screen.getByRole('option', { name: 'Cardiología' })).toBeInTheDocument()
    expect(screen.getByText('El médico autorizó compartir estos datos con EZPay *')).toBeInTheDocument()
  })

  it('sin la casilla de autorización no llama a la RPC', async () => {
    await montar()
    llenar(false)
    enviar()
    expect(await screen.findByTestId('error-autorizado')).toBeInTheDocument()
    expect(solicitarAlta).not.toHaveBeenCalled()
  })

  it('con datos inválidos marca el campo y no llama a la RPC', async () => {
    await montar()
    fireEvent.change(screen.getByLabelText('Correo *'), { target: { value: 'ana@' } })
    fireEvent.click(screen.getByRole('checkbox'))
    enviar()
    expect(await screen.findByTestId('error-nombre')).toBeInTheDocument()
    expect(screen.getByTestId('error-email')).toBeInTheDocument()
    expect(solicitarAlta).not.toHaveBeenCalled()
  })

  it("'creada' va a Mis solicitudes con aviso de éxito", async () => {
    solicitarAlta.mockResolvedValue({ ok: true, data: { estado: 'creada', solicitud_id: 's-1' } })
    await montar()
    llenar()
    enviar()
    expect(await screen.findByText('PANTALLA SOLICITUDES')).toBeInTheDocument()
    expect(toastSuccess).toHaveBeenCalled()
    expect(solicitarAlta.mock.calls[0][0]).toMatchObject({ nombre: 'Dra. Ana Pérez', email: 'ana@clinica.com', autorizado: true })
  })

  it("'existe' ofrece enrolar y llama enrolar_medico con el medico_id devuelto", async () => {
    solicitarAlta.mockResolvedValue({ ok: true, data: { estado: 'existe', medico_id: 'med-77' } })
    enrolarMedico.mockResolvedValue({ ok: true, data: 'enrolado' })
    await montar()
    llenar()
    enviar()
    expect(await screen.findByText('Este médico ya está en MED. ¿Quieres enrolarlo?')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Enrolar médico' }))
    expect(await screen.findByText('PANTALLA AGENDAR')).toBeInTheDocument()
    expect(enrolarMedico).toHaveBeenCalledWith('med-77')
  })

  it("'existe' + PV013 muestra el mensaje del servidor y se queda", async () => {
    solicitarAlta.mockResolvedValue({ ok: true, data: { estado: 'existe', medico_id: 'med-77' } })
    enrolarMedico.mockResolvedValue({ ok: false, error: { code: 'PV013', mensaje: 'Este médico ya fue enrolado por otro laboratorio.', destino: 'toast' } })
    await montar()
    llenar()
    enviar()
    fireEvent.click(await screen.findByRole('button', { name: 'Enrolar médico' }))
    await waitFor(() => expect(toastError).toHaveBeenCalledWith('Este médico ya fue enrolado por otro laboratorio.'))
    expect(screen.queryByText('PANTALLA AGENDAR')).toBeNull()
  })

  it('PV021 del servidor va pegado al correo; PV019 arriba del botón', async () => {
    solicitarAlta.mockResolvedValueOnce({ ok: false, error: { code: 'PV021', mensaje: 'Este médico ya tiene una solicitud en curso.', destino: 'inline', campo: 'email' } })
    await montar()
    llenar()
    enviar()
    expect(await screen.findByTestId('error-email')).toHaveTextContent('Este médico ya tiene una solicitud en curso.')
    solicitarAlta.mockResolvedValueOnce({ ok: false, error: { code: 'PV019', mensaje: 'La especialidad elegida no existe.', destino: 'inline', campo: 'formulario' } })
    enviar()
    expect(await screen.findByTestId('error-general')).toHaveTextContent('La especialidad elegida no existe.')
  })

  it('sin el gate (farmacia o sin módulo) redirige a agendar', async () => {
    puedeEnrolar = false
    await montar()
    expect(screen.getByText('PANTALLA AGENDAR')).toBeInTheDocument()
  })
})
