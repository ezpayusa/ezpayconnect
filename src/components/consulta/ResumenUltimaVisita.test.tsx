import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import ResumenUltimaVisita from './ResumenUltimaVisita'

// Lo que se mide: que cueste tokens SOLO con click (nada se invoca al montar), que el gate de
// consentimiento deshabilite el botón, sin_visita, las listas vacías ocultas y que un error del edge
// llegue al médico con su motivo y no como "non-2xx".

let consent: { data: unknown; error: unknown } = { data: [], error: null }
let invoke: { data: unknown; error: unknown } = { data: null, error: null }
const invocaciones: { fn: string; body: unknown }[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async () => consent,
    functions: {
      invoke: async (fn: string, opts: { body: unknown }) => {
        invocaciones.push({ fn, body: opts.body })
        return invoke
      },
    },
  },
}))

const httpError = (status: number, body: unknown) => ({
  name: 'FunctionsHttpError',
  message: 'Edge Function returned a non-2xx status code',
  context: new Response(JSON.stringify(body), { status }),
})

const boton = () => screen.getByRole('button', { name: /resumen de la última visita|volver a generar|generando/i })

beforeEach(() => {
  consent = { data: [], error: null }
  invoke = { data: null, error: null }
  invocaciones.length = 0
})

describe('ResumenUltimaVisita', () => {
  it('no invoca nada al montar y muestra el aviso fijo', async () => {
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    expect(invocaciones).toHaveLength(0)
    expect(screen.getByText(/Resumen generado por IA a partir de la nota registrada\. Verificá contra el expediente antes de usarlo\./)).toBeInTheDocument()
  })

  it('consentimiento revocado → botón deshabilitado, sin invocar', async () => {
    consent = { data: [{ codigo: 'asistente_ia', concedido: false }], error: null }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await screen.findByText(/revocó el uso de IA/)
    expect(boton()).toBeDisabled()
    fireEvent.click(boton())
    expect(invocaciones).toHaveLength(0)
  })

  it('consentimiento no verificable → botón deshabilitado y Reintentar', async () => {
    consent = { data: null, error: { message: 'boom' } }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await screen.findByText(/No se pudo verificar el consentimiento de IA/)
    expect(boton()).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
  })

  it('sin_visita → mensaje y body con modo resumen_visita', async () => {
    invoke = { data: { sin_visita: true }, error: null }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    fireEvent.click(boton())
    await screen.findByText('El paciente no tiene visitas completadas con nota registrada')
    expect(invocaciones).toEqual([{ fn: 'asistente-ia', body: { modo: 'resumen_visita', paciente_id: 23 } }])
  })

  it('éxito → encabezado, badge de corregida, listas no vacías y vacías ocultas; Volver a generar', async () => {
    invoke = {
      data: {
        sin_visita: false, cita_id: 970, fecha: '2026-06-24', hora_inicio: '10:00:00',
        medico_nombre: 'Dr. Médico QA', corregida: true,
        resumen: {
          resumen: 'Consulta por motivo xxxx; la nota fue corregida.',
          hallazgos_clave: ['Alergia a penicilina'],
          signos_vitales_relevantes: [],
          pendientes_seguimiento: ['cambio a prueba 2'],
          datos_faltantes: [],
        },
      },
      error: null,
    }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    fireEvent.click(boton())
    await screen.findByText('Consulta por motivo xxxx; la nota fue corregida.')
    expect(screen.getByText(/24 de junio de 2026 · 10:00/)).toBeInTheDocument()
    expect(screen.getByText('Dr. Médico QA')).toBeInTheDocument()
    expect(screen.getByText('Nota corregida')).toBeInTheDocument()
    expect(screen.getByText('Hallazgos clave')).toBeInTheDocument()
    expect(screen.getByText('Alergia a penicilina')).toBeInTheDocument()
    expect(screen.getByText('Pendientes de seguimiento')).toBeInTheDocument()
    expect(screen.queryByText('Signos vitales relevantes')).not.toBeInTheDocument()
    expect(screen.queryByText('Datos faltantes en la nota')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /volver a generar/i })).toBeEnabled()
    expect(invocaciones).toHaveLength(1)   // sin reintento automático
  })

  it('sin corrección → no hay badge', async () => {
    invoke = { data: { sin_visita: false, cita_id: 1, fecha: '2026-06-24', hora_inicio: null, medico_nombre: null, corregida: false,
      resumen: { resumen: 'ok', hallazgos_clave: [], signos_vitales_relevantes: [], pendientes_seguimiento: [], datos_faltantes: [] } }, error: null }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    fireEvent.click(boton())
    await screen.findByText('ok')
    expect(screen.queryByText('Nota corregida')).not.toBeInTheDocument()
  })

  it('error del edge → motivo legible, no "non-2xx", y el botón vuelve a habilitarse', async () => {
    invoke = { data: null, error: httpError(403, { error: 'no_pertenencia' }) }
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    fireEvent.click(boton())
    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('No tenés acceso a este paciente para usar el asistente de IA.')
    expect(alerta).not.toHaveTextContent(/non-2xx/)
    await waitFor(() => expect(boton()).toBeEnabled())
    expect(invocaciones).toHaveLength(1)
  })

  it('mientras carga el botón queda deshabilitado (no se duplica el gasto)', async () => {
    let soltar!: (v: unknown) => void
    invoke = new Promise(r => { soltar = r }) as unknown as typeof invoke
    render(<ResumenUltimaVisita pacienteId={23} />)
    await waitFor(() => expect(boton()).toBeEnabled())
    fireEvent.click(boton())
    await waitFor(() => expect(boton()).toBeDisabled())
    fireEvent.click(boton())
    expect(invocaciones).toHaveLength(1)
    soltar({ data: { sin_visita: true }, error: null })
    await screen.findByText('El paciente no tiene visitas completadas con nota registrada')
  })
})
