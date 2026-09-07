// Test REAL del borde de tarjeta-asesor. deno test --allow-net --allow-env --no-check test.ts
// Molde: enviar-push-notificacion/test.ts — se inyecta `Deps` y no se toca la red.
//
// Lo que se mide: (a) los cuatro motivos de no-respuesta se ven IGUAL; (b) el escape de todo lo que
// viene de la base; (c) los og: están en el HTML servido, que es la única razón de que esta ruta no
// sea React; (d) la vCard; (e) no-store, porque una tarjeta revocable no se cachea.
import { assertEquals, assertStringIncludes, assertNotMatch } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  handle, esc, escVcard, soloDigitos, esInternacional, tokenDe, tipoPorExtension,
  H_CONTENT_TYPE, H_HOST, H_PATH,
  type Deps, type Tarjeta,
} from './index.ts'

// DOS fixtures a propósito: el prefijo internacional NO viene garantizado desde la base.
// `asesores_perfil.celular` es text libre sin validación, así que un celular sin `+` es el caso
// normal y no la excepción. Un único fixture con `+502` haría creer lo contrario.
const T_INTL: Tarjeta = {
  nombre_completo: 'Ana Pérez',
  cargo: 'Ejecutiva de cuenta',
  territorio: 'Zona 1',
  telefono: '2222-0001',
  celular: '+502 5555-0001',
  foto_publica_path: null,
}
const T_LOCAL: Tarjeta = { ...T_INTL, celular: '5555-0001' }   // como lo escribe casi todo el mundo
const T_SIN_CEL: Tarjeta = { ...T_INTL, celular: null }
// Alias para los tests que no dependen del formato del celular.
const T = T_INTL
// Bytes que NO son UTF-8 válido (cabecera PNG + un JPEG + bytes altos sueltos): si algún día
// alguien hace pasar la foto por un string, esto se rompe.
const BYTES_FOTO = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0xff, 0xd8, 0xff, 0xe0, 0xc3, 0x28, 0xa0, 0xf8,
])
const T_CON_FOTO: Tarjeta = { ...T_INTL, foto_publica_path: 'aaaa-bbbb/1234.png' }

const deps = (
  data: Tarjeta | null,
  error: unknown = null,
  foto: { bytes: Uint8Array; tipo: string } | null = { bytes: BYTES_FOTO, tipo: 'image/png' },
): Deps => ({
  resolver: async () => ({ data, error }),
  descargarFoto: async () => foto,
})
const get = (u: string) => new Request(u, { method: 'GET' })
const URL_T = 'https://med.ezpayconnect.com/t/abc123'

// ---------------------------------------------------------------- los cuatro se ven igual
Deno.test('sin token, token inválido y error de RPC dan la MISMA respuesta', async () => {
  const sinToken = await handle(get('https://x/t/'), deps(T))
  const invalido = await handle(get(URL_T), deps(null))          // la RPC devolvió NULL
  const conError = await handle(get(URL_T), deps(null, { message: 'boom' }))

  for (const r of [sinToken, invalido, conError]) assertEquals(r.status, 404)
  const cuerpos = await Promise.all([sinToken.text(), invalido.text(), conError.text()])
  // byte a byte: si alguno difiriera, sería un oráculo que distingue por qué no responde
  assertEquals(cuerpos[0], cuerpos[1])
  assertEquals(cuerpos[1], cuerpos[2])
  assertStringIncludes(cuerpos[0], 'no está disponible')
  // y la página genérica no nombra el token ni el motivo
  assertNotMatch(cuerpos[0], /abc123|consentimiento|inactiv/i)
})

Deno.test('la página de no disponible no se cachea ni se indexa', async () => {
  const r = await handle(get(URL_T), deps(null))
  assertStringIncludes(r.headers.get('cache-control') ?? '', 'no-store')
  assertStringIncludes(r.headers.get('x-robots-tag') ?? '', 'noindex')
})

