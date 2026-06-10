import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

interface ClinicaData {
  id: string
  nombre: string
  direccion: string | null
  telefono: string | null
  email: string | null
  activa: boolean
  pais_id: string | null
}

interface ClinicaUser {
  id: string
  nombre_completo: string
  email: string
  rol: string
  clinica_id: string | null
}

export function useClinicaAuth() {
  const [clinica, setClinica] = useState<ClinicaData | null>(null)
  const [loading, setLoading] = useState(true)
  const [isAdminClinica, setIsAdminClinica] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const cargarClinica = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      // 1. Obtener perfil (informativo: marca si es admin de clínica)
      const { data: perfil } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', user.id)
        .single()

      setIsAdminClinica(perfil?.rol === 'admin_clinica')

      // 2. Buscar clínica asociada al usuario via RPC.
      //    Puede devolver varias filas; tomar la primera. No usar .maybeSingle()
      //    porque lanza error si el usuario tiene más de una clínica asociada.
      //    No bloqueamos por rol: la autorización la da el propio RPC
      //    (SECURITY DEFINER, acotado al usuario), igual que en el panel de Citas.
      const { data: rels } = await supabase
        .rpc('obtener_clinica_usuario', { p_user_id: user.id })
      const rel = Array.isArray(rels) ? rels[0] : rels

      if (!rel?.clinica_id) {
        setError('No se encontró clínica asociada a este usuario')
        setLoading(false)
        return
      }

      // 3. Cargar datos de la clínica
      const { data: clinicaData } = await supabase
        .from('clinicas')
        .select('*')
        .eq('id', rel.clinica_id)
        .single()

      if (clinicaData) {
        setClinica(clinicaData)
      } else {
        setError('No se pudo cargar la información de la clínica')
      }
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    cargarClinica()
  }, [cargarClinica])

  return { clinica, loading, isAdminClinica, error, recargar: cargarClinica }
}
