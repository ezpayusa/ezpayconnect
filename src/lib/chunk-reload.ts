// Recarga controlada ante un chunk lazy obsoleto: tras un deploy nuevo, el índice/SW puede apuntar
// a chunks que ya no existen (404) o el índice servirse como .js con MIME "text/html". Fuente ÚNICA
// usada por los listeners globales (main.tsx) y por el ErrorBoundary.
//
// Contador en sessionStorage (NO throttle temporal): máximo 2 recargas por sesión. Si tras 2
// recargas el chunk sigue fallando, no se recarga más → evita el loop infinito (blanco → reload).

export const ES_CHUNK_ERROR =
  /dynamically imported module|Importing a module script failed|ChunkLoadError|Failed to load module script/i

export function esChunkError(msg: unknown): boolean {
  return ES_CHUNK_ERROR.test(String(msg ?? ''))
}

const RELOAD_KEY = 'chunk_reload_count'
const MAX_RELOADS = 2

export function recargarPorChunkObsoleto(): void {
  const n = Number(sessionStorage.getItem(RELOAD_KEY) || 0)
  if (n >= MAX_RELOADS) {
    console.error(`[PWA] chunk obsoleto persistente tras ${n} recargas — no se recarga más (evita loop)`)
    return
  }
  sessionStorage.setItem(RELOAD_KEY, String(n + 1))
  window.location.reload()
}
