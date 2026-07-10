/// <reference lib="WebWorker" />
/// <reference types="vite-plugin-pwa/client" />

import {
  precacheAndRoute,
  cleanupOutdatedCaches,
  matchPrecache,
} from 'workbox-precaching'
import { registerRoute, NavigationRoute } from 'workbox-routing'
import { NetworkFirst, NetworkOnly } from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'
import { clientsClaim } from 'workbox-core'

declare const self: ServiceWorkerGlobalScope

// Precachear todos los assets del build (inyectados por vite-plugin-pwa)
precacheAndRoute(self.__WB_MANIFEST)

// Limpiar SOLO los precaches obsoletos de versiones anteriores.
// NUNCA borrar todos los caches a mano: eso destruye el precache recién creado.
cleanupOutdatedCaches()

// ============================================
// Navigation: NetworkOnly sobre el shell HTML (SIN cache runtime intermedia)
// Online -> siempre el index.html del último deploy (apunta al JS más reciente).
// Sin red / error -> NetworkOnly LANZA (no tiene cache a la que caer); el catch del
//   handler cae a matchPrecache('/index.html'), que pertenece a la MISMA versión del
//   SW que precacheó los chunks -> coherente por construcción.
//
// POR QUÉ se sacó la cache 'html-shell': era una cache RUNTIME que SOBREVIVE a los
// deploys (cleanupOutdatedCaches() solo limpia PRECACHES, no runtime caches). El SW
// podía servir un index.html rancio (de hasta 24h) que referenciaba chunks de un
// deploy viejo ya inexistentes -> 404 -> import() falla -> pantalla en blanco.
// NetworkOnly no cachea nada: o red fresca, o el precache coherente del deploy actual.
// ============================================
const htmlStrategy = new NetworkOnly()

const navigationRoute = new NavigationRoute(
  async (options) => {
    try {
      const res = await htmlStrategy.handle({
        ...options,
        request: new Request('/index.html'),
      })
      if (res) return res
    } catch {
      // cae al fallback de precache abajo
    }
    return (await matchPrecache('/index.html')) || Response.error()
  },
  {
    denylist: [
      /^\/api\//,
      /^\/.well-known/,
      /^\/supabase\/functions/,
    ],
  }
)
registerRoute(navigationRoute)

// Runtime caching para API de Supabase
registerRoute(
  /^https:\/\/.*\.supabase\.co\/.*$/i,
  new NetworkFirst({
    cacheName: 'supabase-api',
    plugins: [
      new ExpirationPlugin({
        maxEntries: 100,
        maxAgeSeconds: 86400,
      }),
    ],
  })
)

// ============================================
// Push Notifications
// ============================================
self.addEventListener('push', (event) => {
  if (!event.data) return

  let data: any
  try {
    data = event.data.json()
  } catch {
    data = {
      title: 'EzPayConnect',
      body: event.data.text(),
    }
  }

  const title = data.title || 'EzPayConnect'
  const options: NotificationOptions = {
    body: data.body || 'Tienes una nueva notificación',
    icon: '/icon-192x192.png',
    badge: '/icon-192x192.png',
    tag: data.tag || 'default',
    data: {
      url: data.url || '/paciente/dashboard',
      ...data,
    },
    requireInteraction: false,
    actions: data.actions || [],
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

// ============================================
// Notification Click
// ============================================
self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const notificationData = event.notification.data || {}
  const targetUrl = notificationData.url || '/paciente/dashboard'

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Si ya hay una ventana abierta, enfocarla y navegar
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            return (client as WindowClient).focus().then(() => {
              client.navigate(targetUrl)
            })
          }
        }
        // Si no, abrir nueva ventana
        return self.clients.openWindow(targetUrl)
      })
  )
})

// ============================================
// Ciclo de actualización: activar el SW nuevo de inmediato y tomar control.
// El reload de la página lo dispara workbox-window (evento `controlling`)
// gracias a registerType: "autoUpdate" en main.tsx.
// ============================================
self.skipWaiting()
clientsClaim()
