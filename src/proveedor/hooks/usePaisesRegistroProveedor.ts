import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

// País DEMO: no operativo. registrar_proveedor (mig 327) lo rechaza con 22023, y ofrecerlo en el
// alta dejaría un usuario de auth huérfano (el signUp ya ocurrió cuando la RPC falla).
export const CODIGO_PAIS_DEMO = 'ZZ'

export interface PaisRegistroProveedor {
  id: string
  nombre: string
}

// Países del alta pública de proveedores (/proveedor, /farmacia y /laboratorio/registro).
// Solo para esos 3 formularios: usePaisesRegistro (WebApp, NuevaCitaModal) y las pantallas de
// admin tienen sus propias queries y siguen viendo ZZ.
export function usePaisesRegistroProveedor() {
  const [paises, setPaises] = useState<PaisRegistroProveedor[]>([])

  useEffect(() => {
    supabase
      .from('configuracion_pais')
      .select('id, nombre')
      .eq('activo', true)
      .neq('codigo', CODIGO_PAIS_DEMO)
      .order('nombre')
      .then(({ data }) => setPaises((data || []) as PaisRegistroProveedor[]))
  }, [])

  return paises
}
