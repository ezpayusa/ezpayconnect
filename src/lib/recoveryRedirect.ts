// Desvío del link de recuperación de contraseña a /set-password.
//
// Por qué existe: el link de recovery que no trae redirectTo (por ejemplo, el "Send password
// recovery" del dashboard de Supabase) vuelve a la raíz con #…type=recovery. Ningún listener de
// onAuthStateChange mira el evento (PASSWORD_RECOVERY), y RootRedirect mandaba directo al panel con
// la sesión ya abierta, sin pedir clave nueva (incidente 15-oct).
//
// ORDEN: este módulo tiene que importarse PRIMERO en main.tsx, antes de cualquier import que cree el
// cliente de Supabase: detectSessionInUrl lee la URL al inicializar el cliente, y el path tiene que
// estar reescrito antes de eso. recoveryRedirect.test.ts lo verifica.
//
// Solo reescribe el path (history.replaceState, sin recarga): el search y el hash con el token quedan
// intactos, y supabase-js los procesa ya en /set-password.

export function destinoRecovery(pathname: string, search: string, hash: string): string | null {
  const params = new URLSearchParams(hash.startsWith('#') ? hash.slice(1) : hash)
  if (params.get('type') !== 'recovery') return null
  if (pathname === '/set-password') return null
  return '/set-password' + search + hash
}

if (typeof window !== 'undefined') {
  const d = destinoRecovery(window.location.pathname, window.location.search, window.location.hash)
  if (d) window.history.replaceState(null, '', d)
}
