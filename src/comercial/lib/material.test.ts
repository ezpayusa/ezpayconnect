import { describe, it, expect, vi, beforeEach } from 'vitest'

// El orden rpc -> remove NO es un detalle de implementación: es el que impone la policy de la
// mig 279 (el DELETE de storage sólo alcanza objetos que ya no figuran en material_comercial).
// Si alguien lo invierte, el remove se rechaza y queda una fila apuntando a un archivo que quizá
// ya no está. Por eso se fija acá.
const llamadas: string[] = []
let rpcError: unknown = null
let removeError: unknown = null

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: Record<string, unknown>) => {
      llamadas.push(`rpc:${nombre}:${String(args.p_material_id)}`)
      return { data: null, error: rpcError }
    },
    storage: {
      from: (bucket: string) => ({
        remove: async (paths: string[]) => {
          llamadas.push(`remove:${bucket}:${paths.join(',')}`)
          return { data: null, error: removeError }
        },
      }),
    },
  },
}))

const { borrarMaterial } = await import('./material')

const M = { id: 'mat-1', storage_path: 'pais-gt/archivo.pdf' }

beforeEach(() => { llamadas.length = 0; rpcError = null; removeError = null })

describe('borrarMaterial — el orden y las dos formas de fallar', () => {
  it('camino feliz: primero el RPC, DESPUÉS el remove, y en ese orden', async () => {
    const r = await borrarMaterial(M)
    expect(r).toEqual({ fase: null, error: null })
    expect(llamadas).toEqual([
      'rpc:borrar_material_comercial:mat-1',
      'remove:material-comercial:pais-gt/archivo.pdf',
    ])
  })

  it('si el RPC falla NO se toca el storage: no pasó nada, la fila sigue', async () => {
    rpcError = { code: '42501', message: 'no_autorizado' }
    const r = await borrarMaterial(M)
    expect(r.fase).toBe('rpc')
    expect(r.error).toBe(rpcError)
    // lo que importa: NO hay una llamada a remove
    expect(llamadas).toEqual(['rpc:borrar_material_comercial:mat-1'])
    expect(llamadas.some(c => c.startsWith('remove:'))).toBe(false)
  })

  it('si falla el remove DESPUÉS de un RPC exitoso, la fase es "storage" y NO éxito', async () => {
    // Este es el caso que no se puede pintar como éxito: la fila ya no existe y el archivo quedó.
    removeError = { statusCode: '403', message: 'denied' }
    const r = await borrarMaterial(M)
    expect(r.fase).toBe('storage')
    expect(r.fase).not.toBe(null)          // explícito: no es el camino feliz
    expect(r.error).toBe(removeError)
    expect(llamadas).toEqual([
      'rpc:borrar_material_comercial:mat-1',
      'remove:material-comercial:pais-gt/archivo.pdf',
    ])
  })

  it('las tres fases son distinguibles entre sí: null / rpc / storage', async () => {
    const ok = await borrarMaterial(M)
    rpcError = { code: '42501' }
    const fallaRpc = await borrarMaterial(M)
    rpcError = null; removeError = { statusCode: '404' }
    const fallaStorage = await borrarMaterial(M)
    expect(new Set([ok.fase, fallaRpc.fase, fallaStorage.fase]).size).toBe(3)
  })
})

describe('el error del remove entra al mapa único de erroresRpc', () => {
  it('un StorageApiError se normaliza a STORAGE_<status> y no cae en el genérico mudo', async () => {
    const { mapearErrorRpc } = await import('@/lib/erroresRpc')
    removeError = { statusCode: '403', message: 'denied' }
    const r = await borrarMaterial(M)
    const m = mapearErrorRpc(r.error)
    expect(m.code).toBe('STORAGE_403')
    expect(m.mensaje.trim()).not.toBe('')
  })
})
