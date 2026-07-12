import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export function useEnviarReceta() {
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [exito, setExito] = useState(false)

  const enviarReceta = useCallback(async (datos: {
    to: string
    pacienteNombre: string
    medicoNombre?: string
    medicamentos: any[]
    instruccionesGenerales?: string
    solicitarConfirmacion?: boolean
  }) => {
    setEnviando(true)
    setError(null)
    setExito(false)

    try {
      // Adjuntar el JWT de sesión: el endpoint /api/send-receta exige caller
      // autenticado con rol clínico (cierra el open-relay de emails).
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setError('Sesión no válida. Iniciá sesión de nuevo.')
        return { success: false, error: 'No autenticado' }
      }
      const response = await fetch('/api/send-receta', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify(datos),
      })

      if (!response.ok) {
        // Leer el body UNA sola vez como texto: el backend puede responder JSON de error
        // o texto plano (ej. el genérico de Vercel "A server error has occurred"), que
        // rompería el parseo JSON directo con un SyntaxError crudo para el médico.
        const raw = await response.text()
        let mensaje = 'No se pudo procesar el envío. Intentá de nuevo en unos minutos.'
        try {
          const parsed = JSON.parse(raw)
          if (parsed?.error) mensaje = String(parsed.error)
          // details es para el log, NO para el usuario (puede ser un objeto).
          if (parsed?.details) console.error('[useEnviarReceta] detalle del error:', parsed.details)
        } catch {
          // Respuesta no-JSON (texto plano): mensaje genérico limpio + crudo a consola.
          console.error('[useEnviarReceta] respuesta no-JSON del servidor:', raw)
        }
        setError(mensaje)
        return { success: false, error: mensaje }
      }

      // Éxito: el backend puede responder ok con body vacío (204/sin cuerpo) o con JSON.
      // Leemos el body como texto UNA sola vez y no asumimos que haya JSON: un body vacío
      // o no-JSON NO debe romper el éxito (síntoma: "Unexpected end of JSON input").
      const raw = await response.text()
      let data: any = null
      if (raw.trim()) {
        try {
          data = JSON.parse(raw)
        } catch {
          console.warn('[useEnviarReceta] éxito con body no-JSON:', raw)
        }
      }
      setExito(true)
      return { success: true, data }
    } catch (err: any) {
      // Con el manejo de arriba, acá solo caen errores de RED (fetch rechazado).
      const mensaje = 'No se pudo conectar. Revisá tu conexión.'
      setError(mensaje)
      return { success: false, error: err?.message || mensaje }
    } finally {
      setEnviando(false)
    }
  }, [])

  return { enviarReceta, enviando, error, exito, setError, setExito }
}
