import type { VercelRequest, VercelResponse } from '@vercel/node';

// Proxy de la tarjeta pública del asesor: /t/<token> -> esta función -> edge `tarjeta-asesor`.
//
// NO DECIDE NADA. Toda la lógica —resolver el token, mirar el consentimiento, el `activo` de la
// ficha y el del perfil, elegir HTML o vCard— vive en la edge, que es la única que puede hablar con
// `tarjeta_publica_por_token` (sólo `service_role` tiene EXECUTE, mig 288). Acá se transporta y se
// arreglan headers, nada más. Por eso esta función NO necesita ningún secreto nuevo: la URL del
// proyecto no es secreta y el service_role se queda del lado de Supabase, que es todo el punto.
//
// POR QUÉ EXISTE, medido el 7-sep-2026 contra el deploy real y no supuesto:
//   1. El gateway de Supabase reescribe el `Content-Type` de toda respuesta HTML a `text/plain` y
//      le agrega `Content-Security-Policy: default-src 'none'; sandbox`. Es su defensa
//      anti-phishing sobre `*.supabase.co`. Con eso el navegador muestra el código fuente en vez de
//      la tarjeta, y el crawler de WhatsApp no lee los `og:` de un `text/plain` — que es la única
//      razón por la que esta ruta sirve HTML server-side y no es una página de React.
//   2. Vercel NO lo arregla: proxea la respuesta de un rewrite externo sin tocar headers. Medido
//      contra med.ezpayconnect.com, llegaron el `text/plain` y el CSP intactos.
//   3. Vercel tampoco manda `x-forwarded-host` a un destino externo, y el gateway entrega el path
//      como `/tarjeta-asesor`. Con eso `og:url` salía `https://<ref>.supabase.co/tarjeta-asesor`:
//      mal el dominio Y mal el path. Acá el host y el path públicos los mandamos nosotros.
// La contraprueba de (1) está en la misma medición: la vCard llegó intacta con su `text/vcard` y
// sin CSP. El gateway interviene sobre `text/html` y no toca headers propios — por ahí viaja el
// tipo real.

// Contrato con la edge (supabase/functions/tarjeta-asesor/index.ts). En minúscula porque los
// headers de una Response de fetch se leen así.
const H_CONTENT_TYPE = 'x-tarjeta-content-type';
const H_HOST = 'x-tarjeta-host';
const H_PATH = 'x-tarjeta-path';

/**
 * Headers de la edge que se propagan al cliente. Es una LISTA BLANCA y no una lista negra del CSP
 * de Supabase: lo que el gateway agregue mañana no se cuela solo. De paso deja afuera el `set-cookie`
 * del `__cf_bm` de Cloudflare, que no tiene nada que hacer en el dominio propio.
 */
const PROPAGAR = ['cache-control', 'x-robots-tag', 'x-content-type-options', 'content-disposition'];

/** Lo único del query que se reenvía. El resto no se pasa: la edge no tiene por qué verlo. */
const QUERY_PERMITIDO = ['formato'];

const HTML_ERROR = `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tarjeta no disponible</title>
<meta name="robots" content="noindex,nofollow">
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f8fafc;
font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#334155}
.c{max-width:22rem;padding:2rem;text-align:center}h1{font-size:1.125rem;color:#0f172a;margin:0 0 .5rem}</style>
</head><body><div class="c">
<h1>No pudimos mostrar esta tarjeta</h1>
<p>Volvé a intentarlo en un momento.</p>
</div></body></html>`;

