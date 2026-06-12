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

// Si un chunk lazy falla al cargar (deploy nuevo + Service Worker con un index
// viejo que apunta a chunks que ya no existen), recargar UNA vez para traer el
// bundle consistente. Evita las pantallas en blanco al navegar a una ruta lazy.
function recargarPorChunkObsoleto() {
  const ultima = Number(sessionStorage.getItem('chunk_reload_ts') || 0)
  if (Date.now() - ultima > 10_000) {
    sessionStorage.setItem('chunk_reload_ts', String(Date.now()))
    window.location.reload()
  }
}
window.addEventListener('vite:preloadError', recargarPorChunkObsoleto)
window.addEventListener('error', (e) => {
  const msg = (e?.message || '') + ''
  if (/dynamically imported module|Importing a module script failed|ChunkLoadError/i.test(msg)) {
    recargarPorChunkObsoleto()
  }
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)