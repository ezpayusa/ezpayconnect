import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { HistorialMedico } from '@/types'

export function useHistorialMedico(pacienteId?: number) {
  const [historial, setHistorial] = useState<HistorialMedico[]>([])
  const [loading, setLoading] = useState(true)

  const fetchHistorial = useCallback(async () => {
    if (!pacienteId) {
      setHistorial([])
      setLoading(false)
      return
    }

    setLoading(true)
    const { data, error } = await supabase
      .from('historial_medico')
      .select('*')
      .eq('paciente_id', pacienteId)
      .order('fecha', { ascending: false })

    if (error) {
      console.error('Error fetching historial:', error)
    } else {
      setHistorial(data || [])
    }
    setLoading(false)
  }, [pacienteId])

  useEffect(() => { fetchHistorial() }, [fetchHistorial])

  const createHistorial = async (historialData: Partial<HistorialMedico>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesión' }

    if (!pacienteId) return { error: 'Paciente no especificado' }

    const { data, error } = await supabase.from('historial_medico').insert({
      paciente_id: pacienteId,
      fecha: historialData.fecha || new Date().toISOString().split('T')[0],
      motivo_consulta: historialData.motivo_consulta || null,
      diagnostico: historialData.diagnostico || null,
      tratamiento: historialData.tratamiento || null,
      notas_medicas: historialData.notas_medicas || null,
      examenes_solicitados: historialData.examenes_solicitados || null,
      medico_id: user.id
    }).select().single()

    if (!error && data) {
      setHistorial(prev => [data, ...prev])
    }

    return { data, error }
  }

  return { historial, loading, fetchHistorial, createHistorial }
}
