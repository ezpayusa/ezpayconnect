import { useState } from 'react'
import { useNotificaciones } from '@/hooks/useNotificaciones'
import { Bell, Check, Mail, AlertCircle, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

// Función simple para mostrar tiempo relativo (reemplaza formatDistanceToNow)
const formatDistanceToNow = (date: Date): string => {
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffSec = Math.floor(diffMs / 1000)
  const diffMin = Math.floor(diffSec / 60)
  const diffHour = Math.floor(diffMin / 60)
  const diffDay = Math.floor(diffHour / 24)

  if (diffSec < 60) return 'hace un momento'
  if (diffMin < 60) return `hace ${diffMin} minuto${diffMin > 1 ? 's' : ''}`
  if (diffHour < 24) return `hace ${diffHour} hora${diffHour > 1 ? 's' : ''}`
  if (diffDay < 30) return `hace ${diffDay} día${diffDay > 1 ? 's' : ''}`
  return date.toLocaleDateString('es-GT')
}

export default function NotificacionesBadge() {
  const { notificaciones, noLeidas, marcarLeida, marcarTodasLeidas, loading } = useNotificaciones()
  const [abierto, setAbierto] = useState(false)

  return (
    <div className="relative">
      <button
        onClick={() => setAbierto(!abierto)}
        className="relative p-2 rounded-lg hover:bg-[#e8f0f8] transition-colors"
      >
        <Bell className="h-5 w-5 text-[#8a9aaa]" />
        {noLeidas > 0 && (
          <span className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 text-white text-xs rounded-full flex items-center justify-center font-bold">
            {noLeidas > 9 ? '9+' : noLeidas}
          </span>
        )}
      </button>

      {abierto && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setAbierto(false)} />
          <Card className="absolute right-0 top-12 w-96 z-50 shadow-xl border border-[#e8f0f8]">
            <CardHeader className="flex flex-row items-center justify-between pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Bell className="h-5 w-5 text-[#1E5C8E]" />
                Notificaciones
              </CardTitle>
              <div className="flex items-center gap-2">
                {noLeidas > 0 && (
                  <Button variant="ghost" size="sm" onClick={marcarTodasLeidas}>
                    <Check className="h-4 w-4 mr-1" /> Marcar leídas
                  </Button>
                )}
                <button onClick={() => setAbierto(false)} className="text-[#8a9aaa] hover:text-[#1a2a3a]">
                  <X className="h-4 w-4" />
                </button>
              </div>
            </CardHeader>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-8 text-center text-[#8a9aaa]">Cargando...</div>
              ) : notificaciones.length === 0 ? (
                <div className="p-8 text-center text-[#8a9aaa]">
                  <Bell className="h-8 w-8 mx-auto mb-2 opacity-50" />
                  <p>No hay notificaciones</p>
                </div>
              ) : (
                <div className="max-h-[400px] overflow-y-auto">
                  {notificaciones.map(notif => (
                    <div
                      key={notif.id}
                      className={`p-4 border-b border-[#e8f0f8] hover:bg-[#f8fafc] transition-colors cursor-pointer ${
                        !notif.leida ? 'bg-[#e8f0f8]' : ''
                      }`}
                      onClick={() => marcarLeida(notif.id)}
                    >
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5">
                          {notif.tipo === 'email' && <Mail className="h-4 w-4 text-[#1E5C8E]" />}
                          {notif.tipo === 'in-app' && <Bell className="h-4 w-4 text-[#3A8ABF]" />}
                          {notif.tipo === 'sms' && <AlertCircle className="h-4 w-4 text-yellow-500" />}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[#1a2a3a] truncate">{notif.titulo}</p>
                          <p className="text-xs text-[#8a9aaa] line-clamp-2">{notif.mensaje}</p>
                          <p className="text-xs text-[#8a9aaa] mt-1">
                            {formatDistanceToNow(new Date(notif.created_at))}
                          </p>
                        </div>
                        {!notif.leida && (
                          <div className="w-2 h-2 bg-[#1E5C8E] rounded-full mt-1.5" />
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
