import { describe, it, expect, vi, beforeEach } from 'vitest'

// Las respuestas simuladas copian el cuerpo VIVO de liberar_examen_al_paciente (medido 15-sep):
//   - éxito            → { examen, liberado: true }
//   - ya estaba        → { examen, ya_liberado: true }   (SIN excepción: no es un error)
//   - inexistente / sin autoridad / no completado → excepción con SQLSTATE PT002 (los tres iguales)

type Resp = { data: unknown; error: unknown }
let respuestas: Record<number, Resp> = {}
const llamadas: { fn: string; args: Record<string, unknown> }[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      llamadas.push({ fn, args })
      return respuestas[args.p_examen_id as number] ?? { data: { liberado: true }, error: null }
    },
  },
}))

const { liberarUnExamen, liberarExamenes, MENSAJE_PT002_LIBERAR } = await import('./liberacionExamenes')

const PT002 = { code: 'PT002', message: 'No autorizado para liberar este examen' }

beforeEach(() => { respuestas = {}; llamadas.length = 0 })

describe('liberarUnExamen', () => {
  it('llama a liberar_examen_al_paciente con el id, y devuelve liberado', async () => {
    expect(await liberarUnExamen(254)).toEqual({ estado: 'liberado' })
    expect(llamadas).toEqual([{ fn: 'liberar_examen_al_paciente', args: { p_examen_id: 254 } }])
  })

  it('"ya liberado" NO es un error: es data, y se distingue', async () => {
    respuestas[250] = { data: { examen: 250, ya_liberado: true }, error: null }
    expect(await liberarUnExamen(250)).toEqual({ estado: 'ya_liberado' })
  })

  it('PT002 se traduce POR CÓDIGO al texto de liberación (no se lee el mensaje de la base)', async () => {
    // Mensaje de la base con un texto cualquiera: si la traducción mirara .message, esto no daría.
    respuestas[9] = { data: null, error: { code: 'PT002', message: 'texto reformulado que nadie esperaba' } }
    expect(await liberarUnExamen(9)).toEqual({ estado: 'error', mensaje: MENSAJE_PT002_LIBERAR })
  })

  it('un código que no es PT002 usa el mapa global (42501)', async () => {
    respuestas[9] = { data: null, error: { code: '42501', message: 'no_autorizado' } }
    expect(await liberarUnExamen(9)).toEqual({ estado: 'error', mensaje: 'No tenés permiso para esta acción.' })
  })

  it('sin código (red) nunca deja el mensaje vacío', async () => {
    respuestas[9] = { data: null, error: new TypeError('Failed to fetch') }
    const r = await liberarUnExamen(9)
    expect(r.estado).toBe('error')
    expect((r as { mensaje: string }).mensaje.trim()).not.toBe('')
  })
})

describe('liberarExamenes (los N listos)', () => {
  const A = { id: 1, tipo: 'Hemograma' }
  const B = { id: 2, tipo: 'Orina' }
  const C = { id: 3, tipo: 'Glucosa' }

  it('libera EXACTAMENTE la lista confirmada, por id, y nunca por orden', async () => {
    await liberarExamenes([A, B, C])
    expect(llamadas.map((l) => l.fn)).toEqual(Array(3).fill('liberar_examen_al_paciente'))
    expect(llamadas.map((l) => l.args.p_examen_id)).toEqual([1, 2, 3])
  })

  it('no corta al primer error: sigue con el resto y dice cuál falló', async () => {
    respuestas[2] = { data: null, error: PT002 }
    const r = await liberarExamenes([A, B, C])
    expect(llamadas).toHaveLength(3)
    expect(r.liberados.map((e) => e.id)).toEqual([1, 3])
    expect(r.fallidos).toEqual([{ examen: B, mensaje: MENSAJE_PT002_LIBERAR }])
  })

  it('separa los que ya estaban liberados de los que se liberaron ahora', async () => {
    respuestas[1] = { data: { ya_liberado: true }, error: null }
    const r = await liberarExamenes([A, B])
    expect(r.yaLiberados).toEqual([A])
    expect(r.liberados).toEqual([B])
  })
})

describe('estructura: ninguna pantalla libera por orden ni llama a la RPC directo', () => {
  it('PacienteDetallePage pasa por src/lib/liberacionExamenes y no llama liberar_orden_al_paciente', async () => {
    const fs = await import('node:fs')
    const codigo = fs.readFileSync('src/pages/PacienteDetallePage.tsx', 'utf8')
      .split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n')
    expect(codigo).not.toMatch(/rpc\(\s*['"]liberar_orden_al_paciente/)
    expect(codigo).not.toMatch(/rpc\(\s*['"]liberar_examen_al_paciente/)
    // CONTROL POSITIVO: sin esto, borrar los botones también pasaría las dos de arriba.
    expect(codigo).toMatch(/liberarUnExamen\(/)
    expect(codigo).toMatch(/liberarExamenes\(/)
    expect(codigo).toMatch(/<ConfirmarLiberacionDialog/)
  })
})
