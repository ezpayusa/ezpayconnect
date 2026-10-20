import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook } from '@testing-library/react'

const rpc = vi.fn()
vi.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }))

const { useEnrolamiento } = await import('./useEnrolamiento')
const api = () => renderHook(() => useEnrolamiento()).result.current
const pg = (code: string, message: string) => ({ data: null, error: { code, message, details: null, hint: null } })

beforeEach(() => rpc.mockReset())

describe('useEnrolamiento — RPCs y errores mapeados por código', () => {
  it('enrolarMedico llama enrolar_medico y devuelve el estado de la fila', async () => {
    rpc.mockResolvedValue({ data: [{ estado: 'enrolado', lab_enrolador_id: 'x', lab_enrolador_fecha: 'y' }], error: null })
    const r = await api().enrolarMedico('med-1')
    expect(rpc).toHaveBeenCalledWith('enrolar_medico', { p_medico_id: 'med-1' })
    expect(r).toEqual({ ok: true, data: 'enrolado' })
  })

  it('enrolarMedico con PV013 devuelve el mensaje del servidor', async () => {
    rpc.mockResolvedValue(pg('PV013', 'Este médico ya fue enrolado por otro laboratorio.'))
    const r = await api().enrolarMedico('med-1')
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.error.code).toBe('PV013')
      expect(r.error.mensaje).toBe('Este médico ya fue enrolado por otro laboratorio.')
    }
  })

  it('solicitarAlta manda los 7 parámetros normalizados y lee "creada"', async () => {
    rpc.mockResolvedValue({ data: { estado: 'creada', solicitud_id: 's-1' }, error: null })
    const r = await api().solicitarAlta({
      nombre: '  Dra. Ana ', email: ' ANA@Mail.com ', telefono: '', especialidad_id: '',
      numero_colegiado: ' 123 ', nombre_clinica: '', autorizado: true,
    })
    expect(rpc).toHaveBeenCalledWith('solicitar_alta_medico', {
      p_nombre: 'Dra. Ana', p_email: 'ana@mail.com', p_telefono: null, p_especialidad_id: null,
      p_numero_colegiado: '123', p_nombre_clinica: null, p_autorizado: true,
    })
    expect(r).toEqual({ ok: true, data: { estado: 'creada', solicitud_id: 's-1' } })
  })

  it('solicitarAlta lee "existe" con el medico_id', async () => {
    rpc.mockResolvedValue({ data: { estado: 'existe', medico_id: 'm-9' }, error: null })
    const r = await api().solicitarAlta({ nombre: 'Ana Pérez', email: 'a@b.co', telefono: '', especialidad_id: '',
      numero_colegiado: '', nombre_clinica: '', autorizado: true })
    expect(r).toEqual({ ok: true, data: { estado: 'existe', medico_id: 'm-9' } })
  })

  it('una respuesta con forma inesperada es un error genérico reportable', async () => {
    rpc.mockResolvedValue({ data: { estado: 'raro' }, error: null })
    const r = await api().solicitarAlta({ nombre: 'Ana Pérez', email: 'a@b.co', telefono: '', especialidad_id: '',
      numero_colegiado: '', nombre_clinica: '', autorizado: true })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.error.reportar).toBe(true)
  })

  it('cancelarSolicitud con PV022 pide recargar', async () => {
    rpc.mockResolvedValue(pg('PV022', 'La solicitud ya no está pendiente.'))
    const r = await api().cancelarSolicitud('s-1')
    expect(rpc).toHaveBeenCalledWith('cancelar_solicitud_alta', { p_solicitud_id: 's-1' })
    if (!r.ok) expect(r.error.recargar).toBe('solicitudes')
    else throw new Error('debió fallar')
  })

  it('listarSolicitudes solo expone las columnas que pinta la PWA', async () => {
    rpc.mockResolvedValue({ data: [{ id: 's1', nombre_completo: 'Ana', email: 'a@b.co', especialidad_nombre: null,
      estado: 'rechazada', motivo_rechazo: 'Datos incompletos', created_at: '2026-10-20T10:00:00Z',
      empresa_nombre: 'Otra', solicitante_nombre: 'X' }], error: null })
    const r = await api().listarSolicitudes()
    expect(rpc).toHaveBeenCalledWith('listar_solicitudes_alta', { p_estado: null })
    expect(r.ok && Object.keys(r.data[0]).sort()).toEqual(
      ['created_at', 'email', 'especialidad_nombre', 'estado', 'id', 'motivo_rechazo', 'nombre_completo'])
  })

  it('prioridadParaAgendar parsea el jsonb y PV026 sale mapeado', async () => {
    rpc.mockResolvedValueOnce({ data: { estado: 'otro_laboratorio', fecha_minima: '2026-10-25', visitas_completadas: null, visitas_limite: null }, error: null })
    const r = await api().prioridadParaAgendar('m-1')
    expect(rpc).toHaveBeenCalledWith('prioridad_para_agendar', { p_medico_id: 'm-1' })
    expect(r.ok && r.data?.fecha_minima).toBe('2026-10-25')
    rpc.mockResolvedValueOnce(pg('PV026', 'No puedes consultar a este médico.'))
    const r2 = await api().prioridadParaAgendar('m-2')
    expect(!r2.ok && r2.error.mensaje).toBe('No puedes consultar a este médico.')
  })
})
