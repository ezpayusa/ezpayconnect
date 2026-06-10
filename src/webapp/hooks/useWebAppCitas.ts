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
        .select('id, fecha, hora_inicio, hora_fin, motivo, estado, notas, motivo_cancelacion, created_at, medico_id, clinica_id')
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
        motivo_cancelacion: c.motivo_cancelacion,
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

  // Cancelar una cita (con motivo) y avisar a la clínica + médico
  const cancelarCita = useCallback(
    async (citaId: number, motivo: string, pacienteNombre?: string) => {
      // 1. Cancelar vía RPC seguro (solo cancela citas del propio paciente)
      const { data, error: err } = await supabase.rpc('cancelar_cita_paciente', {
        p_cita_id: citaId,
        p_motivo: motivo,
      })
      if (err) {
        console.error('Error cancelando cita:', err)
        return { ok: false as const, error: err.message }
      }

      const row = (Array.isArray(data) ? data[0] : data) as
        | { medico_id: string | null; clinica_id: string | null }
        | undefined
      const medicoId = row?.medico_id || undefined
      const clinicaId = row?.clinica_id || undefined

      // 2. Construir mensaje con el motivo
      const cita = citas.find((c) => c.id === citaId)
      const fechaStr = cita
        ? new Date(cita.fecha).toLocaleDateString('es-GT', { weekday: 'long', month: 'long', day: 'numeric' })
        : ''
      const titulo = 'Cita cancelada por el paciente'
      const mensaje = `${pacienteNombre || 'Un paciente'} canceló su cita${fechaStr ? ' del ' + fechaStr : ''}${
        cita?.hora_inicio ? ' a las ' + cita.hora_inicio.slice(0, 5) : ''
      }. Motivo: ${motivo}`

      // 3. Destinatarios:
      //    - in-app: SOLO admins de la clínica (vienen de perfiles -> son auth users).
      //      El medico_id de la cita puede ser de la tabla 'medicos' y NO un auth user,
      //      lo que rompe enviar-notificacion (FK a auth.users -> error 500).
      //    - push: médico + admins (enviar-push degrada sin error si no hay suscripción).
      const adminIds: string[] = []
      if (clinicaId) {
        const { data: admins } = await supabase.rpc('obtener_admins_clinica', { p_clinica_id: clinicaId })
        for (const a of (admins || []) as { user_id: string }[]) adminIds.push(a.user_id)
      }
      const inAppIds = [...new Set(adminIds)]
      const pushIds = [...new Set([...(medicoId ? [medicoId] : []), ...adminIds])]

      // 4. Notificar (best-effort; no falla la cancelación)
      for (const uid of inAppIds) {
        try {
          await supabase.functions.invoke('enviar-notificacion', {
            body: {
              usuario_id: uid,
              tipo: 'cita_cancelada',
              titulo,
              mensaje,
              accion_url: '/clinica/citas',
              metadata: { cita_id: citaId, motivo_cancelacion: motivo },
            },
          })
        } catch (e) {
          console.error('Error notificación in-app cancelación:', e)
        }
      }
      if (pushIds.length > 0) {
        try {
          await supabase.functions.invoke('enviar-push', {
            body: { usuario_ids: pushIds, titulo, mensaje, url: '/clinica/citas', tag: `cita-${citaId}` },
          })
        } catch (e) {
          console.error('Error push cancelación:', e)
        }
      }

      await fetchCitas()
      return { ok: true as const }
    },
    [citas, fetchCitas]
  )

  const proximas = citas.filter((c) =>
    ['solicitada', 'agendada', 'confirmada', 'en_curso'].includes(c.estado)
  )
  const pasadas = citas.filter((c) =>
    ['completada'].includes(c.estado)
  )
  const canceladas = citas.filter((c) =>
    ['cancelada', 'no_show'].includes(c.estado)
  )

  return { citas, proximas, pasadas, canceladas, loading, error, refetch: fetchCitas, cancelarCita }
}
