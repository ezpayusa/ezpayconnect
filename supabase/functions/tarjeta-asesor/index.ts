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

export type Deps = {
  resolver: (token: string) => Promise<{ data: Tarjeta | null; error: unknown }>
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
  return new Response(HTML_NO_DISPONIBLE, {
    status: 404,
    headers: { ...NO_STORE, 'Content-Type': 'text/html; charset=utf-8' },
  })
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
  const vcardUrl = `${urlPublica}${urlPublica.includes('?') ? '&' : '?'}formato=vcard`

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
<meta name="twitter:card" content="summary">
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
</style></head>
<body>
<main class="card">
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

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: NO_STORE })
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return new Response('Method Not Allowed', { status: 405, headers: NO_STORE })
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
  if ((url.searchParams.get('formato') ?? '').toLowerCase() === 'vcard') {
    return new Response(renderVcard(data), {
      headers: {
        ...NO_STORE,
        'Content-Type': 'text/vcard; charset=utf-8',
        'Content-Disposition': 'attachment; filename="contacto.vcf"',
      },
    })
  }

  // og:url tiene que ser la URL PÚBLICA (la de Vercel), no la de Supabase: el crawler la usa como
  // canónica. Vercel la manda en x-forwarded-host al hacer proxy.
  //
  // AL DESPLEGAR, MIRAR ESTAS DOS COSAS — no se pueden verificar desde un test, porque el doble se
  // inventa el request, y las dos hacen que og:url quede apuntando a la URL interna de la función:
  //   1. Que Vercel MANDE `x-forwarded-host` al proxear a un destino EXTERNO (supabase.co). Si no
  //      lo mandara, el fallback `url.host` da el host de Supabase.
  //   2. Que `url.pathname` llegue como `/t/<token>` y NO como `/functions/v1/tarjeta-asesor`. Con
  //      el host correcto pero el path interno, og:url igual queda mal.
  // Se comprueba abriendo una tarjeta y leyendo el `og:url` del HTML, o pegando el link en WhatsApp
  // y viendo a dónde apunta la preview.
  const host = req.headers.get('x-forwarded-host') ?? url.host
  const proto = req.headers.get('x-forwarded-proto') ?? 'https'
  const publica = `${proto}://${host}${url.pathname === '/' ? `/t/${encodeURIComponent(token)}` : url.pathname}`

  return new Response(renderHtml(data, publica), {
    headers: { ...NO_STORE, 'Content-Type': 'text/html; charset=utf-8' },
  })
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
  }
}

if (import.meta.main) serve((req) => handle(req, depsReales()))
