import { describe, it, expect, vi, beforeEach } from 'vitest'

// Fija las dos reglas de H5/H6: 0 filas NO es éxito (mig 391: la RLS filtra sin error) y el aviso al
// paciente sale solo después de un cambio real, para los estados que avisan.
const llamadas: string[] = []
let updateResp: { data: unknown; error: unknown } = { data: [{ id: 7 }], error: null }

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: (tabla: string) => ({
      update: (vals: Record<string, unknown>) => ({
        eq: (_col: string, id: number) => ({
          select: async (cols: string) => {
            llamadas.push(`update:${tabla}:${id}:${String(vals.estado)}:select(${cols})`)
            return updateResp
          },
        }),
      }),
    }),
    rpc: async (nombre: string, args: Record<string, unknown>) => {
      llamadas.push(`rpc:${nombre}:${String(args.p_cita_id)}:${String(args.p_evento)}`)
      return { data: null, error: null }
    },
  },
}))

const { cambiarEstadoCita, etiquetaEstadoCita, MENSAJE_SIN_FILAS } = await import('./estadoCita')

beforeEach(() => {
  llamadas.length = 0
  updateResp = { data: [{ id: 7 }], error: null }
})

describe('cambiarEstadoCita', () => {
  it('cambio real: UPDATE con select(id) y aviso al paciente', async () => {
    const r = await cambiarEstadoCita(7, 'en_curso')
    expect(r).toEqual({ ok: true, codigo: null, mensaje: null })
    expect(llamadas).toEqual([
      'update:citas:7:en_curso:select(id)',
      'rpc:notificar_cita_paciente:7:en_curso',
    ])
  })

  it('0 filas (RLS de la 391 filtra sin error) es un error SIN_FILAS y no avisa', async () => {
    updateResp = { data: [], error: null }
    const r = await cambiarEstadoCita(7, 'completada')
    expect(r).toEqual({ ok: false, codigo: 'SIN_FILAS', mensaje: MENSAJE_SIN_FILAS })
    expect(llamadas.some(c => c.startsWith('rpc:'))).toBe(false)
  })

  it('error de la base: se propaga el mensaje y no avisa', async () => {
    updateResp = { data: null, error: { code: 'PE001', message: 'Debe guardar la nota' } }
    const r = await cambiarEstadoCita(7, 'completada')
    expect(r).toEqual({ ok: false, codigo: 'ERROR', mensaje: 'Debe guardar la nota' })
    expect(llamadas.some(c => c.startsWith('rpc:'))).toBe(false)
  })

  it('un estado sin aviso (no_show) no llama a la RPC', async () => {
    const r = await cambiarEstadoCita(7, 'no_show')
    expect(r).toEqual({ ok: true, codigo: null, mensaje: null })
    expect(llamadas).toEqual(['update:citas:7:no_show:select(id)'])
  })
})

describe('etiquetaEstadoCita', () => {
  it('usa las etiquetas de la agenda, no el texto crudo', () => {
    expect(etiquetaEstadoCita('en_curso')).toBe('En curso')
    expect(etiquetaEstadoCita('no_show')).toBe('No asistió')
    expect(etiquetaEstadoCita('en_espera')).toBe('En espera')
  })
})

describe('puedeAtender (H1)', () => {
  it('confirmada y en_espera abren la consulta; el resto no', async () => {
    const { puedeAtender } = await import('./estadoCita')
    expect(puedeAtender('confirmada')).toBe(true)
    expect(puedeAtender('en_espera')).toBe(true)
    for (const e of ['solicitada', 'agendada', 'en_curso', 'completada', 'cancelada', 'no_show']) {
      expect(puedeAtender(e)).toBe(false)
    }
  })
})
