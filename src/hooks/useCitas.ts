import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Cita } from '@/types'

export function useCitas() {
  const [citas, setCitas] = useState<Cita[]>([])
  const [loading, setLoading] = useState(true)

  const fetchCitas = useCallback(async () => {
    setLoading(true)
    const { data } = await supabase
      .from('citas')
      .select('*')
      .order('fecha', { ascending: true })
    setCitas(data || [])
    setLoading(false)
  }, [])

  useEffect(() => { fetchCitas() }, [fetchCitas])

  const createCita = async (cita: Partial<Cita>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear citas' }
    
    if (!cita.paciente_id || !cita.fecha || !cita.hora_inicio) {
      return { error: 'Paciente, fecha y hora son requeridos' }
    }
    
    const { data, error } = await supabase.from('citas').insert({
      paciente_id: cita.paciente_id,
      fecha: cita.fecha,
      hora_inicio: cita.hora_inicio,
      hora_fin: cita.hora_fin || null,
      motivo: cita.motivo || null,
      notas: cita.notas || null,
      estado: cita.estado || 'agendada',
      medico_id: user.id,
     }).select().single()
    
    if (error) {
      console.error('Error creating cita:', error)
      return { data: null, error: `Error: ${error.message} (${error.code})` }
    }
    
    setCitas(prev => [...prev, data])
    return { data, error: null }
  }

  const updateCita = async (id: number, updates: Partial<Cita>) => {
    const { data, error } = await supabase.from('citas').update(updates).eq('id', id).select().single()
    if (!error && data) setCitas(prev => prev.map(c => c.id === id ? data : c))
    return { data, error }
  }

  const deleteCita = async (id: number) => {
    const { error } = await supabase.from('citas').delete().eq('id', id)
    if (!error) setCitas(prev => prev.filter(c => c.id !== id))
    return { error }
  }

  return { citas, loading, fetchCitas, createCita, updateCita, deleteCita }
}
