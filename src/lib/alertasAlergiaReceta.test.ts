import { describe, it, expect, vi, beforeEach } from 'vitest'

let respuesta: { data: unknown; error: unknown } = { data: [], error: null }
vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: () => ({ select: () => ({ eq: async () => respuesta }) }),
  },
}))

const { cargarAlertasAlergia, armarAlertasAlergia, textoAlertaAlergia } = await import('./alertasAlergiaReceta')

const items = [{ id: 12345, nombre_medicamento: 'Penicilina G benzatínica' }]

beforeEach(() => { respuesta = { data: [], error: null } })

describe('alertas de alergia de la receta (H23)', () => {
  it('médico autor: la alerta llega con el medicamento, el término y el motivo', async () => {
    respuesta = { data: [{ receta_item_id: 12345, termino_alergia: 'penicilina', motivo: 'Sin alternativa, se vigila 30 min' }], error: null }
    const a = await cargarAlertasAlergia(8927, items)
    expect(a).toEqual([{ medicamento: 'Penicilina G benzatínica', termino: 'penicilina', motivo: 'Sin alternativa, se vigila 30 min' }])
    expect(textoAlertaAlergia(a[0])).toBe('Penicilina G benzatínica: coincide con la alergia «penicilina». Motivo: Sin alternativa, se vigila 30 min')
  })

  it('paciente u otro rol (RLS: 0 filas) → nada que mostrar', async () => {
    expect(await cargarAlertasAlergia(8927, items)).toEqual([])
  })

  it('error de lectura → nada que mostrar, sin tirar', async () => {
    respuesta = { data: null, error: { code: '42501', message: 'permission denied' } }
    expect(await cargarAlertasAlergia(8927, items)).toEqual([])
  })

  it('sin ítem asociado: el texto no inventa un medicamento', () => {
    const [a] = armarAlertasAlergia([{ receta_item_id: null, termino_alergia: 'sulfas', motivo: null }], items)
    expect(textoAlertaAlergia(a)).toBe('Coincide con la alergia «sulfas».')
  })
})
