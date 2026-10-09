import { supabase } from '@/lib/supabase'

// ¿La sesión actual es de un paciente? Lo usan RootRedirect y LoginPage cuando la cuenta no tiene fila en perfiles:
// el paciente vive en `pacientes` (la crea handle_new_paciente en el signUp), no en perfiles, y sin esto caía en
// /sin-panel. Solo por auth_user_id (policy "Paciente ve su perfil": auth_user_id = auth.uid()), sin fallback por email.
// Nunca lanza: ante un error o sin fila devuelve false (el destino de siempre). Log sin datos del usuario: solo el código.
export async function esPacienteActual(uid: string): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from('pacientes')
      .select('id')
      .eq('auth_user_id', uid)
      .limit(1)
      .maybeSingle()
    if (error) {
      console.error('[esPaciente] no se pudo verificar si la cuenta es de paciente', error.code ?? null)
      return false
    }
    return !!data
  } catch (err) {
    console.error('[esPaciente] no se pudo verificar si la cuenta es de paciente', (err as { code?: string } | null)?.code ?? null)
    return false
  }
}
