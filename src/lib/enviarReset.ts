import { supabase } from '@/lib/supabase'
import { APP_URL } from '@/lib/app-url'

// Envía el correo de restablecimiento de contraseña.
// `next` = ruta interna del portal a la que volver luego de setear la clave (la lee SetPasswordPage).
export async function enviarReset(email: string, next: string) {
  const redirectTo = `${APP_URL}/set-password?next=${encodeURIComponent(next)}`
  return supabase.auth.resetPasswordForEmail(email, { redirectTo })
}
