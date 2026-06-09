/// <reference lib="WebWorker" />
/// <reference types="vite-plugin-pwa/client" />

import { precacheAndRoute, createHandlerBoundToURL } from 'workbox-precaching'
import { registerRoute, NavigationRoute } from 'workbox-routing'
import { NetworkFirst } from 'workbox-strategies'
import { ExpirationPlugin } from 'workbox-expiration'

declare const self: ServiceWorkerGlobalScope

// Precachear todos los assets del build (inyectados por vite-plugin-pwa)
precacheAndRoute(self.__WB_MANIFEST)

// ============================================
// Navigation fallback: para que la SPA funcione al recargar cualquier ruta
// ============================================
const handler = createHandlerBoundToURL('/index.html')
const navigationRoute = new NavigationRoute(handler, {
  denylist: [
    /^\/api\//,
    /^\/.well-known/,
    /^\/supabase\/functions/,
  ],
})
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
// Install / Activate
// ============================================
self.addEventListener('install', () => {
  console.log('[SW] EzPayConnect v3 installed - 2025-06-08')
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})
