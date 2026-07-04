import { createContext, useContext, useEffect, type ReactNode } from 'react'
import { useNotificaciones } from '@/hooks/useNotificaciones'

// Contexto de notificaciones del PROVEEDOR: UNA sola instancia de useNotificaciones, compartida por el
// badge del sidebar (ProveedorLayout) Y la página de notificaciones. Antes eran 2 instancias separadas →
// al marcar leída en la página, el badge del sidebar no se enteraba hasta el polling de 60s. Con una
// instancia única, marcarLeida/marcarTodasLeidas actualizan el estado compartido y el badge baja al
// instante. Scope 100% proveedor (no toca el hook compartido ni otros paneles).
type NotifCtx = ReturnType<typeof useNotificaciones>
const Ctx = createContext<NotifCtx | null>(null)

export function ProveedorNotificacionesProvider({ children }: { children: ReactNode }) {
  const notif = useNotificaciones()
  const { listarNotificaciones } = notif
  // Carga inicial + polling 60s (igual que hacía ProveedorLayout; ahora centralizado en la única instancia).
  useEffect(() => {
    listarNotificaciones()
    const interval = setInterval(listarNotificaciones, 60000)
    return () => clearInterval(interval)
  }, [listarNotificaciones])
  return <Ctx.Provider value={notif}>{children}</Ctx.Provider>
}

export function useProveedorNotificaciones() {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useProveedorNotificaciones debe usarse dentro de ProveedorNotificacionesProvider')
  return ctx
}
