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

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Error al enviar receta')
      }

      setExito(true)
      return { success: true, data }
    } catch (err: any) {
      setError(err.message || 'Error desconocido')
      return { success: false, error: err.message }
    } finally {
      setEnviando(false)
    }
  }, [])

  return { enviarReceta, enviando, error, exito, setError, setExito }
}
