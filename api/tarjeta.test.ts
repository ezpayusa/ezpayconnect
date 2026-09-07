// Test del proxy de la tarjeta pública. Lo que se mide es lo ÚNICO que este archivo hace:
// transportar sin romper y corregir headers. No hay lógica de negocio que probar acá — vive en la
// edge — así que cada test de abajo es sobre el transporte.
//
// EL IMPORTANTE es el de bytes. La foto de la tarjeta (mig 289) viaja por este proxy, y un
// `await r.text()` la entrega corrupta SIN FALLAR: decodifica como UTF-8, cambia cada secuencia
// inválida por U+FFFD y devuelve un archivo distinto del original. Comparar LONGITUDES no lo
// detecta —U+FFFD ocupa 3 bytes al re-serializar y el largo puede hasta coincidir por casualidad—,
// así que se comparan los bytes uno por uno.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import handler from './tarjeta'

// Bytes que NO son UTF-8 válido: cabecera PNG (0x89 P N G), un JPEG (0xFF 0xD8 0xFF 0xE0) y varios
// bytes altos sueltos. Un decode/encode los destruye; es exactamente el contenido de una foto real.
const FOTO = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
  0xc3, 0x28, 0xa0, 0xa1, 0xf8, 0x88, 0x80, 0x9f,
  0x00, 0x01, 0x02, 0xfe, 0xfd, 0xfc, 0x7f, 0x80,
])

type Enviado = { status: number; headers: Record<string, string>; body: unknown }

function dobles(query: Record<string, string> = {}, metodo = 'GET') {
  const enviado: Enviado = { status: 0, headers: {}, body: undefined }
  const req = {
    method: metodo,
    query,
    headers: { host: 'med.ezpayconnect.com', 'x-forwarded-proto': 'https' },
  }
  const res = {
    setHeader(k: string, v: string) { enviado.headers[k.toLowerCase()] = v },
    status(c: number) { enviado.status = c; return res },
    send(b: unknown) { enviado.body = b; return res },
  }
  // Los tipos de @vercel/node piden bastante más superficie de la que el handler toca.
  return { req: req as never, res: res as never, enviado }
}

/** Respuesta REAL de fetch: así el arrayBuffer() del proxy se ejercita de verdad y no se simula. */
function respuestaEdge(body: BodyInit, tipoReal: string, status = 200, extra: HeadersInit = {}) {
  return new Response(body, {
    status,
    headers: {
      // El gateway de Supabase reescribe esto a text/plain; se reproduce el escenario real.
      'content-type': 'text/plain',
      'x-tarjeta-content-type': tipoReal,
      'cache-control': 'no-store, no-cache, must-revalidate',
      'x-robots-tag': 'noindex, nofollow',
      'x-content-type-options': 'nosniff',
      // Y el CSP que Supabase agrega y que NO se debe propagar: es el que rompe el render.
      'content-security-policy': "default-src 'none'; sandbox",
      ...(extra as Record<string, string>),
    },
  })
}

beforeEach(() => {
  vi.stubEnv('SUPABASE_URL', 'https://proyecto.supabase.co')
})
afterEach(() => {
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
})

