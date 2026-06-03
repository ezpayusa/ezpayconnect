import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { CitaPaciente } from '@/webapp/types/webapp.types'

export function useWebAppCitas(pacienteId: number | undefined) {
  const [citas, setCitas] = useState<CitaPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchCitas = useCallback(async () => {
    if (!pacienteId) {
      setCitas([])
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      // 1. Obtener citas del paciente (sin join, solo medico_id)
      const { data: citasData, error: citasErr } = await supabase
        .from('citas')
        .select('id, fecha, hora_inicio, hora_fin, motivo, estado, notas, created_at, medico_id')
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: true })

      if (citasErr) throw citasErr

      // 2. Obtener nombres de médicos por separado
      const medicoIds = [...new Set((citasData || []).map((c: any) => c.medico_id).filter(Boolean))]
      let medicosMap: Record<string, string> = {}

      if (medicoIds.length > 0) {
        const { data: perfilesData } = await supabase
          .from('perfiles')
          .select('id, nombre_completo')
          .in('id', medicoIds)

        medicosMap = (perfilesData || []).reduce((acc: Record<string, string>, p: any) => {
          acc[p.id] = p.nombre_completo
          return acc
        }, {})
      }

      const mapped: CitaPaciente[] = (citasData || []).map((c: any) => ({
        id: c.id,
        fecha: c.fecha,
        hora_inicio: c.hora_inicio,
        hora_fin: c.hora_fin,
        motivo: c.motivo,
        estado: c.estado as any,
        medico_nombre: medicosMap[c.medico_id] || 'Médico asignado',
        medico_especialidad: undefined,
        notas: c.notas,
        created_at: c.created_at,
      }))

      setCitas(mapped)
    } catch (err: any) {
      console.error('Error cargando citas:', err)
      setError(err.message || 'Error al cargar citas')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  useEffect(() => {
    fetchCitas()
  }, [fetchCitas])

  const proximas = citas.filter((c) =>
    ['agendada', 'confirmada', 'en_curso', 'pendiente'].includes(c.estado)
  )
  const pasadas = citas.filter((c) =>
    ['completada'].includes(c.estado)
  )
  const canceladas = citas.filter((c) =>
    ['cancelada', 'no_show'].includes(c.estado)
  )

  return { citas, proximas, pasadas, canceladas, loading, error, refetch: fetchCitas }
}
