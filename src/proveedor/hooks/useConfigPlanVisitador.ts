import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { configComprable } from '@/proveedor/lib/compraPlanVisitador'

export interface ConfigPlanVisitador {
  id: string
  nombre: string
  precio: number
  moneda: string
  visitasIncluidas: number | null
  duracionDias: number | null
  comprable: boolean
}

// Lee la configuración del plan de visitador que el checkout va a cobrar (precio, moneda, visitas, duración).
// El checkout NO usa el monto de la URL: la RPC cobra estos mismos valores desde el servidor.
export function useConfigPlanVisitador(configId: string | null) {
  const [config, setConfig] = useState<ConfigPlanVisitador | null>(null)
  const [loading, setLoading] = useState(!!configId)

  useEffect(() => {
    if (!configId) {
      setConfig(null)
      setLoading(false)
      return
    }
    let vivo = true
    setLoading(true)
    supabase
      .from('planes_configuracion')
      .select('id, precio_local, moneda_local, visitas_incluidas, duracion_dias, activo, plan_base:plan_base_id(nombre, tipo, activo)')
      .eq('id', configId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (!vivo) return
        if (error) console.error(error)
        const base = (data as any)?.plan_base
        setConfig(
          data && base?.tipo === 'visitador'
            ? {
                id: data.id,
                nombre: base.nombre,
                precio: Number(data.precio_local ?? 0),
                moneda: data.moneda_local ?? 'GTQ',
                visitasIncluidas: data.visitas_incluidas,
                duracionDias: data.duracion_dias,
                comprable: !!data.activo && !!base.activo && configComprable(data) && Number(data.precio_local ?? 0) > 0,
              }
            : null
        )
        setLoading(false)
      })
    return () => {
      vivo = false
    }
  }, [configId])

  return { config, loading }
}