describe('el proxy transporta bytes sin tocarlos', () => {
  it('una imagen llega BYTE A BYTE igual que salió de la edge', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => respuestaEdge(FOTO, 'image/png')))

    const { req, res, enviado } = dobles({ token: 'abc', formato: 'foto' })
    await handler(req, res)

    expect(enviado.status).toBe(200)
    expect(Buffer.isBuffer(enviado.body)).toBe(true)
    const salida = new Uint8Array(enviado.body as Buffer)

    // byte a byte, no longitud
    expect(Array.from(salida)).toEqual(Array.from(FOTO))
  })

  it('el camino viejo (text()) SÍ la habría corrompido — por eso el test es de bytes', () => {
    // Esta es la contraprueba del test de arriba: sin ella, "los bytes coinciden" no distingue
    // entre un proxy correcto y un test que no ejercita nada.
    const comoTexto = Buffer.from(new TextDecoder().decode(FOTO), 'utf8')
    expect(Array.from(new Uint8Array(comoTexto))).not.toEqual(Array.from(FOTO))
  })

  it('el HTML también viaja como bytes y no se altera', async () => {
    // Con acentos y símbolos: si alguien "arreglara" esto volviendo a text() sin charset, se vería.
    const html = '<!doctype html><p>Ana Pérez — Zona 1 · ñandú</p>'
    vi.stubGlobal('fetch', vi.fn(async () => respuestaEdge(html, 'text/html; charset=utf-8')))

    const { req, res, enviado } = dobles({ token: 'abc' })
    await handler(req, res)

    expect((enviado.body as Buffer).toString('utf8')).toBe(html)
    expect(enviado.headers['content-type']).toBe('text/html; charset=utf-8')
  })
})

describe('el proxy corrige headers y no filtra los de Supabase', () => {
  it('el Content-Type lo dice la edge, no el gateway ni el propio proxy', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => respuestaEdge(FOTO, 'image/webp')))

    const { req, res, enviado } = dobles({ token: 'abc', formato: 'foto' })
    await handler(req, res)

    // el upstream decía text/plain; lo que vale es el header propio
    expect(enviado.headers['content-type']).toBe('image/webp')
  })

  it('el CSP sandbox de Supabase NO se propaga, y los headers propios sí', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => respuestaEdge('<p>hola</p>', 'text/html; charset=utf-8')))

    const { req, res, enviado } = dobles({ token: 'abc' })
    await handler(req, res)

    expect(enviado.headers['content-security-policy']).toBeUndefined()
    expect(enviado.headers['cache-control']).toContain('no-store')
    expect(enviado.headers['x-robots-tag']).toContain('noindex')
    expect(enviado.headers['x-content-type-options']).toBe('nosniff')
  })

  it('el 404 de la edge llega como 404, no como 200 con una página de error', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => respuestaEdge('<p>no disponible</p>', 'text/html; charset=utf-8', 404)))

    const { req, res, enviado } = dobles({ token: 'apagado' })
    await handler(req, res)

    expect(enviado.status).toBe(404)
  })
})

describe('el proxy le manda a la edge lo que el gateway le esconde', () => {
  it('host y path públicos van explícitos, y el path se reconstruye desde el token', async () => {
    const espia = vi.fn(async () => respuestaEdge('<p>ok</p>', 'text/html; charset=utf-8'))
    vi.stubGlobal('fetch', espia)

    const { req, res } = dobles({ token: 'ab/c d', formato: 'foto' })
    await handler(req, res)

    const [url, init] = espia.mock.calls[0] as unknown as [string, RequestInit]
    const h = init.headers as Record<string, string>
    expect(h['x-tarjeta-host']).toBe('med.ezpayconnect.com')
    // el token va percent-encoded: para cuando corre el proxy, Vercel ya reescribió la URL a
    // /api/tarjeta?token=... y el /t/<token> original no existe en ningún lado
    expect(h['x-tarjeta-path']).toBe(`/t/${encodeURIComponent('ab/c d')}`)
    // y el formato se reenvía, que es lo que separa la foto de la tarjeta
    expect(url).toContain('formato=foto')
    expect(url).toContain('/functions/v1/tarjeta-asesor')
  })

  it('si la edge se cae, 502 y no el 404 de "tarjeta no disponible"', async () => {
    // Confundir una caída con una tarjeta apagada haría que una interrupción real pase inadvertida.
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('ECONNRESET') }))

    const { req, res, enviado } = dobles({ token: 'abc' })
    await handler(req, res)

    expect(enviado.status).toBe(502)
    expect(enviado.headers['content-type']).toBe('text/html; charset=utf-8')
  })
})
