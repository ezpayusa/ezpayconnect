import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// obtenerBlob decide qué ve el usuario cuando un archivo no carga. Las respuestas de storage que se
// simulan acá son las MEDIDAS el 15-sep contra el proyecto real:
//   - firma de un objeto inexistente o sin permiso → error de createSignedUrl (NoSuchKey, indistinguibles)
//   - token vencido/roto → HTTP 400 {"error":"InvalidJWT"}, con CORS, así que el fetch lo puede leer
//   - objeto borrado entre firmar y bajar → HTTP 400 {"statusCode":"404","error":"not_found"}

let firmas: { path: string; ttl: number }[] = []
let firmaFalla = false

vi.mock('@/lib/supabase', () => ({
  supabase: {
    storage: {
      from: () => ({
        createSignedUrl: async (path: string, ttl: number) => {
          firmas.push({ path, ttl })
          return firmaFalla
            ? { data: null, error: { message: 'Object not found' } }
            : { data: { signedUrl: `https://storage.example/${path}?token=T${firmas.length}` }, error: null }
        },
      }),
    },
  },
}))

const { obtenerBlob, TTL_VISOR_S } = await import('./signedUrl')

const respuesta = (status: number, cuerpo: string | Blob) =>
  new Response(cuerpo, { status, headers: { 'Content-Type': typeof cuerpo === 'string' ? 'application/json' : 'image/png' } })

let fetchMock: ReturnType<typeof vi.fn>

beforeEach(() => {
  firmas = []
  firmaFalla = false
  fetchMock = vi.fn()
  vi.stubGlobal('fetch', fetchMock)
})
afterEach(() => vi.unstubAllGlobals())

describe('obtenerBlob', () => {
  it('firma con TTL de 60 s y devuelve el blob', async () => {
    fetchMock.mockResolvedValueOnce(respuesta(200, new Blob(['png'], { type: 'image/png' })))
    const r = await obtenerBlob('resultados-examenes', 'lab/1-1.png')
    expect(r.ok).toBe(true)
    expect(TTL_VISOR_S).toBe(60)
    expect(firmas).toEqual([{ path: 'lab/1-1.png', ttl: 60 }])
  })

  it('si la firma no se emite, es "sin_acceso" y NO intenta bajar nada', async () => {
    firmaFalla = true
    const r = await obtenerBlob('resultados-examenes', 'lab/x.pdf')
    expect(r).toMatchObject({ ok: false, motivo: 'sin_acceso' })
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('firma vencida (400 InvalidJWT): vuelve a firmar UNA vez y baja', async () => {
    fetchMock
      .mockResolvedValueOnce(respuesta(400, '{"statusCode":"400","error":"InvalidJWT","message":"jwt expired"}'))
      .mockResolvedValueOnce(respuesta(200, new Blob(['pdf'], { type: 'application/pdf' })))
    const r = await obtenerBlob('resultados-examenes', 'lab/1-1.pdf')
    expect(r.ok).toBe(true)
    expect(firmas).toHaveLength(2)
  })

  it('si la firma vence dos veces seguidas, no entra en un loop: falla', async () => {
    fetchMock.mockResolvedValue(respuesta(400, '{"error":"InvalidJWT"}'))
    const r = await obtenerBlob('resultados-examenes', 'lab/1-1.pdf')
    expect(r).toMatchObject({ ok: false, motivo: 'desconocido' })
    expect(firmas).toHaveLength(2)
  })

  it('un corte de red es "red", no "sin_acceso"', async () => {
    fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    const r = await obtenerBlob('resultados-examenes', 'lab/1-1.pdf')
    expect(r).toMatchObject({ ok: false, motivo: 'red' })
  })

  it('objeto borrado entre firmar y bajar es "no_existe"', async () => {
    fetchMock.mockResolvedValueOnce(respuesta(400, '{"statusCode":"404","error":"not_found","message":"Object not found"}'))
    const r = await obtenerBlob('resultados-examenes', 'lab/1-1.pdf')
    expect(r).toMatchObject({ ok: false, motivo: 'no_existe' })
  })

  it('una fila vieja con URL pública completa se firma por su PATH, no por la URL', async () => {
    fetchMock.mockResolvedValueOnce(respuesta(200, new Blob(['x'])))
    await obtenerBlob('resultados-examenes', 'https://p.supabase.co/storage/v1/object/public/resultados-examenes/lab/9-9.jpg')
    expect(firmas[0].path).toBe('lab/9-9.jpg')
  })
})
