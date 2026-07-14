import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { ErrorBoundary } from '@/components/ErrorBoundary'
import { AuthProvider } from '@/hooks/AuthContext'
import { esChunkError, recargarPorChunkObsoleto } from '@/lib/chunk-reload'

console.log('[BUILD] EzPayConnect v3.6 - 2026-06-10 (stubs core: config clinica, examenes, reportes)')

// Registro del Service Worker para PWA.
// registerType: "autoUpdate" -> workbox-window aplica el SW nuevo y recarga
// automáticamente la página (evento `controlling`). No usamos onNeedRefresh.
import { registerSW } from 'virtual:pwa-register'

registerSW({
  immediate: true,
  onRegisteredSW(swUrl, registration) {
    // Revisar si hay un deploy nuevo cada 60s, para pestañas abiertas mucho tiempo.
    if (registration) {
      setInterval(() => {
        registration.update().catch(() => {})
      }, 60_000)
    }
  },
  onOfflineReady() {
    console.log('[PWA] App lista para uso offline')
  },
})

// Listeners globales de chunk obsoleto (lógica única en @/lib/chunk-reload). Un import() que falla
// RECHAZA una promesa: si nadie la captura, el listener de 'error' NO se dispara → por eso además
// escuchamos 'unhandledrejection'. El ErrorBoundary usa la misma lógica/contador.
window.addEventListener('vite:preloadError', recargarPorChunkObsoleto)
window.addEventListener('error', (e) => {
  if (esChunkError(e?.message)) recargarPorChunkObsoleto()
})
window.addEventListener('unhandledrejection', (e) => {
  if (esChunkError(e?.reason?.message ?? e?.reason)) recargarPorChunkObsoleto()
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <AuthProvider>
        <App />
      </AuthProvider>
    </ErrorBoundary>
  </StrictMode>,
)