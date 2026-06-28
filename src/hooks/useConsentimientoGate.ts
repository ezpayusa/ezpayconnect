import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export type EstadoConsentimiento = 'concedido' | 'revocado' | 'pendiente'

/**
 * Gate liviano de consentimiento (una lectura). Regla GRANDFATHER: bloquea SOLO si el estado vigente es
 * concedido=false; sin fila = permite; concedido=true = permite. Un error de lectura NO bloquea (permite).
 * Con pacienteId undefined no dispara RPC (para call-sites que no necesitan gatear).
 */
export function useConsentimientoGate(pacienteId: number | undefined) {
  const [mapa, setMapa] = useState<Record<string, { concedido: boolean }>>({})
  const [cargando, setCargando] = useState(!!pacienteId)

  const cargar = useCallback(async () => {
    if (!pacienteId) { setMapa({}); setCargando(false); return }
    setCargando(true)
    const { data, error } = await supabase.rpc('estado_consentimiento_paciente', { p_paciente_id: pacienteId })
    if (error) { console.warn('estado_consentimiento_paciente:', error.message); setMapa({}); setCargando(false); return } // NO bloquear: grandfather
    const m: Record<string, { concedido: boolean }> = {}
    if (Array.isArray(data)) {
      for (const row of data) {
        if (row && typeof row.codigo === 'string') m[row.codigo] = { concedido: !!row.concedido }
      }
    }
    setMapa(m)
    setCargando(false)
  }, [pacienteId])

  useEffect(() => { cargar() }, [cargar])

  // Grandfather: sin entrada = permite; con entrada = devuelve concedido. Durante la carga, permite (no parpadea).
  const permitido = useCallback((codigo: string): boolean => {
    if (cargando) return true
    const e = mapa[codigo]
    if (!e) return true
    return e.concedido
  }, [mapa, cargando])

  const estadoDe = useCallback((codigo: string): EstadoConsentimiento => {
    const e = mapa[codigo]
    if (!e) return 'pendiente'
    return e.concedido ? 'concedido' : 'revocado'
  }, [mapa])

  return { permitido, estadoDe, cargando, recargar: cargar }
}
