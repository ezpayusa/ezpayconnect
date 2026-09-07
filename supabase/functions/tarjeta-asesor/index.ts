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


// ============================================================================================
// Activos graficos de la maqueta aprobada (docs/maqueta_tarjeta_1.html). Copiados TAL CUAL.
// ============================================================================================

/**
 * Logo de la EMPRESA MATRIZ, inlineado. Verificado al trasladar la maqueta: es byte a byte el
 * mismo `public/ezpayconnect_matriz.svg`.
 *
 * VA INLINE Y NO POR `<img src>`: esta pagina la sirve una edge y la abre gente sin sesion, asi
 * que un `<img>` seria un request mas que puede fallar y dejar la tarjeta sin marca. Inline no
 * puede faltar.
 *
 * UNA SOLA CONSTANTE PARA LAS DOS APARICIONES —la banda superior en blanco (via
 * `filter: brightness(0) invert(1)`) y el pie a color—. Duplicar 5 KB de `<path>` en el fuente
 * garantizaria que algun dia se editara una copia y no la otra.
 *
 * No declara ningun `id` ni `<defs>`, asi que aparecer dos veces en el mismo documento no colisiona
 * con nada. Los logos del PRODUCTO MEDICO si declaran un `linearGradient` con `id` y no se podrian
 * inlinear dos veces sin renombrarlo — otra razon por la que este frente usa el de la matriz.
 */
