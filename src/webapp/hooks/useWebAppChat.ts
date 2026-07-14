import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import type { ChatMensaje } from '@/webapp/types/webapp.types'

/**
 * Chat del paciente con UN médico ELEGIDO. El hilo es el par (pacienteId, medicoId).
 * El médico ya no se resuelve adentro: el padre pasa el medicoId seleccionado (bandeja
 * mis_medicos_chat). Si medicoId es null → no hay hilo abierto (mensajes vacíos).
 */
export function useWebAppChat(pacienteId: number | undefined, medicoId: string | null) {
  const [mensajes, setMensajes] = useState<ChatMensaje[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const channelRef = useRef<any>(null)

  // Marca leídos SOLO los mensajes del médico de ESTE hilo.
  const marcarComoLeidos = useCallback(async () => {
    if (!pacienteId || !medicoId) return
    await supabase
      .from('chat_mensajes')
      .update({ leido: true })
      .eq('paciente_id', pacienteId)
      .eq('medico_id', medicoId)
      .eq('remitente', 'medico')
      .eq('leido', false)
  }, [pacienteId, medicoId])

  const fetchMensajes = useCallback(async () => {
    // Sin paciente o sin médico elegido → no hay hilo que cargar.
    if (!pacienteId || !medicoId) {
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
        .eq('medico_id', medicoId)
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
      await marcarComoLeidos()
    } catch (err: any) {
      console.error('Error cargando mensajes:', err)
      setError(err.message || 'Error al cargar mensajes')
    } finally {
      setLoading(false)
    }
  }, [pacienteId, medicoId, marcarComoLeidos])

  const enviarMensaje = useCallback(async (texto: string) => {
    if (!pacienteId || !medicoId || !texto.trim()) return

    try {
      setEnviando(true)
      setError(null)

      // El paciente inserta DIRECTO: la policy INSERT (mig 135) gatea remitente='paciente' + relación.
      const { data: nuevoMsg, error: err } = await supabase
        .from('chat_mensajes')
        .insert({
          paciente_id: pacienteId,
          medico_id: medicoId,
          remitente: 'paciente',
          mensaje: texto.trim(),
          leido: false,
        })
        .select('id')
        .single()

      if (err) throw err

      // Notificación server-side gateada (in-app + web-push al médico), sin texto crudo. Best-effort.
      if (nuevoMsg?.id) {
        try {
          await supabase.rpc('notificar_chat', { p_mensaje_id: nuevoMsg.id })
        } catch (notifErr) {
          console.error('Error notificar_chat:', notifErr)
        }
      }
    } catch (err: any) {
      console.error('Error enviando mensaje:', err)
      setError(err.message || 'Error al enviar mensaje')
    } finally {
      setEnviando(false)
    }
  }, [pacienteId, medicoId])

  useEffect(() => {
    fetchMensajes()
  }, [fetchMensajes])

  // Realtime: nuevos mensajes de ESTE hilo (paciente + médico elegido).
  useEffect(() => {
    if (!pacienteId || !medicoId) return

    const channel = supabase
      .channel(`chat_paciente_${pacienteId}_${medicoId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'chat_mensajes' },
        (payload) => {
          const nuevo = payload.new as any
          // Solo mensajes de este hilo (paciente + médico elegido).
          if (nuevo.paciente_id !== pacienteId || nuevo.medico_id !== medicoId) return

          setMensajes((prev) => {
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
          if (nuevo.remitente === 'medico') {
            marcarComoLeidos()
          }
        }
      )
      .subscribe()

    channelRef.current = channel

    return () => {
      channel.unsubscribe()
    }
  }, [pacienteId, medicoId, marcarComoLeidos])

  return {
    mensajes,
    loading,
    error,
    enviando,
    enviarMensaje,
    refetch: fetchMensajes,
  }
}
