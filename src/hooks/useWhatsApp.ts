import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface WhatsAppMensaje {
  id: string
  doctor_id: string
  paciente_id?: string
  cita_id?: string
  telefono_destino: string
  mensaje: string
  estado: 'pendiente' | 'enviado' | 'entregado' | 'leido' | 'respondido' | 'error'
  respuesta?: string
  tipo: string
  enviado_en?: string
  respondido_en?: string
  created_at: string
}

export function useWhatsApp() {
  const [mensajes, setMensajes] = useState<WhatsAppMensaje[]>([])
  const [loading, setLoading] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const cargarMensajes = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      const { data, error: dbError } = await supabase
        .from('whatsapp_mensajes')
        .select('*')
        .eq('doctor_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50)

      if (dbError) throw dbError
      setMensajes(data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    cargarMensajes()
  }, [cargarMensajes])

  // Crear mensaje de recordatorio de cita
  const crearRecordatorioCita = useCallback(async (datos: {
    paciente_id: string
    cita_id: string
    telefono: string
    nombre_paciente: string
    fecha_cita: string
    hora_cita: string
    motivo?: string
  }) => {
    setSending(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      const fecha = new Date(datos.fecha_cita).toLocaleDateString('es-GT', {
        weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
      })

      const mensaje = `🏥 *EzPayConnect - Recordatorio de Cita*

Hola *${datos.nombre_paciente}*, le recordamos su cita médica:

📅 *Fecha:* ${fecha}
🕐 *Hora:* ${datos.hora_cita}
📝 *Motivo:* ${datos.motivo || 'Consulta general'}

📍 *Dirección:* [Dirección de la clínica]

Por favor responda:
✅ *SI* - para confirmar
❌ *NO* - para cancelar

Gracias por preferirnos. EzPayConnect 💙`

      const { data, error: dbError } = await supabase
        .from('whatsapp_mensajes')
        .insert({
          doctor_id: user.id,
          paciente_id: datos.paciente_id,
          cita_id: datos.cita_id,
          telefono_destino: datos.telefono,
          mensaje,
          estado: 'pendiente',
          tipo: 'recordatorio'
        })
        .select()
        .single()

      if (dbError) throw dbError

      setMensajes(prev => [data, ...prev])
      return { success: true, data }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSending(false)
    }
  }, [])

  // Simular envío (cuando conectes Meta Business, cambias esto)
  const simularEnvio = useCallback(async (mensajeId: string) => {
    try {
      const { error } = await supabase
        .from('whatsapp_mensajes')
        .update({ 
          estado: 'enviado', 
          enviado_en: new Date().toISOString() 
        })
        .eq('id', mensajeId)

      if (error) throw error

      setMensajes(prev => prev.map(m => 
        m.id === mensajeId ? { ...m, estado: 'enviado', enviado_en: new Date().toISOString() } : m
      ))

      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }, [])

  // Simular respuesta del paciente
  const simularRespuesta = useCallback(async (mensajeId: string, respuesta: string) => {
    try {
      const estadoRespuesta = respuesta.toLowerCase().includes('si') ? 'respondido' : 'respondido'

      const { error } = await supabase
        .from('whatsapp_mensajes')
        .update({ 
          estado: estadoRespuesta, 
          respuesta,
          respondido_en: new Date().toISOString() 
        })
        .eq('id', mensajeId)

      if (error) throw error

      setMensajes(prev => prev.map(m => 
        m.id === mensajeId ? { 
          ...m, 
          estado: estadoRespuesta, 
          respuesta,
          respondido_en: new Date().toISOString() 
        } : m
      ))

      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }, [])

  return {
    mensajes,
    loading,
    sending,
    error,
    cargarMensajes,
    crearRecordatorioCita,
    simularEnvio,
    simularRespuesta
  }
}