const LOGO_MATRIZ = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1102 623" role="img" aria-label="ezpayconnect"><title>ezpayconnect</title><path fill="#0168FB" fill-rule="evenodd" d="M198.0 554.1L198.0 492.0L211.2 492.0C222.7 492.0 224.5 492.5 225.4 496.0C226.7 500.9 226.2 500.9 235.3 495.6C264.1 478.6 298.8 509.0 293.2 546.4C288.8 575.3 257.5 593.5 234.9 580.2C231.0 577.9 227.4 576.0 227.0 576.0C226.5 576.0 225.9 584.8 225.6 595.5L225.0 615.0L211.5 615.6L198.0 616.2L198.0 554.1ZM389.5 614.6C387.1 614.0 386.0 611.7 386.0 607.4C386.1 594.2 387.4 592.6 399.4 591.2C422.6 588.5 422.7 587.6 403.0 537.9C384.1 490.2 384.1 492.0 403.9 492.0C415.6 492.0 415.5 491.9 424.9 518.5C434.6 546.2 434.0 546.2 444.3 517.5L453.0 493.0L465.8 492.4C484.0 491.5 484.1 490.0 462.1 546.1C436.1 612.4 424.2 623.7 389.5 614.6ZM44.6 583.9C13.8 577.8 -2.6 544.8 11.4 517.0C33.2 473.9 102.0 487.1 102.0 534.5C102.0 546.7 102.4 546.5 67.3 546.8C42.3 547.0 39.0 547.4 38.4 550.4C36.5 560.1 59.2 565.0 72.2 557.7L79.8 553.3L87.9 558.9C97.5 565.6 97.5 565.8 90.5 572.5C80.2 582.4 60.9 587.2 44.6 583.9ZM112.5 582.7C103.5 579.1 109.6 562.8 128.0 540.9C149.9 514.9 149.9 516.3 128.5 515.6L111.0 515.0L110.4 505.2C109.5 492.0 109.4 492.1 150.5 492.0L186.0 492.0L185.9 502.5C185.9 512.9 185.7 513.3 166.9 534.9C145.2 559.9 145.2 559.9 169.5 560.0L186.0 560.0L186.0 570.8C186.0 578.8 185.2 581.9 182.8 582.8C179.1 584.2 116.1 584.1 112.5 582.7ZM314.2 580.5C283.6 564.9 301.4 528.0 339.5 528.0C357.8 528.0 360.4 525.7 350.7 518.1C344.5 513.3 335.7 512.9 324.2 516.9C314.9 520.2 311.4 517.4 308.8 504.7C305.1 486.1 365.1 487.8 378.9 506.6C384.1 513.8 386.5 579.2 381.6 582.3C376.7 585.4 362.2 584.2 358.3 580.3C354.8 576.8 354.5 576.8 347.9 580.3C339.2 585.0 323.1 585.1 314.2 580.5ZM351.7 559.8C354.7 557.1 356.0 553.8 355.6 550.3C354.3 539.3 328.0 543.5 328.0 554.6C328.0 564.5 343.1 567.8 351.7 559.8ZM255.4 556.1C272.0 545.9 264.7 516.0 245.6 516.0C219.6 516.0 220.0 558.8 246.0 559.9C247.7 559.9 251.9 558.2 255.4 556.1ZM71.6 525.6C73.7 514.7 50.9 509.5 42.1 518.9C34.1 527.4 37.6 530.3 55.4 529.6C68.1 529.1 71.1 528.4 71.6 525.6ZM337.9 392.9C214.6 368.3 148.6 234.8 204.3 122.4C268.8 -7.8 448.2 -33.8 547.3 72.7C598.9 128.2 614.8 215.1 577.0 234.8C564.2 241.5 362.2 242.4 348.6 235.8C316.8 220.4 324.4 171.8 359.9 164.2C366.4 162.8 397.3 162.0 443.1 162.0C483.6 162.0 516.0 161.2 516.0 160.2C516.0 139.2 476.5 98.9 442.4 85.0C306.5 29.8 185.3 210.7 298.3 300.0C330.0 325.1 337.6 326.7 430.4 327.5C552.7 328.6 540.8 333.8 643.6 235.4C684.1 196.7 734.7 148.4 756.1 128.2C777.5 108.0 795.7 90.2 796.6 88.7C797.9 86.4 784.6 86.0 715.6 86.0C639.3 85.9 632.4 85.6 624.8 82.2C598.2 70.1 596.8 32.6 622.3 18.0L631.0 13.0L753.0 13.0L875.0 13.0L884.7 17.8C899.3 25.0 906.0 36.6 906.0 54.8C906.0 80.0 920.1 64.5 727.0 251.2C571.8 401.4 582.3 396.1 436.0 395.7C374.7 395.6 347.3 394.8 337.9 392.9Z"/><path fill="#04BE67" fill-rule="evenodd" d="M606.7 583.8C576.3 578.1 559.8 546.7 572.7 519.0C593.8 473.7 663.9 487.9 664.3 537.5C664.5 567.0 636.6 589.5 606.7 583.8ZM892.7 583.8C843.1 574.6 841.8 501.5 891.0 492.2C919.0 486.9 941.2 503.9 945.1 533.5C947.0 547.4 944.8 548.3 912.2 547.6C883.7 546.9 881.2 547.7 888.0 555.0C894.8 562.2 904.0 563.3 914.6 558.2C925.8 552.8 926.0 552.8 933.9 560.9L940.6 567.8L934.2 573.8C924.6 582.8 908.3 586.7 892.7 583.8ZM986.2 583.8C952.2 577.4 938.4 538.1 959.8 508.6C975.4 487.1 1013.6 485.7 1030.8 506.1C1037.0 513.5 1036.5 514.6 1024.5 520.7L1015.3 525.4L1008.2 520.5C989.3 507.7 969.9 528.6 981.0 549.9C986.5 560.7 1002.1 561.9 1012.6 552.5C1016.5 548.9 1032.6 555.4 1034.9 561.5C1039.1 572.5 1006.3 587.5 986.2 583.8ZM508.5 580.5C464.8 557.0 477.2 494.5 525.9 492.3C556.3 490.9 576.7 509.5 556.7 520.4L547.5 525.5L540.5 520.8C525.7 510.8 510.0 519.8 510.0 538.2C510.0 556.8 528.0 565.5 541.5 553.4L546.0 549.3L556.1 554.1C569.0 560.1 569.4 560.8 563.2 568.9C552.5 583.0 524.2 589.0 508.5 580.5ZM672.5 582.7C670.6 581.9 670.0 571.0 670.0 537.8L670.0 494.0L684.0 494.0C695.1 494.0 698.0 494.6 698.0 497.0C698.0 500.9 698.6 500.8 706.5 496.0C715.4 490.6 732.2 490.6 741.1 496.0C753.0 503.4 755.0 510.8 755.0 547.6C755.0 583.8 754.9 583.9 741.7 584.0C728.0 584.0 728.0 584.1 728.0 558.3C728.0 522.5 725.1 516.5 708.8 518.3C699.9 519.4 698.1 525.5 698.0 555.3C698.0 577.4 697.5 581.8 694.8 582.8C691.1 584.2 676.1 584.1 672.5 582.7ZM766.5 582.7C764.6 581.9 764.0 571.0 764.0 537.8L764.0 494.0L778.0 494.0C789.1 494.0 792.0 494.6 792.0 497.0C792.0 500.9 792.4 500.8 801.0 495.8C811.0 489.9 829.6 491.1 837.2 498.1C847.5 507.8 848.4 511.9 848.2 547.7C848.0 584.0 848.0 583.9 835.7 584.0C822.0 584.0 822.0 584.1 822.0 558.3C822.0 523.0 817.5 513.5 802.8 517.2C793.5 519.6 792.0 524.7 792.0 553.0C792.0 570.7 791.2 580.0 789.6 581.6C787.3 583.9 771.5 584.7 766.5 582.7ZM1062.6 581.1C1052.7 576.7 1050.0 569.3 1050.0 545.6C1049.9 521.3 1048.8 516.0 1043.9 516.0C1037.2 516.0 1037.1 494.9 1043.8 492.5C1048.6 490.7 1049.9 487.8 1050.0 479.5L1050.0 472.0L1064.0 472.0L1078.0 472.0L1078.0 481.9L1078.0 491.8L1086.5 492.4L1095.0 493.0L1095.6 504.4L1096.2 515.8L1087.6 516.4L1079.0 517.0L1078.4 536.0C1077.8 557.2 1079.6 560.8 1090.2 558.7L1096.0 557.5L1096.0 568.7C1096.0 583.9 1081.6 589.3 1062.6 581.1ZM630.5 552.0C642.6 538.7 633.4 516.0 616.0 516.0C599.6 516.0 589.8 537.6 600.3 550.9C608.8 561.7 621.2 562.1 630.5 552.0ZM915.3 526.9C917.5 521.1 908.1 513.7 899.3 514.4C891.0 515.0 882.1 523.3 884.9 527.8C887.1 531.4 913.9 530.6 915.3 526.9ZM646.7 378.9C644.6 373.5 648.2 369.2 677.3 341.5C713.6 307.1 702.7 309.7 806.1 310.4L889.3 311.0L896.5 316.0C919.9 332.0 916.5 368.1 890.6 379.2C880.3 383.6 648.4 383.3 646.7 378.9Z"/></svg>`

