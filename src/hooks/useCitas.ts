import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'
import type { Cita } from '@/types'

export function useCitas(opts?: { autoFetch?: boolean }) {
  const autoFetch = opts?.autoFetch ?? true
  const [citas, setCitas] = useState<Cita[]>([])
  const [loading, setLoading] = useState(true)
  const { paisId } = usePaisFiltro()

  const fetchCitas = useCallback(async () => {
    setLoading(true)
    let query = supabase
      .from('citas')
      .select('*')
      .order('fecha', { ascending: true })
    if (paisId) query = query.eq('pais_id', paisId)
    const { data } = await query
    setCitas(data || [])
    setLoading(false)
  }, [paisId])

  useEffect(() => { if (autoFetch) fetchCitas() }, [fetchCitas, autoFetch])

  const createCita = async (cita: Partial<Cita>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear citas' }
    
    if (!cita.paciente_id || !cita.fecha || !cita.hora_inicio) {
      return { error: 'Paciente, fecha y hora son requeridos' }
    }
    
    // Crear vía RPC SECURITY DEFINER (valida autorización del caller).
    const { data: nuevoId, error } = await supabase.rpc('crear_cita', {
      p_paciente_id: cita.paciente_id,
      p_medico_id: user.id,
      p_fecha: cita.fecha,
      p_hora_inicio: cita.hora_inicio,
      p_hora_fin: cita.hora_fin || null,
      p_motivo: cita.motivo || null,
      p_notas: cita.notas || null,
      p_estado: cita.estado || 'agendada',
      p_pais_id: paisId,
    })

    if (error) {
      console.error('Error creating cita:', error)
      return { data: null, error: `Error: ${error.message} (${error.code})` }
    }

    // La RPC devuelve solo el id → recuperar la fila creada
    const { data } = await supabase.from('citas').select('*').eq('id', nuevoId).single()

    // Programar recordatorio automático 24h antes
    try {
      await supabase.functions.invoke('programar-recordatorio', {
        body: {
          tipo: 'cita',
          referencia_id: nuevoId,
          horas_antes: 24,
        },
      })
    } catch (recErr) {
      console.error('Error programando recordatorio:', recErr)
    }

    if (data) setCitas(prev => [...prev, data])
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
