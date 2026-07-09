import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

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

// Si un chunk lazy falla al cargar (deploy nuevo + un index/SW que apunta a chunks que ya no
// existen -> 404; o la variante MIME "text/html" del index servido como .js), recargar para
// traer el bundle consistente. Evita las pantallas en blanco al navegar a una ruta lazy.
const ES_CHUNK_ERROR = /dynamically imported module|Importing a module script failed|ChunkLoadError|Failed to load module script/i
function recargarPorChunkObsoleto() {
  // Contador (no throttle temporal): máximo 2 recargas por sesión. Si tras 2 recargas el chunk
  // sigue fallando, no recargar más → evita el loop infinito (blanco → reload → blanco).
  const KEY = 'chunk_reload_count'
  const n = Number(sessionStorage.getItem(KEY) || 0)
  if (n >= 2) {
    console.error('[PWA] chunk obsoleto persistente tras', n, 'recargas — no se recarga más (evita loop)')
    return
  }
  sessionStorage.setItem(KEY, String(n + 1))
  window.location.reload()
}
window.addEventListener('vite:preloadError', recargarPorChunkObsoleto)
window.addEventListener('error', (e) => {
  const msg = (e?.message || '') + ''
  if (ES_CHUNK_ERROR.test(msg)) recargarPorChunkObsoleto()
})
// Hueco real: un import() que falla RECHAZA una promesa; si nadie la captura, el listener de
// 'error' NO se dispara. Por eso escuchamos también 'unhandledrejection'.
window.addEventListener('unhandledrejection', (e) => {
  const msg = (e?.reason?.message || String(e?.reason) || '') + ''
  if (ES_CHUNK_ERROR.test(msg)) recargarPorChunkObsoleto()
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)