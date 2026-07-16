import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { ExamenPaciente } from '@/webapp/types/webapp.types'

export function useWebAppExamenes(pacienteId: number | undefined) {
  const [examenes, setExamenes] = useState<ExamenPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchExamenes = useCallback(async () => {
    if (!pacienteId) {
      setExamenes([])
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      const { data, error: err } = await supabase.rpc('paciente_examenes')
      if (err) throw err
      const mapped: ExamenPaciente[] = (data || []).map((e: any) => ({
        id: e.id,
        tipo: e.tipo,
        fecha: e.fecha_solicitud,
        estado: e.estado,
        resultados: e.resultados,
        archivo_url: e.archivo_url,
        medico_nombre: e.medico_nombre || 'Médico asignado',
        notas: e.notas,
        created_at: e.created_at,
        en_revision: e.en_revision,
      }))
      setExamenes(mapped)
    } catch (err: any) {
      console.error('Error cargando examenes:', err?.message ?? err?.code)
      setError(err.message || 'Error al cargar exámenes')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  useEffect(() => {
    fetchExamenes()
  }, [fetchExamenes])

  const pendientes = examenes.filter((e) => e.estado === 'pendiente')

  return { examenes, pendientes, loading, error, refetch: fetchExamenes }
}
