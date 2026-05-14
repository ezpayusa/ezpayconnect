import { useNotificaciones } from '@/hooks/useNotificaciones'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Bell, Mail, Check, AlertCircle, Clock, ArrowLeft } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

export default function NotificacionesPage() {
  const navigate = useNavigate()
  const { notificaciones, loading, marcarLeida, marcarTodasLeidas, noLeidas } = useNotificaciones()

  const getIcono = (tipo: string) => {
    switch (tipo) {
      case 'email': return <Mail className="h-5 w-5 text-[#1E5C8E]" />
      case 'sms': return <AlertCircle className="h-5 w-5 text-yellow-500" />
      case 'in-app': return <Bell className="h-5 w-5 text-[#3A8ABF]" />
      default: return <Bell className="h-5 w-5 text-[#8a9aaa]" />
    }
  }

  const getColorBadge = (estado: string) => {
    switch (estado) {
      case 'enviado': return 'bg-blue-100 text-blue-700 border-blue-200'
      case 'leido': return 'bg-gray-100 text-gray-600 border-gray-200'
      case 'error': return 'bg-red-100 text-red-700 border-red-200'
      default: return 'bg-yellow-100 text-yellow-700 border-yellow-200'
    }
  }

  const formatFecha = (fecha: string) => {
    return new Date(fecha).toLocaleDateString('es-GT', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Button variant="ghost" size="sm" onClick={() => navigate('/dashboard')} className="text-[#8a9aaa]">
              <ArrowLeft className="h-4 w-4 mr-1" /> Dashboard
            </Button>
          </div>
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <Bell className="h-8 w-8 text-[#1E5C8E]" />
            Notificaciones
          </h1>
          <p className="text-[#8a9aaa] mt-1">
            {noLeidas > 0 ? `Tienes ${noLeidas} notificación${noLeidas > 1 ? 'es' : ''} sin leer` : 'No hay notificaciones nuevas'}
          </p>
        </div>
        {noLeidas > 0 && (
          <Button onClick={marcarTodasLeidas} variant="outline" className="border-[#1E5C8E] text-[#1E5C8E]">
            <Check className="h-4 w-4 mr-2" /> Marcar todas leídas
          </Button>
        )}
      </div>

      {notificaciones.length === 0 ? (
        <Card className="bg-[#f8fafc]">
          <CardContent className="p-12 text-center">
            <Bell className="h-12 w-12 mx-auto mb-4 text-[#8a9aaa]" />
            <p className="text-[#8a9aaa]">No tienes notificaciones registradas</p>
            <p className="text-sm text-[#8a9aaa] mt-2">
              Las notificaciones aparecerán aquí cuando envíes recordatorios de citas o recetas.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {notificaciones.map(notif => (
            <Card 
              key={notif.id} 
              className={`hover:shadow-md transition-shadow cursor-pointer ${
                notif.estado === 'enviado' ? 'border-l-4 border-l-[#1E5C8E]' : ''
              }`}
              onClick={() => marcarLeida(notif.id)}
            >
              <CardContent className="p-4">
                <div className="flex items-start gap-4">
                  <div className="mt-1">
                    {getIcono(notif.tipo)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-medium text-[#1a2a3a]">{notif.titulo}</h3>
                      <Badge variant="outline" className={getColorBadge(notif.estado)}>
                        {notif.estado}
                      </Badge>
                    </div>
                    <p className="text-sm text-[#8a9aaa] line-clamp-2">{notif.mensaje}</p>
                    <div className="flex items-center gap-4 mt-2 text-xs text-[#8a9aaa]">
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {formatFecha(notif.created_at)}
                      </span>
                      {notif.email_destino && (
                        <span className="flex items-center gap-1">
                          <Mail className="h-3 w-3" />
                          {notif.email_destino}
                        </span>
                      )}
                    </div>
                  </div>
                  {notif.estado === 'enviado' && (
                    <div className="w-3 h-3 bg-[#1E5C8E] rounded-full mt-2" />
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
