import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface SolicitudPersonalizacion {
  id: string
  tenant_tipo: 'clinica' | 'empresa_proveedora'
  tenant_id: string
  estado: 'pendiente' | 'aprobada' | 'rechazada'
  logo_url: string | null
  color_primario: string | null
  color_secundario: string | null
  color_fondo: string | null
  motivo_rechazo: string | null
  created_at: string
  revisado_at: string | null
}

// Lee las solicitudes de personalización del PROPIO tenant. La RLS de mig 205 (es_mi_tenant) ya
// filtra a las del tenant de la sesión; el .eq('tenant_tipo', tipo) es redundante pero explícito.
export function useMiSolicitudPersonalizacion(tipo: 'clinica' | 'empresa_proveedora') {
  const [rows, setRows] = useState<SolicitudPersonalizacion[]>([])
  const [loading, setLoading] = useState(true)

  const recargar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('solicitudes_personalizacion')
      .select('*')
      .eq('tenant_tipo', tipo)
      .order('created_at', { ascending: false })
    if (error) {
      console.error('[useMiSolicitudPersonalizacion]', error)
      setRows([])
    } else {
      setRows((data ?? []) as SolicitudPersonalizacion[])
    }
    setLoading(false)
  }, [tipo])

  useEffect(() => { recargar() }, [recargar])

  const pendiente = rows.find((r) => r.estado === 'pendiente') ?? null
  const ultima = rows.find((r) => r.estado !== 'pendiente') ?? null  // la resuelta más reciente

  return { pendiente, ultima, loading, recargar }
}
