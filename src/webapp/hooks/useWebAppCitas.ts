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

      const { data, error: err } = await supabase
        .from('citas')
        .select(`
          id,
          fecha,
          hora_inicio,
          hora_fin,
          motivo,
          estado,
          notas,
          created_at,
          perfiles!citas_medico_id_fkey(nombre_completo)
        `)
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: true })

      if (err) throw err

      const mapped: CitaPaciente[] = (data || []).map((c: any) => ({
        id: c.id,
        fecha: c.fecha,
        hora_inicio: c.hora_inicio,
        hora_fin: c.hora_fin,
        motivo: c.motivo,
        estado: c.estado,
        medico_nombre: c.perfiles?.nombre_completo || 'Médico asignado',
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
    ['agendada', 'confirmada', 'en_curso'].includes(c.estado)
  )
  const pasadas = citas.filter((c) =>
    ['completada'].includes(c.estado)
  )
  const canceladas = citas.filter((c) =>
    c.estado === 'cancelada'
  )

  return { citas, proximas, pasadas, canceladas, loading, error, refetch: fetchCitas }
}