/** Telefono de oficina, en la fila de datos. */
const IC_TEL = `<svg viewBox="0 0 24 24" fill="none" stroke="#0168FB" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 1.9.7 2.8a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.8.7a2 2 0 0 1 1.7 2z"/></svg>`

/** Celular, en la fila de datos. */
const IC_CEL = `<svg viewBox="0 0 24 24" fill="none" stroke="#0168FB" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/></svg>`

/** Boton Llamar (trazo blanco sobre azul). */
const IC_LLAMAR = `<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 1.9.7 2.8a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.8.7a2 2 0 0 1 1.7 2z"/></svg>`

/** Boton WhatsApp (relleno blanco sobre verde). */
const IC_WA = `<svg viewBox="0 0 24 24" fill="#fff"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1a8 8 0 0 1-4-3.5c-.3-.5.3-.5.8-1.5.1-.2 0-.4 0-.5l-1-2.2c-.2-.6-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.5s1.1 2.9 1.2 3.1c.2.2 2.2 3.3 5.3 4.6 2 .9 2.7.9 3.7.8.6-.1 1.7-.7 2-1.4.2-.7.2-1.3.2-1.4-.1-.1-.3-.2-.6-.3z"/><path d="M12 2a10 10 0 0 0-8.5 15.2L2 22l4.9-1.4A10 10 0 1 0 12 2zm0 18.3c-1.6 0-3.1-.4-4.4-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.3 8.3 0 1 1 12 20.3z"/></svg>`

/** Boton Guardar contacto (descarga la vCard). */
const IC_DESCARGA = `<svg viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/></svg>`

/** Boton Compartir (navigator.share). */
const IC_COMPARTIR = `<svg viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4"/></svg>`

/**
 * Iniciales para el avatar cuando no hay foto: primera letra de la primera palabra y primera de la
 * última. Con una sola palabra, esa letra sola.
 *
 * Existe porque un círculo vacío en el lugar de la cara se lee como una imagen rota, y porque la
 * tarjeta CON foto y SIN foto tienen que medir lo mismo: el avatar está montado sobre la banda y
 * quitarlo descuadraría el encabezado entero.
 */
