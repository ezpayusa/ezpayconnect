// Observabilidad: Sentry SOLO error monitoring, con scrubbing de PHI desde el día 1.
//
// Reglas innegociables de este archivo:
//  - NADA de performance/replay/profiling (browserTracing, replay, tracesSampleRate, etc.).
//  - Deny-by-default en URLs: todo valor de query param se borra, y todo segmento de path
//    numérico o UUID se borra. Un id nuevo mañana ya queda cubierto sin tocar código.
//  - Breadcrumbs de console DESACTIVADOS: hay console.error en el repo que imprimen paciente_id.
//  - Un chunk obsoleto NO es un bug → se descarta (misma detección que main.tsx/ErrorBoundary).

import * as Sentry from '@sentry/react'
import { esChunkError } from '@/lib/chunk-reload'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const NUM_RE = /^\d+$/

// scrubUrl: deny-by-default. Soporta URLs absolutas y relativas (paths de router).
//  - query: TODOS los valores → [scrubbed] (sin allowlist).
//  - path: cada segmento numérico puro o UUID → [scrubbed].
// Ejemplos:
//   /clinica/admision?paciente_id=23&cita_id=1353 → /clinica/admision?paciente_id=[scrubbed]&cita_id=[scrubbed]
//   /medico/consulta/1353                         → /medico/consulta/[scrubbed]
//   /pacientes/9f3c1a2e-.../detalle               → /pacientes/[scrubbed]/detalle
//   /clinica/citas                                → /clinica/citas   (sin cambios)
export function scrubUrl(url: string): string {
  if (!url) return url

  // Separar #fragment y ?query manualmente (el constructor URL no acepta paths relativos).
  const hashIdx = url.indexOf('#')
  const hash = hashIdx >= 0 ? url.slice(hashIdx) : ''
  const sinHash = hashIdx >= 0 ? url.slice(0, hashIdx) : url

  const qIdx = sinHash.indexOf('?')
  const query = qIdx >= 0 ? sinHash.slice(qIdx + 1) : ''
  const base = qIdx >= 0 ? sinHash.slice(0, qIdx) : sinHash

  const scrubbedBase = base
    .split('/')
    .map((seg) => (NUM_RE.test(seg) || UUID_RE.test(seg) ? '[scrubbed]' : seg))
    .join('/')

  let scrubbedQuery = ''
  if (query) {
    scrubbedQuery =
      '?' +
      query
        .split('&')
        .map((pair) => {
          const eq = pair.indexOf('=')
          if (eq < 0) return pair // flag sin valor → se conserva el nombre
          return pair.slice(0, eq) + '=[scrubbed]'
        })
        .join('&')
  }

  return scrubbedBase + scrubbedQuery + hash
}

// Scrub in-place de las URLs conocidas dentro de un breadcrumb (navigation/fetch/xhr).
function scrubBreadcrumbUrls(data: Record<string, unknown> | undefined): void {
  if (!data) return
  if (typeof data.url === 'string') data.url = scrubUrl(data.url)
  if (typeof data.to === 'string') data.to = scrubUrl(data.to)
  if (typeof data.from === 'string') data.from = scrubUrl(data.from)
}

function beforeSend(event: Sentry.ErrorEvent): Sentry.ErrorEvent | null {
  // Chunk obsoleto tras deploy → no es un bug reportable, se descarta.
  const msg =
    event.exception?.values?.map((v) => v?.value ?? '').join(' ') ?? event.message ?? ''
  if (esChunkError(msg)) return null

  if (event.request?.url) event.request.url = scrubUrl(event.request.url)

  // Nunca enviar identidad del usuario.
  delete event.user

  event.breadcrumbs?.forEach((bc) => scrubBreadcrumbUrls(bc.data))

  return event
}

// Scrub también en el origen, para que ningún breadcrump guarde una URL con PHI aunque
// después no llegue a beforeSend (p.ej. si se envía en otro evento).
function beforeBreadcrumb(breadcrumb: Sentry.Breadcrumb): Sentry.Breadcrumb | null {
  scrubBreadcrumbUrls(breadcrumb.data)
  return breadcrumb
}

export function initSentry(): void {
  const dsn = import.meta.env.VITE_SENTRY_DSN
  // Sin DSN (dev local / preview sin configurar) → no se inicializa nada.
  if (!dsn) return

  // environment: preferir la señal de Vercel si existe; si no, el modo de Vite.
  const environment = import.meta.env.VITE_VERCEL_ENV || import.meta.env.MODE

  Sentry.init({
    dsn,
    environment,
    sendDefaultPii: false,
    // integrations EXPLÍCITO: solo breadcrumbs con console:false. NO browserTracing, NO replay.
    // Al pasar breadcrumbsIntegration por nombre, reemplaza la default (que trae console:true).
    integrations: [Sentry.breadcrumbsIntegration({ console: false })],
    beforeSend,
    beforeBreadcrumb,
  })
}
