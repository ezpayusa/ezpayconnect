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

      // 1. Obtener citas del paciente (con clinica_id restaurado)
      const citasRes = await supabase
        .from('citas')
        .select('id, fecha, hora_inicio, hora_fin, motivo, estado, notas, created_at, medico_id, clinica_id')
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: true })

      const { data: citasData, error: citasErr } = citasRes
      if (citasErr) throw citasErr

      // 2. Obtener nombres de médicos por separado (tabla medicos primero, fallback perfiles)
      const medicoIds = [...new Set((citasData || []).map((c: any) => c.medico_id).filter(Boolean))]
      let medicosMap: Record<string, { nombre: string; especialidad?: string }> = {}

      if (medicoIds.length > 0) {
        // Usar RPC para bypass PostgREST schema cache
        const { data: medsNuevos } = await supabase
          .rpc('obtener_medicos_por_ids', { p_medico_ids: medicoIds })

        const { data: medsViejos } = await supabase
          .from('perfiles')
          .select('id, nombre_completo')
          .in('id', medicoIds)
          .eq('rol', 'medico')

        const medsNuevosMap = new Map((medsNuevos || []).map((m: any) => [m.id, m]))
        const medsViejosMap = new Map((medsViejos || []).map((m: any) => [m.id, m]))

        medicoIds.forEach((id: string) => {
          const m = medsNuevosMap.get(id) || medsViejosMap.get(id)
          if (m) {
            medicosMap[id] = { nombre: m.nombre_completo, especialidad: m.especialidad }
          }
        })
      }

      // 3. Obtener nombres de clínicas por separado
      const clinicaIds = [...new Set((citasData || []).map((c: any) => c.clinica_id).filter(Boolean))]
      let clinicasMap: Record<number, string> = {}

      if (clinicaIds.length > 0) {
        const { data: clinicsData } = await supabase
          .from('clinicas')
          .select('id, nombre')
          .in('id', clinicaIds)

        clinicasMap = (clinicsData || []).reduce((acc: Record<number, string>, c: any) => {
          acc[c.id] = c.nombre
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
        medico_nombre: c.medico_id ? (medicosMap[c.medico_id]?.nombre || 'Médico asignado') : 'Médico por asignar',
        medico_especialidad: c.medico_id ? medicosMap[c.medico_id]?.especialidad : undefined,
        clinica_nombre: c.clinica_id ? clinicasMap[c.clinica_id] : undefined,
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
    ['solicitada', 'agendada', 'confirmada', 'en_curso', 'pendiente'].includes(c.estado)
  )
  const pasadas = citas.filter((c) =>
    ['completada'].includes(c.estado)
  )
  const canceladas = citas.filter((c) =>
    ['cancelada', 'no_show'].includes(c.estado)
  )

  return { citas, proximas, pasadas, canceladas, loading, error, refetch: fetchCitas }
}
