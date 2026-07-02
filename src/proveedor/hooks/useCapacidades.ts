import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

// Capacidad vigente devuelta por la RPC public.mis_capacidades() (ya filtra activa + no vencida server-side).
interface CapacidadVigente {
  capacidad_codigo: string
  hasta: string | null
}

// Visibilidad de UI (NO es un gate de seguridad — los gates reales están server-side).
// Deriva la empresa de la sesión vía mis_capacidades(); deny-by-default (sin fila → no la tiene).
export function useCapacidades() {
  const [capacidades, setCapacidades] = useState<CapacidadVigente[]>([])
  const [loading, setLoading] = useState(true)

  const fetchCapacidades = useCallback(async () => {
    const { data, error } = await supabase.rpc('mis_capacidades')
    if (error) {
      console.error('[useCapacidades] Error obteniendo capacidades:', error)
      setCapacidades([])
      return
    }
    setCapacidades((Array.isArray(data) ? data : []) as CapacidadVigente[])
  }, [])

  useEffect(() => {
    const init = async () => {
      await fetchCapacidades()
      setLoading(false)
    }
    init()

    // Re-fetch al cambiar de sesión (login/logout), mismo espíritu que useProveedorAuth.
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session?.user) fetchCapacidades()
      else setCapacidades([])
    })

    return () => listener.subscription.unsubscribe()
  }, [fetchCapacidades])

  const codigos = new Set(capacidades.map((c) => c.capacidad_codigo))
  // Mientras carga, el Set está vacío → tieneCapacidad = false (el layout espera loading para no parpadear).
  const tieneCapacidad = (codigo: string) => codigos.has(codigo)

  return { capacidades, loading, tieneCapacidad }
}
