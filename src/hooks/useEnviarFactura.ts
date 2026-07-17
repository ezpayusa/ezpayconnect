import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export function useEnviarFactura() {
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [exito, setExito] = useState(false)

  const enviarFactura = useCallback(async (datos: {
    to: string
    facturaId?: number
    pacienteNombre: string
    medicoNombre?: string
    concepto: string
    cantidad?: number
    precioUnitario?: number
    descuento?: number
    total: number
    moneda?: string
    fecha?: string
    estado?: string
    metodoPago?: string
    notas?: string
  }) => {
    setEnviando(true)
    setError(null)
    setExito(false)

    try {
      // Adjuntar el JWT de sesión: el endpoint /api/send-factura exige caller autenticado
      // con rol clínico/administrativo (cierra el open-relay de emails). Mismo patrón que recetas.
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setError('Sesión no válida. Iniciá sesión de nuevo.')
        return { success: false, error: 'No autenticado' }
      }
      const response = await fetch('/api/send-factura', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify(datos),
      })

      if (!response.ok) {
        const raw = await response.text()
        let mensaje = 'No se pudo procesar el envío. Intentá de nuevo en unos minutos.'
        try {
          const parsed = JSON.parse(raw)
          if (parsed?.error) mensaje = String(parsed.error)
          if (parsed?.details) console.error('[useEnviarFactura] detalle del error:', parsed.details)
        } catch {
          console.error('[useEnviarFactura] respuesta no-JSON del servidor:', raw)
        }
        setError(mensaje)
        return { success: false, error: mensaje }
      }

      const raw = await response.text()
      let data: any = null
      if (raw.trim()) {
        try {
          data = JSON.parse(raw)
        } catch {
          console.warn('[useEnviarFactura] éxito con body no-JSON:', raw)
        }
      }
      setExito(true)
      return { success: true, data }
    } catch (err: any) {
      const mensaje = 'No se pudo conectar. Revisá tu conexión.'
      setError(mensaje)
      return { success: false, error: err?.message || mensaje }
    } finally {
      setEnviando(false)
    }
  }, [])

  return { enviarFactura, enviando, error, exito, setError, setExito }
}
