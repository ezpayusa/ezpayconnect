import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'

// Mig 365: el UPDATE de una nota que la RLS filtra afecta 0 filas sin error. El hook pide las filas con .select('id')
// y, si vuelven 0, devuelve un error con mensaje fijo: la pantalla no marca "guardado" porque result.error viene lleno.
let respuestaUpdate: { data: unknown; error: unknown } = { data: [], error: null }
const llamadas: string[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getUser: async () => ({ data: { user: { id: 'medico-1' } } }) },
    from: (tabla: string) => ({
      update: () => ({
        eq: () => ({
          select: async (cols: string) => { llamadas.push(`${tabla}.update.eq.select(${cols})`); return respuestaUpdate },
        }),
      }),
    }),
  },
}))

const { useConsultas, mensajeErrorNota, CODIGO_NOTA_SIN_FILAS, MENSAJE_NOTA_SIN_FILAS } = await import('./useConsultas')

let errorSpy: ReturnType<typeof vi.spyOn>
beforeEach(() => { llamadas.length = 0; errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {}) })
afterEach(() => { errorSpy.mockRestore() })

const guardar = async () => {
  const { result } = renderHook(() => useConsultas())
  let r: { error: string | null; errorCode?: string | null; data?: unknown } = { error: null }
  await act(async () => { r = await result.current.crearOActualizarConsulta({ paciente_id: 23, subjetivo: 'x' }, 2213) })
  return r
}

describe('useConsultas.crearOActualizarConsulta (UPDATE de la nota)', () => {
  it('0 filas afectadas: devuelve el error fijo, no un guardado', async () => {
    respuestaUpdate = { data: [], error: null }
    const r = await guardar()
    expect(llamadas).toEqual(["expediente_notas.update.eq.select(id)"])
    expect(r.error).toBe(MENSAJE_NOTA_SIN_FILAS)
    expect(r.errorCode).toBe(CODIGO_NOTA_SIN_FILAS)
    expect(r.data).toBeUndefined()
    // la pantalla lo muestra tal cual (sin el prefijo 'Error al guardar: ')
    expect(mensajeErrorNota({ code: r.errorCode, message: r.error! }, 'Error al guardar: ')).toBe(MENSAJE_NOTA_SIN_FILAS)
    expect(errorSpy).toHaveBeenCalledWith('Guardar nota: el UPDATE no afectó filas:', CODIGO_NOTA_SIN_FILAS)
  })

  it('data null tambien es 0 filas', async () => {
    respuestaUpdate = { data: null, error: null }
    const r = await guardar()
    expect(r.error).toBe(MENSAJE_NOTA_SIN_FILAS)
    expect(r.errorCode).toBe(CODIGO_NOTA_SIN_FILAS)
  })

  it('1 fila afectada: sin error', async () => {
    respuestaUpdate = { data: [{ id: 2213 }], error: null }
    const r = await guardar()
    expect(r.error).toBeNull()
    expect(r.errorCode).toBeNull()
  })

  it('error de PostgREST: el mismo manejo de siempre (mensaje y codigo del error)', async () => {
    respuestaUpdate = { data: null, error: { code: 'NT006', message: 'La nota está cerrada: solo se puede corregir con motivo' } }
    const r = await guardar()
    expect(r.error).toBe('La nota está cerrada: solo se puede corregir con motivo')
    expect(r.errorCode).toBe('NT006')
  })
})
