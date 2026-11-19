import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import RecetaModal, { MSG_ERROR_ALERGIAS, motivoAlergiaValido } from './RecetaModal'

// Lo que se mide: H20 (mig 395). El modal pregunta a alergias_en_receta por cada cambio de medicamentos,
// exige un motivo (5-500) en los ítems que coinciden, no deja emitir sin haber verificado, y un PR011 del
// servidor se muestra en el modal (no como error genérico). H2: la cita viaja en cita_id.

const rpc = vi.fn()
const createReceta = vi.fn()
const toastError = vi.fn()

vi.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }))
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ perfil: { rol: 'medico' } }) }))
vi.mock('@/hooks/usePacientes', () => ({ usePacientes: () => ({ pacientes: [] }) }))
vi.mock('@/hooks/useBusquedaMedicamentos', () => ({
  useBusquedaMedicamentos: () => ({ resultados: [], loading: false, buscarPorMedicamento: vi.fn() }),
}))
vi.mock('@/hooks/useRecetas', () => ({
  useRecetas: () => ({ createReceta: (...a: unknown[]) => createReceta(...a) }),
  useMedicamentos: () => ({
    medicamentos: [
      { id: 7, nombre_generico: 'Penicilina G', nombre_comercial: null, presentacion: 'Amp', concentracion: '1M', categoria_regulatoria: null },
    ],
    loading: false,
    error: null,
    fetchMedicamentos: vi.fn(),
  }),
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: (...a: unknown[]) => toastError(...a), warning: vi.fn() } }))

const PACIENTE = { id: 23, nombre: 'Paciente QA', alergias: 'Penicilina, sulfas', medicamentos_en_uso: null }

function renderModal() {
  return render(
    <RecetaModal open onOpenChange={vi.fn()} paciente={PACIENTE} pacienteIdPreseleccionado="23" citaId={501} />,
  )
}

function agregarPenicilina() {
  const fila = screen.getByText('Penicilina G').parentElement!.parentElement!
  fireEvent.click(within(fila).getByRole('button'))
}

function llenarDosis() {
  fireEvent.change(screen.getByPlaceholderText('500mg'), { target: { value: '1 amp' } })
  fireEvent.change(screen.getByPlaceholderText('Cada 8 horas'), { target: { value: 'Cada 12 horas' } })
}

const botonEmitir = () => screen.getByRole('button', { name: /Generar Receta/ })

beforeEach(() => {
  rpc.mockReset()
  createReceta.mockReset()
  toastError.mockReset()
})

describe('motivoAlergiaValido', () => {
  it('exige entre 5 y 500 caracteres sin contar espacios de los bordes', () => {
    expect(motivoAlergiaValido(undefined)).toBe(false)
    expect(motivoAlergiaValido('   abcd   ')).toBe(false)
    expect(motivoAlergiaValido('abcde')).toBe(true)
    expect(motivoAlergiaValido('x'.repeat(500))).toBe(true)
    expect(motivoAlergiaValido('x'.repeat(501))).toBe(false)
  })
})

describe('RecetaModal — alergias (H20)', () => {
  it('coincidencia: recuadro + motivo obligatorio; con motivo emite y manda motivo y cita', async () => {
    rpc.mockResolvedValue({ data: [{ medicamento_id: 7, alergia: 'penicilina' }], error: null })
    createReceta.mockResolvedValue({ data: { id: 900 }, folio: 'X-000001-20261119', error: null })
    renderModal()
    agregarPenicilina()

    expect(await screen.findByText('Coincide con la alergia registrada «penicilina».')).toBeInTheDocument()
    expect(rpc).toHaveBeenCalledWith('alergias_en_receta', { p_paciente_id: 23, p_medicamento_ids: [7] })

    llenarDosis()
    await waitFor(() => expect(botonEmitir()).toBeEnabled())
    fireEvent.click(botonEmitir())
    expect(await screen.findByText('Confirma con un motivo la prescripción de "Penicilina G".')).toBeInTheDocument()
    expect(createReceta).not.toHaveBeenCalled()

    fireEvent.change(screen.getByLabelText(/Motivo para prescribirlo igual/), { target: { value: '  Prueba cutánea negativa  ' } })
    fireEvent.click(botonEmitir())
    await waitFor(() => expect(createReceta).toHaveBeenCalledTimes(1))
    const [receta, items] = createReceta.mock.calls[0]
    expect(receta).toMatchObject({ paciente_id: 23, cita_id: 501 })
    expect(items[0]).toMatchObject({ medicamento_id: 7, alergia_confirmacion_motivo: 'Prueba cutánea negativa' })
  })

  it('si la verificación falla, bloquea la emisión hasta reintentar con éxito', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '08006', message: 'network' } })
    renderModal()
    agregarPenicilina()
    llenarDosis()

    expect(await screen.findByText(MSG_ERROR_ALERGIAS)).toBeInTheDocument()
    expect(botonEmitir()).toBeDisabled()
    expect(screen.queryByText('network')).toBeNull()

    rpc.mockResolvedValueOnce({ data: [], error: null })
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await waitFor(() => expect(botonEmitir()).toBeEnabled())
    expect(screen.queryByText(MSG_ERROR_ALERGIAS)).toBeNull()
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it('PR011 del servidor: se muestra su mensaje en el modal y se marca el ítem, sin toast genérico', async () => {
    rpc.mockResolvedValue({ data: [], error: null })
    const msg = 'El medicamento "Penicilina G" coincide con la alergia registrada "penicilina". Confirma la prescripción con un motivo.'
    createReceta.mockResolvedValue({ data: null, error: msg, code: 'PR011' })
    renderModal()
    agregarPenicilina()
    llenarDosis()
    await waitFor(() => expect(botonEmitir()).toBeEnabled())
    expect(screen.queryByTestId('alergia-coincidencia')).toBeNull()

    fireEvent.click(botonEmitir())
    expect(await screen.findByText(msg)).toBeInTheDocument()
    expect(await screen.findByText('Coincide con la alergia registrada «penicilina».')).toBeInTheDocument()
    expect(toastError).not.toHaveBeenCalled()
  })
})
