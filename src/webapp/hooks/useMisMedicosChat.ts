import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface MedicoChatItem {
  medico_id: string
  nombre_completo: string
  especialidad: string | null
  foto_url: string | null
  no_leidos: number
  ultimo_mensaje: string | null
  ultimo_at: string | null
}

/**
 * Bandeja del selector de chat del paciente: los médicos con relación real
 * (RPC DEFINER mis_medicos_chat, mig 258) + no_leidos/último mensaje por hilo,
 * calculados leyendo chat_mensajes por la policy SELECT del paciente.
 */
export function useMisMedicosChat(pacienteId: number | undefined) {
  const [medicos, setMedicos] = useState<MedicoChatItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)

      const { data: meds, error: errRpc } = await supabase.rpc('mis_medicos_chat')
      if (errRpc) throw errRpc

      // no_leidos + último mensaje por médico (una sola query; si falla, no rompe la lista)
      const stats: Record<string, { no_leidos: number; ultimo_mensaje: string | null; ultimo_at: string | null }> = {}
      if (pacienteId) {
        const { data: msgs } = await supabase
          .from('chat_mensajes')
          .select('medico_id, mensaje, created_at, remitente, leido')
          .eq('paciente_id', pacienteId)
          .order('created_at', { ascending: false })

        for (const m of (msgs || []) as any[]) {
          if (!m.medico_id) continue
          const s = stats[m.medico_id] ?? { no_leidos: 0, ultimo_mensaje: null, ultimo_at: null }
          // el primero que vemos (orden desc) es el último mensaje
          if (s.ultimo_at === null) {
            s.ultimo_mensaje = m.mensaje
            s.ultimo_at = m.created_at
          }
          if (m.remitente === 'medico' && m.leido === false) s.no_leidos += 1
          stats[m.medico_id] = s
        }
      }

      const enriquecidos: MedicoChatItem[] = ((meds || []) as any[]).map((med) => ({
        medico_id: med.medico_id,
        nombre_completo: med.nombre_completo,
        especialidad: med.especialidad ?? null,
        foto_url: med.foto_url ?? null,
        no_leidos: stats[med.medico_id]?.no_leidos ?? 0,
        ultimo_mensaje: stats[med.medico_id]?.ultimo_mensaje ?? null,
        ultimo_at: stats[med.medico_id]?.ultimo_at ?? null,
      }))

      setMedicos(enriquecidos)
    } catch (err: any) {
      console.error('Error cargando médicos del chat:', err?.message ?? err)
      setError(err?.message ?? 'No se pudieron cargar tus médicos')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  useEffect(() => {
    cargar()
  }, [cargar])

  return { medicos, loading, error, refetch: cargar }
}
