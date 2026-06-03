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

      const { data, error: err } = await supabase
        .from('examenes')
        .select(`
          id,
          tipo,
          descripcion,
          fecha_solicitud,
          fecha_resultado,
          estado,
          resultados,
          archivo_url,
          notas,
          created_at,
          perfiles!examenes_medico_id_fkey(nombre_completo)
        `)
        .eq('paciente_id', pacienteId)
        .order('fecha_solicitud', { ascending: false })

      if (err) {
        // Si la tabla no existe (error 42P01), no es fatal
        if (err.code === '42P01') {
          setExamenes([])
          return
        }
        throw err
      }

      const mapped: ExamenPaciente[] = (data || []).map((e: any) => ({
        id: e.id,
        tipo: e.tipo,
        fecha: e.fecha_solicitud,
        estado: e.estado,
        resultados: e.resultados,
        archivo_url: e.archivo_url,
        medico_nombre: e.perfiles?.nombre_completo || 'Médico asignado',
        notas: e.notas,
        created_at: e.created_at,
      }))

      setExamenes(mapped)
    } catch (err: any) {
      console.error('Error cargando examenes:', err)
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
