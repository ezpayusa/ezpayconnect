import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useCapacidades } from '@/proveedor/hooks/useCapacidades'
import { puedeEnrolarEmpresa } from '@/visitador/lib/visibilidadEnrolamiento'

// Visibilidad de enrolar / solicitar alta / pestaña Solicitudes: laboratorio farmacéutico con el módulo
// 'enrolamiento' vigente (mis_capacidades). Solo UI: la barrera real son las RPCs (PV016/PV014).
// Mientras carga devuelve false (deny-by-default, sin parpadeo de botones que después desaparecen).
export function usePuedeEnrolar(): { puedeEnrolar: boolean; loading: boolean } {
  const { empresa, loading } = useProveedorAuth()
  const { tieneCapacidad, loading: loadingCapacidades } = useCapacidades()
  const cargando = loading || loadingCapacidades
  return { puedeEnrolar: !cargando && puedeEnrolarEmpresa(empresa?.tipo, tieneCapacidad('enrolamiento')), loading: cargando }
}
