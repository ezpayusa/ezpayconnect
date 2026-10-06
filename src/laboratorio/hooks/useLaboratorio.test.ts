import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'

// Mig 369: el catálogo de exámenes se escribe SOLO por las 3 RPCs (crear/actualizar/eliminar_examen_catalogo); authenticated
// ya no tiene INSERT/UPDATE/DELETE en examenes_catalogo. Este test falla si el hook vuelve a escribir la tabla directo.
const rpcs: Array<{ fn: string; args: unknown }> = []
const tablas: string[] = []   // "<tabla>.<metodo>" de cada llamada encadenada sobre supabase.from(...)
let respuestaRpc: { data: unknown; error: unknown } = { data: 'id-ok', error: null }

// builder encadenable: registra cada metodo y, al hacer await, resuelve { data: [], error: null }
const builder = (tabla: string): unknown => {
  const p: unknown = new Proxy(() => {}, {
    get: (_t, prop) => {
      if (prop === 'then') return (res: (v: unknown) => void) => res({ data: [], error: null })
      return () => { tablas.push(`${tabla}.${String(prop)}`); return p }
    },
  })
  return p
}

vi.mock('@/lib/supabase', () => {
  const canal = { on: () => canal, subscribe: () => canal }
  return {
    supabase: {
      from: (tabla: string) => { tablas.push(`${tabla}.from`); return builder(tabla) },
      rpc: async (fn: string, args: unknown) => { rpcs.push({ fn, args }); return respuestaRpc },
      channel: () => canal,
      removeChannel: () => {},
      storage: { from: () => builder('storage') },
    },
  }
})
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({ useProveedorAuth: () => ({ empresa: { id: 'lab-1' } }) }))
vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))

const { useLaboratorio } = await import('./useLaboratorio')

const escriturasDirectasCatalogo = () =>
  tablas.filter(t => /^examenes_catalogo\.(insert|update|upsert|delete)$/.test(t))

let errorSpy: ReturnType<typeof vi.spyOn>
let confirmSpy: ReturnType<typeof vi.spyOn>
beforeEach(() => {
  rpcs.length = 0; tablas.length = 0; respuestaRpc = { data: 'id-ok', error: null }
  errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true)
})
afterEach(() => { errorSpy.mockRestore(); confirmSpy.mockRestore() })

const montar = async () => {
  const { result } = renderHook(() => useLaboratorio())
  await act(async () => {})
  rpcs.length = 0; tablas.length = 0   // descarta las lecturas del montaje
  return result
}

describe('useLaboratorio: el catálogo se escribe solo por RPC (mig 369)', () => {
  it('crearCatalogo llama a crear_examen_catalogo con nombre y categoría recortados', async () => {
    const result = await montar()
    let ok: boolean | undefined
    await act(async () => { ok = await result.current.crearCatalogo('  Hemograma  ', '  Sangre ') })
    expect(ok).toBe(true)
    expect(rpcs).toEqual([{ fn: 'crear_examen_catalogo', args: { p_nombre: 'Hemograma', p_categoria: 'Sangre' } }])
    expect(escriturasDirectasCatalogo()).toEqual([])
  })

  it('crearCatalogo sin categoría manda p_categoria null', async () => {
    const result = await montar()
    await act(async () => { await result.current.crearCatalogo('Orina') })
    expect(rpcs).toEqual([{ fn: 'crear_examen_catalogo', args: { p_nombre: 'Orina', p_categoria: null } }])
    expect(escriturasDirectasCatalogo()).toEqual([])
  })

  it('toggleCatalogo llama a actualizar_examen_catalogo con p_categoria null y el activo pedido', async () => {
    const result = await montar()
    await act(async () => { await result.current.toggleCatalogo('cat-1', false) })
    expect(rpcs).toEqual([{ fn: 'actualizar_examen_catalogo', args: { p_id: 'cat-1', p_categoria: null, p_activo: false } }])
    expect(escriturasDirectasCatalogo()).toEqual([])
  })

  it('eliminarCatalogo llama a eliminar_examen_catalogo con el id', async () => {
    const result = await montar()
    await act(async () => { await result.current.eliminarCatalogo('cat-2') })
    expect(rpcs).toEqual([{ fn: 'eliminar_examen_catalogo', args: { p_id: 'cat-2' } }])
    expect(escriturasDirectasCatalogo()).toEqual([])
  })

  it('una RPC sin id devuelto es un error: crearCatalogo devuelve false y no hay escritura directa de respaldo', async () => {
    respuestaRpc = { data: null, error: null }
    const result = await montar()
    let ok: boolean | undefined
    await act(async () => { ok = await result.current.crearCatalogo('Glucosa') })
    expect(ok).toBe(false)
    expect(rpcs.map(r => r.fn)).toEqual(['crear_examen_catalogo'])
    expect(escriturasDirectasCatalogo()).toEqual([])
  })
})