// ---------------------------------------------------------------- el HTML de la tarjeta
Deno.test('la tarjeta trae los og: EN EL HTML servido (el crawler no ejecuta JS)', async () => {
  const html = await (await handle(get(URL_T), deps(T))).text()
  assertStringIncludes(html, '<meta property="og:type" content="profile">')
  assertStringIncludes(html, 'og:title" content="Ana Pérez — Ejecutiva de cuenta"')
  assertStringIncludes(html, 'og:description" content="Territorio: Zona 1"')
  assertStringIncludes(html, 'og:url" content="https://med.ezpayconnect.com/t/abc123"')
  assertStringIncludes(html, '<title>Ana Pérez — Ejecutiva de cuenta</title>')
})

Deno.test('la tarjeta muestra los dos teléfonos y los botones', async () => {
  const html = await (await handle(get(URL_T), deps(T_INTL))).text()
  assertStringIncludes(html, 'tel:22220001')
  assertStringIncludes(html, 'tel:50255550001')
  assertStringIncludes(html, 'https://wa.me/50255550001')   // wa.me sólo dígitos
  assertStringIncludes(html, 'formato=vcard')
  assertStringIncludes(html, 'id="compartir" hidden')       // nace oculto: se muestra si hay share
})

// ---------------------------------------------------------------- el criterio del '+'
// wa.me exige el numero internacional completo. Sin `+` no hay forma de saber el pais —la RPC no
// devuelve pais_id, y adivinar por cantidad de digitos falla distinto en cada pais del modulo—,
// asi que el boton NO EXISTE en vez de generar un link que abre WhatsApp en la nada.
Deno.test('celular CON + : aparece el boton de WhatsApp y el numero sale completo', async () => {
  const html = await (await handle(get(URL_T), deps(T_INTL))).text()
  assertStringIncludes(html, 'https://wa.me/50255550001')
  assertStringIncludes(html, '>WhatsApp</a>')
  assertStringIncludes(html, 'tel:50255550001')            // y el de llamar tambien
})

Deno.test('celular SIN + : NO hay boton de WhatsApp, pero SI el de llamar', async () => {
  const html = await (await handle(get(URL_T), deps(T_LOCAL))).text()
  assertEquals(html.includes('wa.me'), false)              // ni el link
  assertEquals(html.includes('>WhatsApp</a>'), false)      // ni el boton
  assertStringIncludes(html, 'tel:55550001')               // llamar SI: marca bien desde el pais
  assertStringIncludes(html, '>Llamar</a>')
  assertStringIncludes(html, '5555-0001')                  // y el numero se sigue mostrando
})

Deno.test('celular null: ni WhatsApp ni Llamar, y la tarjeta no se rompe', async () => {
  const r = await handle(get(URL_T), deps(T_SIN_CEL))
  assertEquals(r.status, 200)
  const html = await r.text()
  assertEquals(html.includes('wa.me'), false)
  assertEquals(html.includes('>Llamar</a>'), false)
  assertStringIncludes(html, 'Ana Pérez')                  // la tarjeta sigue en pie
  assertStringIncludes(html, 'tel:22220001')               // el de oficina sigue estando
  assertStringIncludes(html, '>Guardar contacto</a>')
})

Deno.test('esInternacional: solo el + cuenta, no la longitud', () => {
  assertEquals(esInternacional('+502 5555-0001'), true)
  assertEquals(esInternacional('  +5215555000001'), true)   // con espacios delante
  assertEquals(esInternacional('5555-0001'), false)
  assertEquals(esInternacional('50255550001'), false)       // 11 digitos y sin +: no alcanza
  assertEquals(esInternacional(null), false)
})

Deno.test('mailto NO aparece: la RPC no devuelve email y no se inventa uno', async () => {
  const html = await (await handle(get(URL_T), deps(T))).text()
  assertEquals(html.includes('mailto:'), false)
})

Deno.test('la tarjeta tampoco se cachea: revocar tiene que surtir efecto ya', async () => {
  const r = await handle(get(URL_T), deps(T))
  assertEquals(r.status, 200)
  assertStringIncludes(r.headers.get('cache-control') ?? '', 'no-store')
  assertStringIncludes(r.headers.get('content-type') ?? '', 'text/html')
})

