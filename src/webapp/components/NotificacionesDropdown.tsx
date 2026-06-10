import { useState, useRef, useEffect } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppNotificaciones } from '@/webapp/hooks/useWebAppNotificaciones'
import { Bell, Check, Calendar, FileText, FlaskConical, MessageCircle, Info, Loader2, Megaphone } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

export default function NotificacionesDropdown() {
  const { perfil } = useWebAppAuth()
  const { notificaciones, noLeidas, loading, marcarComoLeida, marcarTodasComoLeidas } =
    useWebAppNotificaciones(perfil?.id)
  const [abierto, setAbierto] = useState(false)
  const dropdownRef = useRef<HTMLDivElement>(null)
  const navigate = useNavigate()

  // Cerrar al hacer click fuera
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setAbierto(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const getIcono = (tipo: string) => {
    switch (tipo) {
      case 'cita': return <Calendar className="h-4 w-4 text-sky-500" />
      case 'receta': return <FileText className="h-4 w-4 text-emerald-500" />
      case 'examen': return <FlaskConical className="h-4 w-4 text-amber-500" />
      case 'mensaje': return <MessageCircle className="h-4 w-4 text-indigo-500" />
      case 'promocion': return <Megaphone className="h-4 w-4 text-rose-500" />
      default: return <Info className="h-4 w-4 text-slate-400" />
    }
  }

  const handleClickNotif = async (notif: any) => {
    if (!notif.leida) {
      await marcarComoLeida(notif.id)
    }
    if (notif.accion_url) {
      navigate(notif.accion_url)
    }
    setAbierto(false)
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setAbierto(!abierto)}
        className="relative p-2 text-slate-500 hover:bg-slate-100 rounded-lg transition-colors"
      >
        <Bell className="h-5 w-5" />
        {noLeidas > 0 && (
          <span className="absolute top-1 right-1 h-4 w-4 bg-red-500 rounded-full text-white text-[10px] flex items-center justify-center">
            {noLeidas > 9 ? '9+' : noLeidas}
          </span>
        )}
      </button>

      {abierto && (
        <div className="absolute right-0 mt-2 w-80 bg-white rounded-xl shadow-xl border border-slate-200 z-50 overflow-hidden">
          <div className="p-3 border-b border-slate-100 flex items-center justify-between">
            <h3 className="font-semibold text-slate-800 text-sm">Notificaciones</h3>
            {noLeidas > 0 && (
              <button
                onClick={marcarTodasComoLeidas}
                className="text-xs text-sky-600 hover:text-sky-700 flex items-center gap-1"
              >
                <Check className="h-3 w-3" />
                Marcar todas como leídas
              </button>
            )}
          </div>

          <div className="max-h-80 overflow-y-auto">
            {loading && (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-sky-500" />
              </div>
            )}

            {!loading && notificaciones.length === 0 && (
              <div className="text-center py-8">
                <Bell className="h-10 w-10 text-slate-200 mx-auto mb-2" />
                <p className="text-sm text-slate-400">No tienes notificaciones</p>
              </div>
            )}

            {notificaciones.map((notif) => (
              <button
                key={notif.id}
                onClick={() => handleClickNotif(notif)}
                className={`w-full text-left px-4 py-3 hover:bg-slate-50 transition-colors border-b border-slate-50 last:border-0 ${
                  !notif.leida ? 'bg-sky-50/50' : ''
                }`}
              >
                <div className="flex gap-3">
                  <div className="mt-0.5">{getIcono(notif.tipo)}</div>
                  <div className="flex-1 min-w-0">
                    <p className={`text-sm ${!notif.leida ? 'font-semibold text-slate-800' : 'text-slate-600'}`}>
                      {notif.titulo}
                    </p>
                    {notif.mensaje && (
                      <p className="text-xs text-slate-500 truncate">{notif.mensaje}</p>
                    )}
                    <p className="text-[10px] text-slate-400 mt-1">
                      {new Date(notif.created_at).toLocaleDateString('es-GT', {
                        day: 'numeric',
                        month: 'short',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </p>
                  </div>
                  {!notif.leida && (
                    <div className="w-2 h-2 bg-sky-500 rounded-full mt-1.5 shrink-0" />
                  )}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
