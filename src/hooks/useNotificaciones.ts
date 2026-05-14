import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface Notificacion {
  id: string
  doctor_id: string
  paciente_id?: string
  cita_id?: string
  tipo: 'email' | 'sms' | 'whatsapp' | 'in-app'
  categoria: string
  titulo: string
  mensaje: string
  estado: 'pendiente' | 'enviado' | 'leido' | 'error'
  email_destino?: string
  telefono_destino?: string
  enviado_en?: string
  leido_en?: string
  error_mensaje?: string
  metadata?: any
  created_at: string
}

export function useNotificaciones() {
  const [notificaciones, setNotificaciones] = useState<Notificacion[]>([])
  const [noLeidas, setNoLeidas] = useState(0)
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Cargar notificaciones del doctor
  const cargarNotificaciones = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      const { data, error: dbError } = await supabase
        .from('notificaciones')
        .select('*')
        .eq('doctor_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50)

      if (dbError) throw dbError

      const notifs = data || []
      setNotificaciones(notifs)
      setNoLeidas(notifs.filter(n => n.estado === 'enviado').length)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    cargarNotificaciones()
  }, [cargarNotificaciones])

  // Crear notificación in-app
  const crearNotificacion = useCallback(async (datos: Partial<Notificacion>) => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      const { data, error: dbError } = await supabase
        .from('notificaciones')
        .insert({
          doctor_id: user.id,
          tipo: datos.tipo || 'in-app',
          categoria: datos.categoria || 'general',
          titulo: datos.titulo || 'Notificación',
          mensaje: datos.mensaje || '',
          estado: 'enviado',
          email_destino: datos.email_destino,
          telefono_destino: datos.telefono_destino,
          metadata: datos.metadata || {},
        })
        .select()
        .single()

      if (dbError) throw dbError

      setNotificaciones(prev => [data, ...prev])
      setNoLeidas(prev => prev + 1)
      return { success: true, data }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    }
  }, [])

  // Enviar email por Resend
  const enviarEmail = useCallback(async (datos: {
    to: string
    subject: string
    html: string
    text?: string
    categoria?: string
    paciente_id?: string
    cita_id?: string
  }) => {
    setSending(true)
    setError(null)

    try {
      // 1. Enviar por Resend
      const response = await fetch('/api/send-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          to: datos.to,
          subject: datos.subject,
          html: datos.html,
          text: datos.text || datos.html,
        }),
      })

      const result = await response.json()

      if (!response.ok) {
        throw new Error(result.error || 'Error al enviar email')
      }

      // 2. Guardar en base de datos como enviado
      await crearNotificacion({
        tipo: 'email',
        categoria: datos.categoria || 'email_enviado',
        titulo: datos.subject,
        mensaje: datos.text || datos.html,
        email_destino: datos.to,
        estado: 'enviado',
        metadata: { resend_id: result.id, paciente_id: datos.paciente_id, cita_id: datos.cita_id },
      })

      return { success: true, id: result.id }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSending(false)
    }
  }, [crearNotificacion])

  // Marcar como leída
  const marcarLeida = useCallback(async (id: string) => {
    try {
      const { error: dbError } = await supabase
        .from('notificaciones')
        .update({ estado: 'leido', leido_en: new Date().toISOString() })
        .eq('id', id)

      if (dbError) throw dbError

      setNotificaciones(prev => prev.map(n => 
        n.id === id ? { ...n, estado: 'leido', leido_en: new Date().toISOString() } : n
      ))
      setNoLeidas(prev => Math.max(0, prev - 1))
    } catch (err: any) {
      setError(err.message)
    }
  }, [])

  // Marcar todas como leídas
  const marcarTodasLeidas = useCallback(async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { error: dbError } = await supabase
        .from('notificaciones')
        .update({ estado: 'leido', leido_en: new Date().toISOString() })
        .eq('doctor_id', user.id)
        .eq('estado', 'enviado')

      if (dbError) throw dbError

      setNotificaciones(prev => prev.map(n => ({ ...n, estado: 'leido' })))
      setNoLeidas(0)
    } catch (err: any) {
      setError(err.message)
    }
  }, [])

  // Enviar recordatorio de cita
  const enviarRecordatorioCita = useCallback(async (cita: any) => {
    const paciente = cita.paciente
    if (!paciente?.email) {
      return { success: false, error: 'Paciente no tiene email registrado' }
    }

    const fecha = new Date(cita.fecha).toLocaleDateString('es-GT', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })

    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #1E5C8E;">Recordatorio de Cita Médica</h2>
        <p>Hola <strong>${paciente.nombre} ${paciente.apellido}</strong>,</p>
        <p>Le recordamos que tiene una cita programada:</p>
        <div style="background: #e8f0f8; padding: 20px; border-radius: 8px; margin: 20px 0;">
          <p><strong>Fecha:</strong> ${fecha}</p>
          <p><strong>Hora:</strong> ${cita.hora_inicio}</p>
          <p><strong>Motivo:</strong> ${cita.motivo || 'Consulta general'}</p>
          <p><strong>Doctor:</strong> ${cita.doctor_nombre || 'Su médico'}</p>
        </div>
        <p>Si necesita cancelar o reprogramar, por favor contáctenos con anticipación.</p>
        <p style="color: #8a9aaa; font-size: 12px; margin-top: 30px;">
          Este es un mensaje automático de EzPayConnect - Software Médico
        </p>
      </div>
    `

    return await enviarEmail({
      to: paciente.email,
      subject: `Recordatorio: Cita el ${fecha}`,
      html,
      text: `Recordatorio de cita médica el ${fecha} a las ${cita.hora_inicio}. Motivo: ${cita.motivo || 'Consulta general'}`,
      categoria: 'recordatorio_cita',
      paciente_id: paciente.id,
      cita_id: cita.id,
    })
  }, [enviarEmail])

  return {
    notificaciones,
    noLeidas,
    loading,
    sending,
    error,
    cargarNotificaciones,
    crearNotificacion,
    enviarEmail,
    marcarLeida,
    marcarTodasLeidas,
    enviarRecordatorioCita,
  }
}
