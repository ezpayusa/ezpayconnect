import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

console.log('[BUILD] EzPayConnect v3.4 - 2026-06-10 (cancelar cita paciente)')

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

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)