// ---------------------------------------------------------------- escape
Deno.test('un cargo con < y " no rompe el HTML ni se escapa del atributo del meta', async () => {
  const malo: Tarjeta = { ...T, nombre_completo: 'Ana <script>alert(1)</script>', cargo: 'Jefa " onload="x' }
  const html = await (await handle(get(URL_T), deps(malo))).text()
  assertEquals(html.includes('<script>alert(1)</script>'), false)
  assertStringIncludes(html, '&lt;script&gt;')
  // el `"` del cargo quedó escapado: el atributo content no se cierra antes de tiempo
  assertEquals(html.includes('onload="x'), false)
  assertStringIncludes(html, '&quot; onload=&quot;x')
})

Deno.test('esc: & primero, si no se re-escaparían los reemplazos', () => {
  assertEquals(esc('a & b < c'), 'a &amp; b &lt; c')
  assertEquals(esc('<'), '&lt;')
  assertEquals(esc(null), '')
})

Deno.test('soloDigitos limpia lo que wa.me no acepta', () => {
  assertEquals(soloDigitos('+502 5555-0001'), '50255550001')
  assertEquals(soloDigitos(null), '')
})

// ---------------------------------------------------------------- vCard
Deno.test('formato=vcard devuelve text/vcard con los dos teléfonos', async () => {
  const r = await handle(get(`${URL_T}?formato=vcard`), deps(T))
  assertEquals(r.status, 200)
  assertStringIncludes(r.headers.get('content-type') ?? '', 'text/vcard')
  const v = await r.text()
  assertStringIncludes(v, 'FN:Ana Pérez')
  assertStringIncludes(v, 'TITLE:Ejecutiva de cuenta')
  assertStringIncludes(v, 'TEL;TYPE=WORK,VOICE:2222-0001')
  assertStringIncludes(v, 'TEL;TYPE=CELL,VOICE:+502 5555-0001')
  assertStringIncludes(v, '\r\nEND:VCARD\r\n')   // CRLF: lo pide el RFC
})

Deno.test('la vCard pasa por el MISMO gate: sin datos, 404 y no un archivo vacío', async () => {
  const r = await handle(get(`${URL_T}?formato=vcard`), deps(null))
  assertEquals(r.status, 404)
  assertStringIncludes(r.headers.get('content-type') ?? '', 'text/html')
})

Deno.test('escVcard: una coma en el cargo no parte el campo', () => {
  assertEquals(escVcard('Jefa, zona norte'), 'Jefa\\, zona norte')
  assertEquals(escVcard('a;b'), 'a\\;b')
})

// ---------------------------------------------------------------- token
Deno.test('tokenDe: del query o del último segmento del path', () => {
  assertEquals(tokenDe(new URL('https://x/functions/v1/tarjeta-asesor?token=abc')), 'abc')
  assertEquals(tokenDe(new URL('https://x/t/abc')), 'abc')
  assertEquals(tokenDe(new URL('https://x/t/')), '')
})

Deno.test('POST no se atiende: es una tarjeta de lectura', async () => {
  const r = await handle(new Request(URL_T, { method: 'POST' }), deps(T))
  assertEquals(r.status, 405)
})

// ------------------------------------------------- el contrato con el proxy (api/tarjeta.ts)
// El gateway de Supabase reescribe el Content-Type del HTML a text/plain (medido 7-sep-2026) pero
// no toca headers propios, así que el tipo real viaja en X-Tarjeta-Content-Type y el proxy lo
// aplica. Si este header se cayera, la tarjeta se serviría como texto plano: el navegador mostraría
// el código fuente y el crawler de WhatsApp no leería los og:.
const conHeaders = (u: string, h: Record<string, string>) => new Request(u, { method: 'GET', headers: h })

