import { describe, it, expect, vi, beforeEach } from 'vitest'

// supabase simulado: registra la cadena from().select().eq().limit().maybeSingle() y devuelve `respuesta`.
let respuesta: { data: unknown; error: unknown } = { data: null, error: null }
const llamadas: { tabla?: string; cols?: string; eq?: [string, unknown]; limit?: number } = {}
vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: (tabla: string) => {
      llamadas.tabla = tabla
      return {
        select: (cols: string) => {
          llamadas.cols = cols
          return {
            eq: (col: string, val: unknown) => {
              llamadas.eq = [col, val]
              return {
                limit: (n: number) => {
                  llamadas.limit = n
                  return { maybeSingle: async () => respuesta }
                },
              }
            },
          }
        },
      }
    },
  },
}))

const { esPacienteActual } = await import('../esPaciente')
let consoleError: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  respuesta = { data: null, error: null }
  for (const k of Object.keys(llamadas)) delete (llamadas as Record<string, unknown>)[k]
  consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('esPacienteActual', () => {
  it('con fila → true; consulta pacientes por auth_user_id = uid (no por email), limit 1', async () => {
    respuesta = { data: { id: 23 }, error: null }
    expect(await esPacienteActual('uid-pac')).toBe(true)
    expect(llamadas).toEqual({ tabla: 'pacientes', cols: 'id', eq: ['auth_user_id', 'uid-pac'], limit: 1 })
    expect(consoleError).not.toHaveBeenCalled()
  })

  it('sin fila → false, sin log', async () => {
    expect(await esPacienteActual('uid-x')).toBe(false)
    expect(consoleError).not.toHaveBeenCalled()
  })

  it('error → false; log con mensaje fijo y solo el code', async () => {
    respuesta = { data: null, error: { code: '42501', message: 'texto interno con ana@example.com' } }
    expect(await esPacienteActual('uid-x')).toBe(false)
    expect(consoleError).toHaveBeenCalledWith('[esPaciente] no se pudo verificar si la cuenta es de paciente', '42501')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('ana@example.com')
  })
})
