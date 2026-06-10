/// <reference lib="WebWorker" />
/// <reference types="vite-plugin-pwa/client" />

import {
  precacheAndRoute,
  cleanupOutdatedCaches,
  matchPrecache,
} from 'workbox-precaching'
import { registerRoute, NavigationRoute } from 'workbox-routing'
import { NetworkFirst } from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'
import { clientsClaim } from 'workbox-core'

declare const self: ServiceWorkerGlobalScope

// Precachear todos los assets del build (inyectados por vite-plugin-pwa)
precacheAndRoute(self.__WB_MANIFEST)

// Limpiar SOLO los precaches obsoletos de versiones anteriores.
// NUNCA borrar todos los caches a mano: eso destruye el precache recién creado.
cleanupOutdatedCaches()

// ============================================
// Navigation: NetworkFirst sobre el shell HTML
// Online -> siempre el index.html del último deploy (apunta al JS más reciente).
// Offline / red lenta -> cae al cache y, en última instancia, al precache.
// ============================================
const htmlStrategy = new NetworkFirst({
  cacheName: 'html-shell',
  networkTimeoutSeconds: 3,
  plugins: [
    new ExpirationPlugin({
      maxEntries: 1,
      maxAgeSeconds: 86400,
    }),
  ],
})

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
