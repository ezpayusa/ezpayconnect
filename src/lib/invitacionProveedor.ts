import { supabase } from '@/lib/supabase'

// Token de invitación de proveedor pendiente de aceptar tras login.
// El consumo real (aceptar_invitacion_proveedor) corre AUTENTICADO y ata la
// membresía a auth.uid() + email verificado; aquí solo persistimos el token a
// través del round-trip de confirmación de email + login.
const KEY = 'invitacion_proveedor_token'

export function guardarTokenInvitacion(token: string) {
  try { localStorage.setItem(KEY, token) } catch { /* noop */ }
}

export function limpiarTokenInvitacion() {
  try { localStorage.removeItem(KEY) } catch { /* noop */ }
}

// Llamar tras un login exitoso. Si hay token pendiente, lo acepta vía RPC
// autenticado. Devuelve true si creó la membresía (para re-rutear por tipo).
export async function aceptarInvitacionPendiente(): Promise<boolean> {
  let token: string | null = null
  try { token = localStorage.getItem(KEY) } catch { token = null }
  if (!token) return false
  const { error } = await supabase.rpc('aceptar_invitacion_proveedor', { p_token: token })
  limpiarTokenInvitacion()  // no reintentar en bucle (éxito, ya-tiene-cuenta o token usado)
  if (error) {
    console.warn('[aceptarInvitacionPendiente]', error.message)
    return false
  }
  return true
}
