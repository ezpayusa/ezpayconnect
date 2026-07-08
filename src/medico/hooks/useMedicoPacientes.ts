import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Paciente } from '@/types'

export function useMedicoPacientes() {
  const [pacientes, setPacientes] = useState<Paciente[]>([])
  const [loading, setLoading] = useState(true)

  const fetchPacientes = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setPacientes([])
        setLoading(false)
        return
      }

      const { data, error } = await supabase
        .from('pacientes')
        .select('*')
        .eq('medico_id', user.id)
        .eq('activo', true)
        .order('created_at', { ascending: false })

      if (error) {
        console.error('Error cargando pacientes:', error?.message ?? error?.code)
        setPacientes([])
      } else {
        setPacientes(data || [])
      }
    } catch (err) {
      console.error('Error:', err?.message ?? err?.code)
      setPacientes([])
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchPacientes()
  }, [fetchPacientes])

  return { pacientes, loading, recargar: fetchPacientes }
}
