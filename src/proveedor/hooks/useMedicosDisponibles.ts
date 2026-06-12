import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import type { DisponibilidadMedico } from '@/proveedor/types/proveedor.types'

export interface MedicoResumen {
  id: string
  nombre_completo: string
  especialidad?: string
  email?: string
}

export function useMedicosDisponibles() {
  const [medicos, setMedicos] = useState<MedicoResumen[]>([])
  const [disponibilidad, setDisponibilidad] = useState<DisponibilidadMedico[]>([])
  const [loading, setLoading] = useState(false)

  const buscarMedicos = useCallback(async (query?: string) => {
    setLoading(true)
    const { data, error } = await supabase.rpc('buscar_medicos_proveedor', {
      p_query: query?.trim() || null,
    })

    if (error) {
      toast.error('Error buscando médicos')
      console.error(error)
    } else {
      setMedicos((data || []) as MedicoResumen[])
    }
    setLoading(false)
  }, [])

  const fetchDisponibilidadMedico = useCallback(async (medicoId: string) => {
    setLoading(true)
    const { data, error } = await supabase
      .from('disponibilidad_medico')
      .select('*')
      .eq('medico_id', medicoId)
      .eq('activo', true)
      .eq('contexto', 'visitador') // el visitador solo agenda en el horario de visitadores
      .order('dia_semana', { ascending: true })
      .order('hora_inicio', { ascending: true })

    if (error) {
      toast.error('Error cargando disponibilidad')
      console.error(error)
    } else {
      setDisponibilidad(data || [])
    }
    setLoading(false)
  }, [])

  return {
    medicos,
    disponibilidad,
    loading,
    buscarMedicos,
    fetchDisponibilidadMedico,
  }
}
