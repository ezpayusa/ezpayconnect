import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import type { ChatMensaje } from '@/webapp/types/webapp.types'

export function useWebAppChat(pacienteId: number | undefined) {
  const [mensajes, setMensajes] = useState<ChatMensaje[]>([])
  const [medicoId, setMedicoId] = useState<string | null>(null)
  const [medicoNombre, setMedicoNombre] = useState<string>('Tu médico')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const channelRef = useRef<any>(null)

  // Obtener el medico_id del paciente (del perfil o de la última cita)
  const fetchMedico = useCallback(async () => {
    if (!pacienteId) return

    // 1. Intentar obtener medico_id del perfil del paciente
    const { data: pacienteData } = await supabase
      .from('pacientes')
      .select('medico_id')
      .eq('id', pacienteId)
      .single()

    let mid = pacienteData?.medico_id

    // 2. Si no tiene, buscar el médico de la última cita
    if (!mid) {
      const { data: citaData } = await supabase
        .from('citas')
        .select('medico_id')
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: false })
        .limit(1)
        .single()

      mid = citaData?.medico_id
    }

    if (mid) {
      // Verificar que el médico realmente existe en perfiles
      const { data: perfilData } = await supabase
        .from('perfiles')
        .select('nombre_completo')
        .eq('id', mid)
        .single()

      if (perfilData) {
        setMedicoId(mid)
        setMedicoNombre(perfilData.nombre_completo || 'Tu médico')
      }
    }
  }, [pacienteId])

  const fetchMensajes = useCallback(async () => {
    if (!pacienteId) {
      setMensajes([])
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      const { data, error: err } = await supabase
        .from('chat_mensajes')
        .select('*')
        .eq('paciente_id', pacienteId)
        .order('created_at', { ascending: true })

      if (err) {
        if (err.code === '42P01') {
          setMensajes([])
          return
        }
        throw err
      }

      const mapped: ChatMensaje[] = (data || []).map((m: any) => ({
        id: m.id,
        remitente: m.remitente,
        mensaje: m.mensaje,
        leido: m.leido,
        created_at: m.created_at,
      }))

      setMensajes(mapped)

      // Marcar mensajes del médico como leídos
      await marcarComoLeidos()
    } catch (err: any) {
      console.error('Error cargando mensajes:', err)
      setError(err.message || 'Error al cargar mensajes')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  const marcarComoLeidos = useCallback(async () => {
    if (!pacienteId) return
    await supabase
      .from('chat_mensajes')
      .update({ leido: true })
      .eq('paciente_id', pacienteId)
      .eq('remitente', 'medico')
      .eq('leido', false)
  }, [pacienteId])

  const enviarMensaje = useCallback(async (texto: string) => {
    if (!pacienteId || !texto.trim()) return

    try {
      setEnviando(true)
      setError(null)
      const insertData: any = {
        paciente_id: pacienteId,
        remitente: 'paciente',
        mensaje: texto.trim(),
        leido: false,
      }
      // Solo incluir medico_id si existe y es válido
      if (medicoId) {
        insertData.medico_id = medicoId
      }

      const { error: err } = await supabase.from('chat_mensajes').insert(insertData)

      if (err) throw err
    } catch (err: any) {
      console.error('Error enviando mensaje:', err)
      setError(err.message || 'Error al enviar mensaje')
    } finally {
      setEnviando(false)
    }
  }, [pacienteId, medicoId])

  useEffect(() => {
    fetchMedico()
  }, [fetchMedico])

  useEffect(() => {
    fetchMensajes()
  }, [fetchMensajes])

  // Suscripción en tiempo real a nuevos mensajes
  useEffect(() => {
    if (!pacienteId) return

    const channel = supabase
      .channel(`chat_paciente_${pacienteId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'chat_mensajes',
          filter: `paciente_id=eq.${pacienteId}`,
        },
        (payload) => {
          if (payload.eventType === 'INSERT') {
            const nuevo = payload.new as any
            setMensajes((prev) => {
              // Evitar duplicados
              if (prev.some((m) => m.id === nuevo.id)) return prev
              return [
                ...prev,
                {
                  id: nuevo.id,
                  remitente: nuevo.remitente,
                  mensaje: nuevo.mensaje,
                  leido: nuevo.leido,
                  created_at: nuevo.created_at,
                },
              ]
            })
            // Marcar como leído si es del médico
            if (nuevo.remitente === 'medico') {
              marcarComoLeidos()
            }
          }
        }
      )
      .subscribe()

    channelRef.current = channel

    return () => {
      channel.unsubscribe()
    }
  }, [pacienteId, marcarComoLeidos])

  return {
    mensajes,
    medicoId,
    medicoNombre,
    loading,
    error,
    enviando,
    enviarMensaje,
    refetch: fetchMensajes,
  }
}