Deno.test(`${H_CONTENT_TYPE} viaja SIEMPRE y dice exactamente lo mismo que el Content-Type`, async () => {
  const casos: Array<[string, Response]> = [
    ['tarjeta', await handle(get(URL_T), deps(T))],
    ['no disponible', await handle(get(URL_T), deps(null))],
    ['vcard', await handle(get(`${URL_T}?formato=vcard`), deps(T))],
    ['405', await handle(new Request(URL_T, { method: 'POST' }), deps(T))],
  ]
  for (const [nombre, r] of casos) {
    const propio = r.headers.get(H_CONTENT_TYPE)
    const real = r.headers.get('content-type')
    // No basta con que exista: tiene que coincidir. Los dos salen del mismo valor justamente para
    // que nadie pueda cambiar uno y olvidarse del otro.
    assertEquals(propio, real, `${nombre}: ${H_CONTENT_TYPE} y Content-Type divergen`)
  }
  assertStringIncludes(casos[0][1].headers.get(H_CONTENT_TYPE) ?? '', 'text/html')
  assertStringIncludes(casos[2][1].headers.get(H_CONTENT_TYPE) ?? '', 'text/vcard')
})

Deno.test('og:url se arma con el host y el path que manda el proxy, no con los de Supabase', async () => {
  // Este es el request tal como llega en producción: la URL es la INTERNA de Supabase —el gateway
  // entrega el path como /tarjeta-asesor— y lo público sólo está en los headers.
  const req = conHeaders('https://fqnsmvkxsuujahhmpzuk.supabase.co/tarjeta-asesor?token=abc123', {
    [H_HOST]: 'med.ezpayconnect.com',
    [H_PATH]: '/t/abc123',
  })
  const html = await (await handle(req, deps(T))).text()
  assertStringIncludes(html, 'og:url" content="https://med.ezpayconnect.com/t/abc123"')
  assertEquals(html.includes('supabase.co'), false)
  // y el link de la vCard cuelga de la URL pública, no de la interna
  assertStringIncludes(html, 'href="https://med.ezpayconnect.com/t/abc123?formato=vcard"')
})

Deno.test('sin los headers del proxy, og:url cae en la URL por la que se pidió', async () => {
  // Llamada DIRECTA a la edge (los smoke tests). Que og:url apunte a supabase.co acá es correcto.
  const req = get('https://fqnsmvkxsuujahhmpzuk.supabase.co/tarjeta-asesor?token=abc123')
  const html = await (await handle(req, deps(T))).text()
  assertStringIncludes(html, 'og:url" content="https://fqnsmvkxsuujahhmpzuk.supabase.co/tarjeta-asesor"')
})

// ---------------------------------------------------------------- la foto (mig 289)
// El bucket es PRIVADO y la foto la sirve esta edge bajo el MISMO gate que la tarjeta. Lo que se
// mide acá es que no haya ningún camino a los bytes que se saltee ese gate.
Deno.test('?formato=foto devuelve los BYTES con el tipo real del objeto', async () => {
  const r = await handle(get(`${URL_T}?formato=foto`), deps(T_CON_FOTO))
  assertEquals(r.status, 200)
  assertEquals(r.headers.get('content-type'), 'image/png')
  assertEquals(r.headers.get(H_CONTENT_TYPE), 'image/png')   // el proxy lo va a aplicar
  const bytes = new Uint8Array(await r.arrayBuffer())
  assertEquals(Array.from(bytes), Array.from(BYTES_FOTO))    // byte a byte, no longitud
})

Deno.test('la foto tampoco se cachea: revocar tiene que alcanzarla', async () => {
  const r = await handle(get(`${URL_T}?formato=foto`), deps(T_CON_FOTO))
  assertStringIncludes(r.headers.get('cache-control') ?? '', 'no-store')
})

Deno.test('tarjeta APAGADA: la foto da 404 igual que la tarjeta, no hay puerta de atrás', async () => {
  // deps(null) = la RPC no resolvió, que es lo que pasa con el consentimiento apagado, la ficha
  // inactiva, el perfil inactivo o un token que no existe. Los cuatro llegan acá igual.
  const r = await handle(get(`${URL_T}?formato=foto`), deps(null))
  assertEquals(r.status, 404)
  assertStringIncludes(r.headers.get('content-type') ?? '', 'text/html')
  assertStringIncludes(await r.text(), 'no está disponible')
})

