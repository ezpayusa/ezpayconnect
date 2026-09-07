import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Edge PÚBLICA (verify_jwt=false): la tarjeta de presentación de un asesor comercial, servida SIN
// sesión desde el link que él mismo reparte. Credencial = tarjeta_token (256 bits) en la URL, y el
// CONSENTIMIENTO se evalúa en cada request dentro de la RPC.
// Caparazón FINO: resolver el token, mirar el consentimiento, el `activo` de la ficha y el del
// perfil vive todo en `tarjeta_publica_por_token` (SECURITY DEFINER, mig 288), que además sólo
// puede ejecutar `service_role`. Acá no hay ni una decisión de autorización.
//
// POR QUÉ ESTA RUTA DEVUELVE HTML Y NO ES UNA PÁGINA REACT: el crawler de WhatsApp (y el de
// Facebook, y el de Telegram) NO ejecuta JavaScript. Si los `og:` los pusiera la SPA al montar, la
// preview del link no existiría. El HTML server-side es lo único que justifica esta excepción.
//
// LOS CUATRO MOTIVOS DE NO-RESPUESTA SE VEN IGUAL: token inexistente, consentimiento apagado, ficha
// inactiva y perfil inactivo devuelven el mismo 404 con la misma página. La RPC ya los devuelve
// indistinguibles (NULL); acá no se los vuelve a separar.
//
// AL PÚBLICO NO LLEGA POR ACÁ DIRECTO: adelante hay un proxy en `api/tarjeta.ts` (función de Vercel)
// que sirve `/t/<token>`. Existe SÓLO por los headers —el gateway de Supabase rompe el Content-Type
// del HTML y esconde el host público—; ninguna decisión vive ahí. El contrato entre los dos son los
// tres headers `X-Tarjeta-*` de más abajo.

export type Deps = {
  resolver: (token: string) => Promise<{ data: Tarjeta | null; error: unknown }>
  /**
   * Baja el objeto del bucket PRIVADO `tarjetas-asesor` con service_role. Devuelve NULL si no está
   * —path borrado, bucket vacío, error de red—: quien llama trata eso igual que "no hay foto", que
   * es lo que ve el visitante de todos modos.
   */
  descargarFoto: (path: string) => Promise<{ bytes: Uint8Array; tipo: string } | null>
}

/**
 * Los ÚNICOS tipos que se sirven. Es una lista blanca y no una validación del bucket, aunque el
 * bucket ya restrinja el MIME al subir: esto sale por nuestro dominio, y el día que alguien
 * afloje `allowed_mime_types` la edge no tiene por qué enterarse para seguir siendo segura.
 * SIN `image/svg+xml`: un SVG es código, no una imagen.
 */
const TIPOS_FOTO = ['image/jpeg', 'image/png', 'image/webp']

/** Último recurso cuando storage no informa el tipo. Sólo las tres extensiones aceptadas. */
export function tipoPorExtension(path: string): string {
  const ext = path.toLowerCase().split('.').pop() ?? ''
  if (ext === 'jpg' || ext === 'jpeg') return 'image/jpeg'
  if (ext === 'png') return 'image/png'
  if (ext === 'webp') return 'image/webp'
  return ''
}

export type Tarjeta = {
  nombre_completo: string | null
  cargo: string | null
  territorio: string | null
  telefono: string | null
  celular: string | null
  foto_publica_path: string | null
}

/**
 * Escape explícito para todo lo que viene de la base. Los campos de la ficha los escribe el admin
 * de país a mano: un cargo con `<` parte el HTML, y uno con `"` se escapa del atributo `content`
 * de un meta y puede inyectar otro. No se confía en que "no va a pasar".
 * `&` va PRIMERO: si no, re-escaparía los `&` de los reemplazos siguientes.
 */
