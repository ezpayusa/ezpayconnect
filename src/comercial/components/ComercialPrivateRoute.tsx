import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { rutaHomePorRol } from '@/lib/rutas'

// Gate del módulo comercial. Molde: VisitadorPrivateRoute — pero cableado a useAuth (tabla
// `perfiles`), NO a useProveedorAuth (`cuentas_proveedor`). Son dos espacios de identidad
// distintos: los visitadores son cuentas de una empresa proveedora, los comerciales son perfiles
// de EzPay. Reusar aquel guard habría gateado sobre la tabla equivocada.
//
// SOLO ENRUTA Y OCULTA. La autorización real vive en la mig 272 (las 7 RPCs SECURITY DEFINER son
// el control completo: no hay policies de escritura) y en las policies de SELECT de la 264. Si
// alguien fuerza la URL saltándose este guard, la lista le viene vacía por RLS y toda acción le
// contesta 42501. Este archivo es comodidad, no seguridad.
export const ROLES_COMERCIALES = ['asesor_comercial', 'supervisor_comercial'] as const

export default function ComercialPrivateRoute({ children }: { children: ReactNode }) {
  const { user, perfil, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!user) return <Navigate to="/login" replace />

  // Denegar por defecto: sólo entra quien está en la lista. Un rol desconocido —o un perfil que
  // todavía no cargó su rol— NO pasa, y va a /sin-panel en vez de a una pantalla ajena.
  // Rechazar y DEVOLVER A SU CASA, no depositar en un cartel genérico: un médico que fuerza esta
  // URL tiene panel propio y mandarlo a /sin-panel le mentiría. rutaHomePorRol ya sabe a dónde va
  // cada rol —y manda a /sin-panel al que de verdad no tiene ninguno—, así que no se escribe acá
  // una segunda tabla de destinos.
  const rol = perfil?.rol ?? ''
  if (!(ROLES_COMERCIALES as readonly string[]).includes(rol)) {
    return <Navigate to={rutaHomePorRol(perfil)} replace />
  }

  return <>{children}</>
}