/** Un query param de Vercel puede venir repetido (`?formato=a&formato=b`) y entonces es un array. */
function unico(v: string | string[] | undefined): string {
  return (Array.isArray(v) ? v[0] : v) ?? '';
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // TODO el cuerpo va dentro del try: cualquier rechazo async debe salir como una página legible,
  // NUNCA como el 500 opaco genérico de Vercel. (Mismo patrón que api/send-receta.ts.)
  try {
    const base = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
    if (!base) {
      console.error('[tarjeta] falta SUPABASE_URL/VITE_SUPABASE_URL en env');
      return responderError(res);
    }

    const token = unico(req.query.token).trim();
    const upstream = new URL(`${base.replace(/\/+$/, '')}/functions/v1/tarjeta-asesor`);
    // Se manda SIEMPRE, aunque venga vacío: la edge trata "sin token" y "token inválido" igual, y
    // esa decisión es de ella. Acá no se cortocircuita para no crear un segundo lugar que decide.
    upstream.searchParams.set('token', token);
    for (const k of QUERY_PERMITIDO) {
      const v = unico(req.query[k]);
      if (v) upstream.searchParams.set(k, v);
    }

    // Lo que el gateway de Supabase le esconde a la edge. No dependemos de que un intermediario los
    // ponga: acá el intermediario somos nosotros, así que los ponemos nosotros.
    // El path se REconstruye desde el token en vez de leerlo del request, porque para cuando esta
    // función corre, Vercel ya reescribió la URL a /api/tarjeta?token=... y el `/t/<token>` original
    // no está en ningún lado.
    const host = unico(req.headers['x-forwarded-host'] as string | string[] | undefined)
      || unico(req.headers.host as string | undefined);
    const proto = unico(req.headers['x-forwarded-proto'] as string | string[] | undefined) || 'https';

    const r = await fetch(upstream.toString(), {
      // El método se reenvía tal cual para que el 405 de la edge llegue como 405 y no lo invente
      // este proxy. No se reenvía el cuerpo: la edge rechaza todo lo que no sea GET/HEAD sin mirarlo.
      method: req.method || 'GET',
      headers: {
        [H_HOST]: host,
        [H_PATH]: `/t/${encodeURIComponent(token)}`,
        'x-forwarded-proto': proto,
      },
    });

    // BYTES CRUDOS, NUNCA TEXTO. `await r.text()` decodifica como UTF-8, y una imagen no es UTF-8:
    // cada secuencia inválida se reemplaza por U+FFFD y al re-serializar sale un archivo distinto
    // del que mandó la edge. No falla ni avisa — entrega un JPEG roto. Con arrayBuffer + Buffer los
    // bytes pasan tal cual.
    // Es UN SOLO camino para todo, sin ramificar por tipo: el HTML y la vCard viajan igual de bien
    // como bytes, y un `if (esImagen)` sería una segunda decisión sobre qué se está sirviendo, que
    // es justo lo que este proxy no hace (el tipo lo dice la edge, ver más abajo).
    const body = Buffer.from(await r.arrayBuffer());

    // El tipo lo DICE LA EDGE. Si el header no viene, es que allá quedó desplegada una versión
    // vieja: se registra y se cae al `Content-Type` que haya mandado el gateway. Preferible a
    // adivinar `text/html` y etiquetar mal una vCard, y además el síntoma queda visible.
    let contentType = r.headers.get(H_CONTENT_TYPE);
    if (!contentType) {
      console.error(`[tarjeta] la edge no mandó ${H_CONTENT_TYPE}; ¿deploy desincronizado?`);
      contentType = r.headers.get('content-type') || 'text/plain; charset=utf-8';
    }
    res.setHeader('Content-Type', contentType);

    for (const h of PROPAGAR) {
      const v = r.headers.get(h);
      if (v) res.setHeader(h, v);
    }

    return res.status(r.status).send(body);
  } catch (e) {
    console.error('[tarjeta] error no controlado:', e);
    return responderError(res);
  }
}

/**
 * 502 y NO el 404 de "tarjeta no disponible". Los cuatro motivos de no-respuesta se ven iguales
 * entre sí a propósito, pero una caída del proxy no es uno de ellos: mostrarla como 404 haría que
 * una interrupción real se leyera como una tarjeta apagada, y nadie se enteraría.
 */
function responderError(res: VercelResponse) {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.status(502).send(HTML_ERROR);
}