export function esc(v: unknown): string {
  return String(v ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

/** wa.me quiere sólo dígitos. Un celular con espacios, guiones o paréntesis rompe el link. */
export function soloDigitos(v: string | null): string {
  return String(v ?? '').replace(/\D+/g, '')
}

/**
 * ¿Se puede armar un wa.me con este número? SÓLO si empieza con `+`.
 *
 * `wa.me` exige el número en formato internacional completo. Un `5555-0001` guardado a secas
 * produce `wa.me/55550001`, que no le corresponde a nadie: WhatsApp abre y no encuentra el
 * contacto. Falla en silencio, que es peor que no ofrecer el botón.
 *
 * El `+` es una marca EXPLÍCITA de número internacional puesta por quien cargó el dato, y es lo
 * único confiable que hay acá. Adivinar por cantidad de dígitos falla distinto en cada país del
 * módulo —8 en Guatemala, 10 en México, 10 en Colombia, 8 en El Salvador— y **la respuesta de la
 * RPC no trae `pais_id`**: el censo de P651 fija seis campos y no se toca por esto.
 *
 * Sin `+`, el botón de WhatsApp NO EXISTE — no deshabilitado, no presente. El de Llamar se mantiene
 * siempre: un número local marca bien desde el mismo país, que es donde está el prospecto.
 */
export function esInternacional(v: string | null): boolean {
  return String(v ?? '').trim().startsWith('+')
}

/**
 * vCard. Sus saltos de línea son CRLF y sus separadores son `,` `;` `\` `\n`: un cargo con una coma
 * partiría el campo en dos. Escape propio, distinto del de HTML — no son el mismo problema.
 */
export function escVcard(v: unknown): string {
  return String(v ?? '')
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;')
}

const NO_STORE = {
  // Una tarjeta REVOCABLE no se cachea. Si un intermediario la guarda, apagar el consentimiento
  // deja de tener efecto: seguiría sirviéndose desde el caché durante quién sabe cuánto.
  'Cache-Control': 'no-store, no-cache, must-revalidate',
  'X-Content-Type-Options': 'nosniff',
  // Sin `noindex` la tarjeta terminaría en Google, que es un caché que no se puede purgar.
  'X-Robots-Tag': 'noindex, nofollow',
}

/**
 * Los tres headers del contrato con el proxy de Vercel (`api/tarjeta.ts`).
 *
 * POR QUÉ EXISTE ESTE CONTRATO — medido el 7-sep-2026 contra el deploy real, no supuesto:
 * el gateway de Supabase REESCRIBE el `Content-Type` de toda respuesta HTML a `text/plain` y le
 * agrega `Content-Security-Policy: default-src 'none'; sandbox`. Es su defensa anti-phishing sobre
 * `*.supabase.co` y no se puede apagar desde acá. La contraprueba está en el mismo lote: la vCard
 * llegó intacta con su `text/vcard` y SIN CSP, o sea que el gateway interviene sólo sobre
 * `text/html` y **no toca headers propios**. Por ahí viaja el tipo real.
 *
 * Vercel tampoco lo arregla: proxea la respuesta del rewrite externo sin tocar headers (medido
 * también, contra med.ezpayconnect.com). De ahí el proxy en `/api`.
 */
export const H_CONTENT_TYPE = 'X-Tarjeta-Content-Type'
export const H_HOST = 'X-Tarjeta-Host'
export const H_PATH = 'X-Tarjeta-Path'

/**
 * TODA respuesta sale por acá. El `Content-Type` real y el header que lo transporta se emiten del
 * MISMO valor, así que no pueden divergir: quién decide qué se está sirviendo es esta función y
 * nadie más. El proxy sólo copia — si el tipo viviera también en un `if (formato === 'vcard')` del
 * lado de Vercel, habría dos lugares que opinan sobre lo mismo y un día dirían cosas distintas.
 */
function respuesta(
  body: string | Uint8Array,
  contentType: string,
  status = 200,
  extra: Record<string, string> = {},
): Response {
  return new Response(body, {
    status,
    headers: { ...NO_STORE, ...extra, 'Content-Type': contentType, [H_CONTENT_TYPE]: contentType },
  })
}

const HTML_NO_DISPONIBLE = `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tarjeta no disponible</title>
<meta name="robots" content="noindex,nofollow">
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f8fafc;
font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#334155}
.c{max-width:22rem;padding:2rem;text-align:center}h1{font-size:1.125rem;color:#0f172a;margin:0 0 .5rem}</style>
</head><body><div class="c">
<h1>Esta tarjeta no está disponible</h1>
<p>El enlace puede haber cambiado o ya no estar activo.</p>
</div></body></html>`

function paginaNoDisponible(): Response {
  return respuesta(HTML_NO_DISPONIBLE, 'text/html; charset=utf-8', 404)
}

export function renderVcard(t: Tarjeta): string {
  const nombre = escVcard(t.nombre_completo ?? 'Asesor')
  const filas = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    `FN:${nombre}`,
    `N:${nombre};;;;`,
  ]
  if (t.cargo) filas.push(`TITLE:${escVcard(t.cargo)}`)
  if (t.telefono) filas.push(`TEL;TYPE=WORK,VOICE:${escVcard(t.telefono)}`)
  if (t.celular) filas.push(`TEL;TYPE=CELL,VOICE:${escVcard(t.celular)}`)
  filas.push('END:VCARD')
  // CRLF: lo pide RFC 6350. Con \n solo, algunos clientes de contactos no lo importan.
  return filas.join('\r\n') + '\r\n'
}

export function renderHtml(t: Tarjeta, urlPublica: string): string {
  const nombre = t.nombre_completo ?? 'Asesor comercial'
  const titulo = t.cargo ? `${nombre} — ${t.cargo}` : nombre
  const desc = t.territorio ? `Territorio: ${t.territorio}` : 'Asesor comercial de EzPayConnect'
  // Sin `+` no hay botón de WhatsApp. Ver esInternacional.
  const wa = esInternacional(t.celular) ? soloDigitos(t.celular) : ''
  const sep = urlPublica.includes('?') ? '&' : '?'
  const vcardUrl = `${urlPublica}${sep}formato=vcard`
  // MISMA URL, MISMO TOKEN, otro formato. La foto no tiene una URL propia que se pueda repartir
  // suelta: cuelga del token, así que apagar el consentimiento la mata igual que a la tarjeta.
  // Sin foto NO se emite el tag: un og:image que 404ea le arruina la preview al link entero, y
  // varios crawlers prefieren no mostrar nada antes que mostrar un hueco.
  const fotoUrl = t.foto_publica_path ? `${urlPublica}${sep}formato=foto` : ''

  return `<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(titulo)}</title>
<meta name="robots" content="noindex,nofollow">
<meta property="og:type" content="profile">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(urlPublica)}">
${fotoUrl ? `<meta property="og:image" content="${esc(fotoUrl)}">
<meta name="twitter:card" content="summary_large_image">` : `<meta name="twitter:card" content="summary">`}
<style>
:root{color-scheme:light}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f1f5f9;
font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#334155;padding:1rem}
.card{width:100%;max-width:22rem;background:#fff;border-radius:1rem;padding:1.75rem 1.5rem;
box-shadow:0 1px 3px rgba(15,23,42,.1),0 8px 24px rgba(15,23,42,.06);text-align:center}
h1{margin:0;font-size:1.25rem;color:#0f172a}
.cargo{margin:.25rem 0 0;color:#1E5C8E;font-weight:600;font-size:.9rem}
.terr{margin:.25rem 0 0;color:#64748b;font-size:.85rem}
.tels{margin:1.25rem 0 0;border-top:1px solid #e2e8f0;padding-top:1rem;text-align:left}
.tel{display:flex;justify-content:space-between;gap:.75rem;font-size:.9rem;padding:.25rem 0}
.tel span{color:#64748b}
.tel a{color:#1E5C8E;text-decoration:none;font-variant-numeric:tabular-nums}
.acc{margin-top:1.25rem;display:grid;gap:.5rem}
.b{display:block;padding:.7rem;border-radius:.5rem;text-decoration:none;font-size:.9rem;font-weight:600;
border:1px solid transparent;cursor:pointer;font-family:inherit;width:100%}
.b1{background:#1E5C8E;color:#fff}
.b2{background:#25D366;color:#fff}
.b3{background:#fff;color:#334155;border-color:#cbd5e1}
.foto{width:7rem;height:7rem;border-radius:50%;object-fit:cover;display:block;margin:0 auto 1rem;
background:#e2e8f0}
</style></head>
<body>
<main class="card">
  ${fotoUrl ? `<img class="foto" src="${esc(fotoUrl)}" alt="" width="112" height="112">` : ''}
  <h1>${esc(nombre)}</h1>
  ${t.cargo ? `<p class="cargo">${esc(t.cargo)}</p>` : ''}
  ${t.territorio ? `<p class="terr">${esc(t.territorio)}</p>` : ''}
  ${(t.telefono || t.celular) ? `<div class="tels">
    ${t.telefono ? `<p class="tel"><span>Oficina</span><a href="tel:${esc(soloDigitos(t.telefono))}">${esc(t.telefono)}</a></p>` : ''}
    ${t.celular ? `<p class="tel"><span>Celular</span><a href="tel:${esc(soloDigitos(t.celular))}">${esc(t.celular)}</a></p>` : ''}
  </div>` : ''}
  <div class="acc">
    ${t.celular ? `<a class="b b1" href="tel:${esc(soloDigitos(t.celular))}">Llamar</a>` : ''}
    ${wa ? `<a class="b b2" href="https://wa.me/${esc(wa)}" rel="noopener">WhatsApp</a>` : ''}
    <a class="b b3" href="${esc(vcardUrl)}">Guardar contacto</a>
    <button class="b b3" id="compartir" hidden>Compartir</button>
  </div>
</main>
<script>
// El crawler no necesita esto; el humano sí. navigator.share sólo existe en contexto seguro y en
// algunos navegadores: el botón nace oculto y se muestra únicamente si la API está.
(function () {
  var b = document.getElementById('compartir')
  if (!b || !navigator.share) return
  b.hidden = false
  b.addEventListener('click', function () {
    navigator.share({ title: document.title, url: location.href }).catch(function () {})
  })
})()
</script>
</body></html>`
}

/**
 * El token viene del query (`?token=`, que es lo que manda el rewrite de Vercel) y, como defensa en
 * profundidad, del path `/t/<token>`.
 *
 * El fallback del path exige la forma EXACTA `['t', <token>]`. Tomar "el último segmento" a secas
 * hacía que `/t/` (sin token) resolviera con el token literal `"t"`: un path sin credencial se
 * convertía en una consulta con credencial. Lo encontró el test.
 */
export function tokenDe(url: URL): string {
  const q = url.searchParams.get('token')?.trim()
  if (q) return q
  const seg = url.pathname.split('/').filter(Boolean)
  if (seg.length !== 2 || seg[0] !== 't') return ''
  return decodeURIComponent(seg[1]).trim()
}

/**
 * La URL PÚBLICA de la tarjeta, la que va en `og:url` porque el crawler la toma como canónica.
 *
 * LAS DOS INCÓGNITAS QUE ESTABAN ANOTADAS ACÁ YA ESTÁN MEDIDAS (7-sep-2026, deploy real contra
 * med.ezpayconnect.com), y las dos salieron que NO:
 *   1. Vercel **no manda `x-forwarded-host`** al proxear a un destino EXTERNO. El fallback
 *      `url.host` daba `fqnsmvkxsuujahhmpzuk.supabase.co`.
 *   2. El gateway de Supabase entrega el path como **`/tarjeta-asesor`** (se come `/functions/v1`),
 *      así que tampoco llegaba `/` ni `/t/<token>`: `og:url` salía `.../tarjeta-asesor`.
 * O sea que ninguno de los dos datos llegaba solo, y con el host correcto pero el path interno
 * habría quedado mal igual. Por eso el proxy los manda EXPLÍCITOS en X-Tarjeta-Host y X-Tarjeta-Path,
 * en vez de esperar que un intermediario los ponga.
 *
 * Los fallbacks quedan para cuando se llama a la edge directo, sin proxy (los smoke tests): ahí
 * `og:url` apunta a supabase.co y está bien que así sea, es la URL por la que se pidió.
 *
 * ESTOS HEADERS NO SON UN DATO DE CONFIANZA y no hace falta que lo sean: la edge es pública, y
 * cualquiera puede llamarla poniéndolos a mano. Lo único que alimentan es un `og:url` cosmético en
 * una página que ese mismo llamante ya pidió; ninguna decisión de autorización los mira. Salen
 * escapados igual, como todo lo demás (ver `esc`).
 */
export function urlPublicaDe(req: Request, url: URL, token: string): string {
  const host = req.headers.get(H_HOST) ?? req.headers.get('x-forwarded-host') ?? url.host
  const proto = req.headers.get('x-forwarded-proto') ?? 'https'
  const path = req.headers.get(H_PATH)
    ?? (url.pathname === '/' ? `/t/${encodeURIComponent(token)}` : url.pathname)
  return `${proto}://${host}${path}`
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return respuesta('ok', 'text/plain; charset=utf-8')
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return respuesta('Method Not Allowed', 'text/plain; charset=utf-8', 405)
  }

  const url = new URL(req.url)
  const token = tokenDe(url)
  // Sin token = mismo resultado que token inválido. No se dice cuál de las dos cosas fue.
  if (!token) return paginaNoDisponible()

  let data: Tarjeta | null = null
  try {
    const r = await deps.resolver(token)
    if (r.error) {
      // Fail-safe: el error real va a los logs, al visitante le llega la página genérica.
      console.error('[tarjeta-asesor] error RPC:', r.error)
      return paginaNoDisponible()
    }
    data = r.data
  } catch (e) {
    console.error('[tarjeta-asesor] error no controlado:', e)
    return paginaNoDisponible()
  }

  if (!data) return paginaNoDisponible()

  // FORMATO POR QUERY (`?formato=vcard`) Y NO POR PATH. El rewrite de Vercel manda todo lo que
  // sigue a /t/ como token, que es opaco: agregarle segmentos o una extensión obligaría a parsearlo
  // y a distinguir "token con barra" de "token + sufijo". El query es ortogonal al token y no lo
  // toca.
  const formato = (url.searchParams.get('formato') ?? '').toLowerCase()

  if (formato === 'vcard') {
    return respuesta(renderVcard(data), 'text/vcard; charset=utf-8', 200, {
      'Content-Disposition': 'attachment; filename="contacto.vcf"',
    })
  }

  // FOTO. Llega acá SÓLO después de que `data` resolvió, o sea después del MISMO gate que la
  // tarjeta: token, consentimiento, `activo` de la ficha y `activo` del perfil. No hay atajo que
  // salte esas cuatro condiciones, y por eso el bucket puede ser privado — apagar el
  // consentimiento deja la foto inalcanzable en el request siguiente, sin URL sobreviviente.
  if (formato === 'foto') {
    // Sin foto es 404 y NO un error distinto: "no tiene foto" y "no existe la tarjeta" se ven
    // igual, por la misma razón por la que los cuatro motivos de no-respuesta se ven iguales.
    if (!data.foto_publica_path) return paginaNoDisponible()

    let foto: { bytes: Uint8Array; tipo: string } | null = null
    try {
      foto = await deps.descargarFoto(data.foto_publica_path)
    } catch (e) {
      console.error('[tarjeta-asesor] error bajando la foto:', e)
      return paginaNoDisponible()
    }
    if (!foto) return paginaNoDisponible()

    // El tipo REAL del objeto, contra la lista blanca. La extensión es el fallback para cuando
    // storage NO INFORMA el tipo — y sólo para eso. Si storage informa uno que no aceptamos, se
    // rechaza y no se lo "rescata" mirando la extensión: tratar un tipo prohibido como si fuera
    // desconocido es la forma silenciosa de servir lo que dijimos que no íbamos a servir.
    // Lo encontró este test: con tipo `image/svg+xml` y path `.png` el código anterior devolvía 200.
    // El precio es que un objeto con un tipo raro no se muestra; el bucket ya restringe el MIME al
    // subir (mig 289), así que eso sólo pasa si algo está mal, y entonces no mostrarlo es correcto.
    const declarado = (foto.tipo ?? '').trim()
    const tipo = declarado
      ? (TIPOS_FOTO.includes(declarado) ? declarado : '')
      : tipoPorExtension(data.foto_publica_path)
    if (!TIPOS_FOTO.includes(tipo)) {
      console.error('[tarjeta-asesor] foto con tipo no servible:', foto.tipo, data.foto_publica_path)
      return paginaNoDisponible()
    }

    // no-store igual que todo lo demás: una foto cacheada por un intermediario sobreviviría a
    // revocar el consentimiento, que es exactamente lo que el bucket privado vino a impedir.
    return respuesta(foto.bytes, tipo)
  }

  return respuesta(renderHtml(data, urlPublicaDe(req, url, token)), 'text/html; charset=utf-8')
}

// Cliente con service_role: molde de las edges del repo (SB_* con fallback SUPABASE_*).
// `tarjeta_publica_por_token` sólo tiene EXECUTE para service_role — ni anon ni authenticated.
function depsReales(): Deps {
  const supabase = createClient(
    (Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')) ?? '',
    (Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) ?? '',
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
  return {
    resolver: async (token: string) => {
      const { data, error } = await supabase.rpc('tarjeta_publica_por_token', { p_token: token })
      return { data: (data ?? null) as Tarjeta | null, error }
    },
    // Bucket PRIVADO (mig 289): sin service_role esto no baja nada. No se firma una URL ni se
    // redirige al visitante a storage — una URL firmada seguiría viva su tiempo de vida aunque
    // el consentimiento se apague en el medio. Los bytes pasan por acá y por ningún otro lado.
    descargarFoto: async (path: string) => {
      const { data, error } = await supabase.storage.from('tarjetas-asesor').download(path)
      if (error || !data) {
        if (error) console.error('[tarjeta-asesor] storage.download:', error)
        return null
      }
      return { bytes: new Uint8Array(await data.arrayBuffer()), tipo: data.type ?? '' }
    },
  }
}

if (import.meta.main) serve((req) => handle(req, depsReales()))