Deno.test('tarjeta que resuelve pero SIN foto: 404, y se ve igual que si no existiera', async () => {
  const sinFoto = await handle(get(`${URL_T}?formato=foto`), deps(T_INTL))       // foto_publica_path null
  const inexistente = await handle(get(`${URL_T}?formato=foto`), deps(null))
  assertEquals(sinFoto.status, 404)
  assertEquals(await sinFoto.text(), await inexistente.text())   // mismo cuerpo: no es otro error
})

Deno.test('si storage no trae la foto, 404 y no un 200 vacío', async () => {
  const r = await handle(get(`${URL_T}?formato=foto`), deps(T_CON_FOTO, null, null))
  assertEquals(r.status, 404)
})

Deno.test('un tipo fuera de la lista blanca NO se sirve, ni siquiera si storage lo afirma', async () => {
  // Un SVG es código. Si algún día alguien afloja el mime del bucket, la edge sigue sin servirlo.
  const svg = await handle(get(`${URL_T}?formato=foto`),
    deps(T_CON_FOTO, null, { bytes: BYTES_FOTO, tipo: 'image/svg+xml' }))
  assertEquals(svg.status, 404)   // la extensión .png tampoco lo rescata: el tipo declarado manda
})

Deno.test('si storage no informa el tipo, se deduce de la extensión', async () => {
  const r = await handle(get(`${URL_T}?formato=foto`),
    deps({ ...T_INTL, foto_publica_path: 'aaaa/x.webp' }, null, { bytes: BYTES_FOTO, tipo: '' }))
  assertEquals(r.status, 200)
  assertEquals(r.headers.get('content-type'), 'image/webp')
})

Deno.test('tipoPorExtension: sólo los tres aceptados, y nunca svg', () => {
  assertEquals(tipoPorExtension('a/b.jpg'), 'image/jpeg')
  assertEquals(tipoPorExtension('a/b.JPEG'), 'image/jpeg')
  assertEquals(tipoPorExtension('a/b.png'), 'image/png')
  assertEquals(tipoPorExtension('a/b.webp'), 'image/webp')
  assertEquals(tipoPorExtension('a/b.svg'), '')
  assertEquals(tipoPorExtension('a/b'), '')
})

Deno.test('og:image y la <img> SÓLO si hay foto, y cuelgan del mismo token', async () => {
  const con = await (await handle(get(URL_T), deps(T_CON_FOTO))).text()
  assertStringIncludes(con, 'og:image" content="https://med.ezpayconnect.com/t/abc123?formato=foto"')
  assertStringIncludes(con, 'twitter:card" content="summary_large_image"')
  assertStringIncludes(con, '<img class="foto" src="https://med.ezpayconnect.com/t/abc123?formato=foto"')

  const sin = await (await handle(get(URL_T), deps(T_INTL))).text()
  // Un og:image que 404ea arruina la preview del link entero: sin foto, el tag no existe.
  assertEquals(sin.includes('og:image'), false)
  assertEquals(sin.includes('class="foto"'), false)
  assertStringIncludes(sin, 'twitter:card" content="summary"')
})

Deno.test('un host inyectado no se escapa del atributo del meta', async () => {
  // Los headers del proxy NO son un dato de confianza: la edge es pública y cualquiera puede
  // ponerlos a mano. Sólo alimentan un og:url cosmético, pero salen escapados igual.
  const req = conHeaders(URL_T, { [H_HOST]: 'x"><script>alert(1)</script>', [H_PATH]: '/t/abc123' })
  const html = await (await handle(req, deps(T))).text()
  assertEquals(html.includes('<script>alert(1)</script>'), false)
  assertStringIncludes(html, '&quot;&gt;&lt;script&gt;')
})
