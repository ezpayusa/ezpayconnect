import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import { usePaisActivo } from '@/hooks/usePaisActivo'
import { unidadPesoPorPais, type UnidadPeso } from '@/lib/unidades'

// Unidad de peso (kg/lb) segun el pais del usuario. Admin: pais activo del contexto (ya trae codigo).
// Otros roles: resuelve el codigo desde configuracion_pais por perfil.pais_id. Default kg.
export function useUnidadPeso(): { unidad: UnidadPeso; loading: boolean } {
  const { perfil } = useAuth()
  const { paisActivo } = usePaisActivo()
  const [codigo, setCodigo] = useState<string | null>(paisActivo?.codigo ?? null)
  const [loading, setLoading] = useState(true)

  const paisId = paisActivo?.id || perfil?.pais_id

  useEffect(() => {
    let cancelado = false
    async function resolver() {
      if (paisActivo?.codigo) { setCodigo(paisActivo.codigo); setLoading(false); return }
      if (!paisId) { setCodigo(null); setLoading(false); return }
      const { data } = await supabase
        .from('configuracion_pais')
        .select('codigo')
        .eq('id', paisId)
        .maybeSingle()
      if (!cancelado) {
        setCodigo((data as { codigo?: string } | null)?.codigo ?? null)
        setLoading(false)
      }
    }
    resolver()
    return () => { cancelado = true }
  }, [paisId, paisActivo?.codigo])

  return { unidad: unidadPesoPorPais(codigo), loading }
}