export function iniciales(nombre: string | null): string {
  const partes = String(nombre ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return ''
  const primera = [...partes[0]][0] ?? ''
  const ultima = partes.length > 1 ? ([...partes[partes.length - 1]][0] ?? '') : ''
  return (primera + ultima).toUpperCase()
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

  // El avatar SIEMPRE ocupa el mismo lugar: con foto es un <img>, sin foto un círculo con las
  // iniciales. El og:image, en cambio, sólo existe si hay foto: el placeholder es para el humano
  // que abre la tarjeta, no para el crawler que arma la preview de un link.
  const avatar = fotoUrl
    ? `<img class="av" src="${esc(fotoUrl)}" alt="" width="104" height="104">`
    : `<div class="av av-ph" aria-hidden="true">${esc(iniciales(t.nombre_completo))}</div>`

  // Cada fila de teléfono se emite sólo si el dato existe; el bloque entero desaparece si no hay
  // ninguno. Un `.fila` vacío dejaría un separador flotando sobre la nada.
  const filas = [
    t.telefono
      ? `<div class="fila"><div class="ic">${IC_TEL}</div><div><div class="et">Oficina</div>
      <a class="val" href="tel:${esc(soloDigitos(t.telefono))}">${esc(t.telefono)}</a></div></div>`
      : '',
    t.celular
      ? `<div class="fila"><div class="ic">${IC_CEL}</div><div><div class="et">Celular</div>
      <a class="val" href="tel:${esc(soloDigitos(t.celular))}">${esc(t.celular)}</a></div></div>`
      : '',
  ].filter(Boolean).join('\n  ')

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
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;
 background:#eef2f7;display:flex;justify-content:center;padding:28px 16px;-webkit-font-smoothing:antialiased}
.card{width:100%;max-width:380px;background:#fff;border-radius:20px;overflow:hidden;
 box-shadow:0 1px 2px rgba(16,32,64,.06),0 12px 32px -8px rgba(16,32,64,.18)}
.nom{font-size:23px;font-weight:700;letter-spacing:-.02em;color:#0f1c33;line-height:1.2}
.cargo{font-size:14px;font-weight:600;color:#0168FB;margin-top:5px}
.terr{font-size:13px;color:#64748b;margin-top:3px;line-height:1.45}
.tels{padding:0 26px}
.fila{display:flex;align-items:center;gap:12px;padding:13px 0;border-bottom:1px solid #eef1f6}
.fila:last-child{border-bottom:0}
.ic{width:34px;height:34px;border-radius:10px;display:grid;place-items:center;flex:none;background:#eef4ff}
.ic svg{width:17px;height:17px}
.et{font-size:11px;color:#94a3b8;text-transform:uppercase;letter-spacing:.07em;font-weight:600}
.val{font-size:15px;color:#0f1c33;font-weight:600;text-decoration:none;display:block;margin-top:1px}
.acc{padding:18px 26px 22px;display:grid;gap:9px}
.b{display:flex;align-items:center;justify-content:center;gap:8px;height:46px;border-radius:12px;
 font-size:14.5px;font-weight:600;text-decoration:none;border:0;cursor:pointer;font-family:inherit}
.b svg{width:17px;height:17px}
.b1{background:#0168FB;color:#fff}
.b2{background:#04BE67;color:#fff}
.b3{background:#fff;color:#334155;border:1.5px solid #dfe5ee}
.pie{border-top:1px solid #eef1f6;padding:16px 26px 18px;display:flex;align-items:center;justify-content:space-between;gap:14px}
.pie .lg svg{height:30px;width:auto;display:block}
.pie span{font-size:11.5px;color:#94a3b8;text-align:right;line-height:1.45}
.hero{height:112px;background:linear-gradient(115deg,#0168FB 0%,#0a86d6 55%,#04BE67 100%);position:relative}
.marca{position:absolute;top:15px;left:22px;filter:brightness(0) invert(1);opacity:.98}
.marca svg{height:44px;width:auto;display:block}
.av{width:104px;height:104px;border-radius:50%;object-fit:cover;border:5px solid #fff;background:#e2e8f0;
 position:absolute;left:50%;transform:translateX(-50%);bottom:-52px;box-shadow:0 4px 14px rgba(16,32,64,.14)}
.av-ph{display:grid;place-items:center;font-size:38px;font-weight:700;color:#94a3b8;letter-spacing:.01em;
 line-height:1;user-select:none}
.enc{padding:66px 26px 20px;text-align:center}
</style></head>
<body>
<div class="card">
 <div class="hero"><span class="marca">${LOGO_MATRIZ}</span>${avatar}</div>
 <div class="enc"><h1 class="nom">${esc(nombre)}</h1>${t.cargo ? `
 <p class="cargo">${esc(t.cargo)}</p>` : ''}${t.territorio ? `
 <p class="terr">${esc(t.territorio)}</p>` : ''}</div>
${filas ? `<div class="tels">
  ${filas}
</div>` : ''}
<div class="acc">
  ${t.celular ? `<a class="b b1" href="tel:${esc(soloDigitos(t.celular))}">${IC_LLAMAR} Llamar</a>` : ''}
  ${wa ? `<a class="b b2" href="https://wa.me/${esc(wa)}" rel="noopener">${IC_WA} WhatsApp</a>` : ''}
  <a class="b b3" href="${esc(vcardUrl)}">${IC_DESCARGA} Guardar contacto</a>
  <button class="b b3" id="compartir" hidden>${IC_COMPARTIR} Compartir</button>
</div>
<div class="pie"><span class="lg">${LOGO_MATRIZ}</span><span>La solución SaaS que<br>necesitas para tu empresa</span></div>
</div>
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
