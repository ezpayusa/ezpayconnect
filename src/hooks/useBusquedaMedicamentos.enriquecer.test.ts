import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// enriquecerConLaboratorio: "En proveedores" del medico (mig 354), best-effort sobre nombre_empresa_por_productos.
const llamadas: { nombre: string; args: Record<string, unknown> }[] = []
let respuesta: { data: unknown; error: unknown } = { data: [], error: null }

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: Record<string, unknown>) => { llamadas.push({ nombre, args }); return respuesta },
  },
}))
vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))

const { enriquecerConLaboratorio } = await import('./useBusquedaMedicamentos')

const prod = (id: string, empresa_id: string | null) => ({ id, empresa_id, empresa: null }) as any

let errorSpy: ReturnType<typeof vi.spyOn>
beforeEach(() => { llamadas.length = 0; respuesta = { data: [], error: null }; errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {}) })
afterEach(() => { errorSpy.mockRestore() })

describe('enriquecerConLaboratorio', () => {
  it('sin empresas no llama a la RPC', async () => {
    const filas = [prod('1', null)]
    expect(await enriquecerConLaboratorio(filas)).toBe(filas)
    expect(llamadas).toHaveLength(0)
  })
  it('con error de la RPC devuelve las filas sin nombre, sin throw, y registra el codigo', async () => {
    respuesta = { data: null, error: { code: '42501', message: 'permission denied' } }
    const filas = [prod('1', 'e1'), prod('2', 'e2')]
    const r = await enriquecerConLaboratorio(filas)
    expect(r).toBe(filas)
    expect(r.every((p: any) => p.empresa === null)).toBe(true)
    expect(errorSpy).toHaveBeenCalledWith('nombre_empresa_por_productos:', '42501', 'permission denied')
  })
  it('con respuesta completa el nombre del laboratorio', async () => {
    respuesta = { data: [{ empresa_id: 'e1', nombre_empresa: 'Lab Uno' }], error: null }
    const r = await enriquecerConLaboratorio([prod('1', 'e1'), prod('2', 'e2')])
    expect(llamadas).toEqual([{ nombre: 'nombre_empresa_por_productos', args: { p_empresa_ids: ['e1', 'e2'] } }])
    expect(r.map((p: any) => p.empresa?.nombre_empresa ?? null)).toEqual(['Lab Uno', null])
  })
})
