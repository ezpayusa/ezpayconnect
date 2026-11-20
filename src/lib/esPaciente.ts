import { supabase } from '@/lib/supabase'

// ¿La cuenta tiene ficha de paciente? Misma lectura que useWebAppAuth (pacientes por
// auth_user_id; la RLS de pacientes deja que el paciente lea su propia fila).
// Un error de la consulta se propaga: resolverRutaHome lo trata como "no es paciente".
export async function esPacienteDeUsuario(userId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('pacientes')
    .select('id')
    .eq('auth_user_id', userId)
    .maybeSingle()
  if (error) throw error
  return !!data
}
