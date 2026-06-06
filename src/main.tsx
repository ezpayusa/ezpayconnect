import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

// Registro del Service Worker para PWA
import { registerSW } from 'virtual:pwa-register'

const updateSW = registerSW({
  immediate: true,
  onNeedRefresh() {
    // Auto-recarga tras 3s para evitar cache de versiones viejas
    console.log('[PWA] Nueva versión detectada. Recargando...')
    setTimeout(() => {
      updateSW(true)
    }, 3000)
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