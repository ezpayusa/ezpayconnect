import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { NotificacionPaciente } from '@/webapp/types/webapp.types'

export function useWebAppNotificaciones(pacienteId: number | undefined) {
  const [notificaciones, setNotificaciones] = useState<NotificacionPaciente[]>([])
  const [noLeidas, setNoLeidas] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchNotificaciones = useCallback(async () => {
    if (!pacienteId) {
      setNotificaciones([])
      setNoLeidas(0)
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      const { data, error: err } = await supabase
        .from('notificaciones_pacientes')
        .select('*')
        .eq('paciente_id', pacienteId)
        .order('created_at', { ascending: false })
        .limit(50)

      if (err) {
        if (err.code === '42P01') {
          setNotificaciones([])
          setNoLeidas(0)
          return
        }
        throw err
      }

      const mapped: NotificacionPaciente[] = (data || []).map((n: any) => ({
        id: n.id,
        tipo: n.tipo,
        titulo: n.titulo,
        mensaje: n.mensaje,
        leida: n.leida,
        accion_url: n.accion_url,
        created_at: n.created_at,
      }))

      setNotificaciones(mapped)
      setNoLeidas(mapped.filter((n) => !n.leida).length)
    } catch (err: any) {
      console.error('Error cargando notificaciones:', err)
      setError(err.message || 'Error al cargar notificaciones')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  const marcarComoLeida = useCallback(async (id: number) => {
    if (!pacienteId) return

    const { error: err } = await supabase
      .from('notificaciones_pacientes')
      .update({ leida: true })
      .eq('id', id)
      .eq('paciente_id', pacienteId)

    if (err) {
      console.error('Error marcando notificación:', err)
      return
    }

    setNotificaciones((prev) =>
      prev.map((n) => (n.id === id ? { ...n, leida: true } : n))
    )
    setNoLeidas((prev) => Math.max(0, prev - 1))
  }, [pacienteId])

  const marcarTodasComoLeidas = useCallback(async () => {
    if (!pacienteId) return

    const { error: err } = await supabase
      .from('notificaciones_pacientes')
      .update({ leida: true })
      .eq('paciente_id', pacienteId)
      .eq('leida', false)

    if (err) {
      console.error('Error marcando notificaciones:', err)
      return
    }

    setNotificaciones((prev) => prev.map((n) => ({ ...n, leida: true })))
    setNoLeidas(0)
  }, [pacienteId])

  useEffect(() => {
    fetchNotificaciones()
  }, [fetchNotificaciones])

  // Suscripción en tiempo real
  useEffect(() => {
    if (!pacienteId) return

    let channel: ReturnType<typeof supabase.channel> | null = null

    const setup = async () => {
      // Autenticar la conexión realtime con el JWT del usuario para que el RLS
      // de notificaciones_pacientes permita recibir los eventos del paciente.
      const { data: { session } } = await supabase.auth.getSession()
      if (session?.access_token) {
        supabase.realtime.setAuth(session.access_token)
      }

      channel = supabase
        .channel(`notif_paciente_${pacienteId}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'notificaciones_pacientes',
            filter: `paciente_id=eq.${pacienteId}`,
          },
          (payload) => {
            const nuevo = payload.new as any
            setNotificaciones((prev) => {
              if (prev.some((n) => n.id === nuevo.id)) return prev
              const nuevaNotif: NotificacionPaciente = {
                id: nuevo.id,
                tipo: nuevo.tipo,
                titulo: nuevo.titulo,
                mensaje: nuevo.mensaje,
                leida: nuevo.leida,
                accion_url: nuevo.accion_url,
                created_at: nuevo.created_at,
              }
              return [nuevaNotif, ...prev]
            })
            setNoLeidas((prev) => prev + 1)
          }
        )
        .subscribe((status) => {
          console.log('[Notif] Estado de suscripción realtime:', status)
        })
    }

    setup()

    return () => {
      if (channel) supabase.removeChannel(channel).catch(() => {})
    }
  }, [pacienteId])

  return {
    notificaciones,
    noLeidas,
    loading,
    error,
    marcarComoLeida,
    marcarTodasComoLeidas,
    refetch: fetchNotificaciones,
  }
}
