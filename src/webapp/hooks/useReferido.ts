import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

// Salida del RPC public.generar_codigo_referido() (mig 175): idempotente (1ra vez crea, luego devuelve el mismo).
export interface ReferidoData {
  codigo: string
  clinica_origen_id: string | null
}

/**
 * Hook del lado del REFERIDOR (paciente logueado). Llama el RPC DEFINER `generar_codigo_referido`
 * de forma LAZY (solo al invocar `generar`, no en cada render) y memoiza el código (idempotente).
 * El link apunta a /paciente/registro con el ?ref= (capturado ahí por useCapturarReferido). Origin dinámico.
 */
export function useReferido() {
  const [codigo, setCodigo] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const generar = useCallback(async (): Promise<string | null> => {
    // Ya resuelto en esta sesión → no re-llamar al RPC.
    if (codigo) return codigo
    setLoading(true)
    setError(null)
    const { data, error: rpcError } = await supabase.rpc('generar_codigo_referido')
    setLoading(false)
    if (rpcError) {
      setError(rpcError.message)
      return null
    }
    const c = (data as ReferidoData | null)?.codigo ?? null
    setCodigo(c)
    return c
  }, [codigo])

  const link = codigo ? `${window.location.origin}/paciente/registro?ref=${codigo}` : null

  return { codigo, link, loading, error, generar }
}

// Helper puro para armar el link desde un código (mismo formato/origin dinámico).
export function buildReferidoLink(codigo: string): string {
  return `${window.location.origin}/paciente/registro?ref=${codigo}`
}
