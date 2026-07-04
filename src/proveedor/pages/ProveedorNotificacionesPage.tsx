import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useProveedorNotificaciones } from '@/proveedor/context/ProveedorNotificacionesContext'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { Bell, Check, CheckCheck, Clock } from 'lucide-react'

function tiempoRelativo(fecha: string) {
  const diff = Date.now() - new Date(fecha).getTime()
  const minutos = Math.floor(diff / 60000)
  const horas = Math.floor(diff / 3600000)
  const dias = Math.floor(diff / 86400000)
  if (minutos < 1) return 'Ahora'
  if (minutos < 60) return `Hace ${minutos}m`
  if (horas < 24) return `Hace ${horas}h`
  return `Hace ${dias}d`
}

export default function ProveedorNotificacionesPage() {
  // Instancia COMPARTIDA con el badge del sidebar (contexto): marcar leída baja el badge al instante.
  const { notificaciones, noLeidas, loading, listarNotificaciones, marcarLeida, marcarTodasLeidas } = useProveedorNotificaciones()
  const navigate = useNavigate()

  useEffect(() => {
    listarNotificaciones()
  }, [listarNotificaciones])

  return (
    <div className="space-y-6 max-w-3xl mx-auto">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Notificaciones</h1>
          <p className="text-sm text-muted-foreground">
            {noLeidas > 0 ? `Tienes ${noLeidas} notificación${noLeidas !== 1 ? 'es' : ''} sin leer` : 'No tienes notificaciones pendientes'}
          </p>
        </div>
        {noLeidas > 0 && (
          <Button variant="outline" size="sm" onClick={marcarTodasLeidas}>
            <CheckCheck className="h-4 w-4 mr-1" />
            Marcar todas como leídas
          </Button>
        )}
      </div>

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-20 w-full" />
          ))}
        </div>
      ) : notificaciones.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Bell className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">Sin notificaciones</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Aquí aparecerán las notificaciones de visitas, campañas y pagos.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {notificaciones.map((n) => (
            <Card
              key={n.id}
              className={`transition-colors ${!n.leida ? 'bg-blue-50/50 border-blue-100' : ''}`}
            >
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className={`mt-0.5 w-2 h-2 rounded-full shrink-0 ${!n.leida ? 'bg-blue-500' : 'bg-gray-300'}`} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-2">
                      <p className="font-medium text-sm">{n.titulo}</p>
                      <div className="flex items-center gap-2 shrink-0">
                        <span className="text-xs text-muted-foreground flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {tiempoRelativo(n.created_at)}
                        </span>
                        {!n.leida && (
                          <Badge variant="secondary" className="bg-blue-100 text-blue-700 text-[10px]">Nueva</Badge>
                        )}
                      </div>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">{n.mensaje}</p>
                    <div className="flex items-center gap-2 mt-2">
                      {!n.leida && (
                        <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => marcarLeida(n.id)}>
                          <Check className="h-3 w-3 mr-1" />
                          Marcar como leída
                        </Button>
                      )}
                      {n.accion_url && (
                        <Button
                          variant="link"
                          size="sm"
                          className="h-7 text-xs p-0"
                          onClick={() => { if (!n.leida) marcarLeida(n.id); navigate(n.accion_url!) }}
                        >
                          Ver detalle
                        </Button>
                      )}
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
