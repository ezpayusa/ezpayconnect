import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

interface ClinicaData {
  id: number
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
  clinica_id: number | null
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

      // 1. Obtener perfil
      const { data: perfil } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', user.id)
        .single()

      if (!perfil || perfil.rol !== 'admin_clinica') {
        setIsAdminClinica(false)
        setLoading(false)
        return
      }

      setIsAdminClinica(true)

      // 2. Buscar clínica asociada al usuario (por es_principal en medico_clinicas)
      const { data: rel } = await supabase
        .from('medico_clinicas')
        .select('clinica_id')
        .eq('medico_id', user.id)
        .eq('es_principal', true)
        .limit(1)
        .single()

      if (!rel) {
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
