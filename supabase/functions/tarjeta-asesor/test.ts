// Test REAL del borde de tarjeta-asesor. deno test --allow-net --allow-env --no-check test.ts
// Molde: enviar-push-notificacion/test.ts — se inyecta `Deps` y no se toca la red.
//
// Lo que se mide: (a) los cuatro motivos de no-respuesta se ven IGUAL; (b) el escape de todo lo que
// viene de la base; (c) los og: están en el HTML servido, que es la única razón de que esta ruta no
// sea React; (d) la vCard; (e) no-store, porque una tarjeta revocable no se cachea.
import { assertEquals, assertStringIncludes, assertNotMatch } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { handle, esc, escVcard, soloDigitos, esInternacional, tokenDe, type Deps, type Tarjeta } from './index.ts'

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
const deps = (data: Tarjeta | null, error: unknown = null): Deps => ({ resolver: async () => ({ data, error }) })
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
