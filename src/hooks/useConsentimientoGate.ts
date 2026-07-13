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
  const [error, setError] = useState(false)

  const cargar = useCallback(async () => {
    if (!pacienteId) { setMapa({}); setError(false); setCargando(false); return }
    setCargando(true)
    setError(false)
    const { data, error: rpcError } = await supabase.rpc('estado_consentimiento_paciente', { p_paciente_id: pacienteId })
    // FAIL-CLOSED en ERROR: antes esto era grandfather (mapa={} → permite), lo que ante 400/red
    // habilitaba captura de PHI como si hubiera consentido. Ahora se expone `error` y los
    // componentes bloquean. El grandfather del caso OK-sin-fila (abajo) queda intacto.
    if (rpcError) { console.warn('estado_consentimiento_paciente:', rpcError.message); setError(true); setMapa({}); setCargando(false); return }
    const m: Record<string, { concedido: boolean }> = {}
    if (Array.isArray(data)) {
      for (const row of data) {
        if (row && typeof row.codigo === 'string') m[row.codigo] = { concedido: !!row.concedido }
      }
    }
    setError(false)
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

  return { permitido, estadoDe, cargando, error, recargar: cargar }
}
