import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

// Topic único por instancia para no colisionar si el hook se monta dos veces.
let channelSeq = 0

export interface ClinicaNotif {
  id: string
  tipo: string
  titulo: string
  mensaje: string | null
  leida: boolean
  accion_url: string | null
  created_at: string
}

export function useClinicaNotificaciones() {
  const [notificaciones, setNotificaciones] = useState<ClinicaNotif[]>([])
  const [noLeidas, setNoLeidas] = useState(0)
  const [loading, setLoading] = useState(true)
  const [userId, setUserId] = useState<string | null>(null)

  const fetchNotificaciones = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setNotificaciones([])
        setNoLeidas(0)
        return
      }
      setUserId(user.id)

      const { data, error } = await supabase
        .from('notificaciones')
        .select('*')
        .eq('usuario_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50)

      if (error) throw error

      const list = (data || []) as ClinicaNotif[]
      setNotificaciones(list)
      setNoLeidas(list.filter((n) => !n.leida).length)
    } catch (err) {
      console.error('[ClinicaNotif] Error cargando notificaciones:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchNotificaciones()
  }, [fetchNotificaciones])

  // Realtime: nueva notificación aparece sin recargar
  useEffect(() => {
    if (!userId) return

    let channel: ReturnType<typeof supabase.channel> | null = null
    try {
      const topic = `clinica_notif_${userId}_${++channelSeq}`
      channel = supabase
        .channel(topic)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'notificaciones',
            filter: `usuario_id=eq.${userId}`,
          },
          (payload) => {
            const nuevo = payload.new as ClinicaNotif
            setNotificaciones((prev) =>
              prev.some((n) => n.id === nuevo.id) ? prev : [nuevo, ...prev]
            )
            setNoLeidas((prev) => prev + 1)
          }
        )
        .subscribe((status) => {
          console.log('[ClinicaNotif] Estado de suscripción realtime:', status)
        })
    } catch (e) {
      console.error('[ClinicaNotif] Error suscribiendo realtime:', e)
    }

    return () => {
      if (channel) supabase.removeChannel(channel).catch(() => {})
    }
  }, [userId])

  const marcarLeida = useCallback(async (id: string) => {
    const { error } = await supabase.from('notificaciones').update({ leida: true }).eq('id', id)
    if (error) return
    setNotificaciones((prev) => prev.map((n) => (n.id === id ? { ...n, leida: true } : n)))
    setNoLeidas((prev) => Math.max(0, prev - 1))
  }, [])

  const marcarTodasLeidas = useCallback(async () => {
    if (!userId) return
    const { error } = await supabase
      .from('notificaciones')
      .update({ leida: true })
      .eq('usuario_id', userId)
      .eq('leida', false)
    if (error) return
    setNotificaciones((prev) => prev.map((n) => ({ ...n, leida: true })))
    setNoLeidas(0)
  }, [userId])

  return { notificaciones, noLeidas, loading, marcarLeida, marcarTodasLeidas, refetch: fetchNotificaciones }
}
