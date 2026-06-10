import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useClinicaNotificaciones } from '@/clinica/hooks/useClinicaNotificaciones'
import { Bell, Check, Calendar, Loader2 } from 'lucide-react'

export default function ClinicaNotificacionesDropdown() {
  const { notificaciones, noLeidas, loading, marcarLeida, marcarTodasLeidas } = useClinicaNotificaciones()
  const [abierto, setAbierto] = useState(false)
  const navigate = useNavigate()

  const handleClick = async (n: { id: string; leida: boolean; accion_url: string | null }) => {
    if (!n.leida) await marcarLeida(n.id)
    if (n.accion_url) navigate(n.accion_url)
    setAbierto(false)
  }

  return (
    <div className="relative">
      <button
        onClick={() => setAbierto(!abierto)}
        className="relative p-2 rounded-lg hover:bg-white/10 transition-colors"
        aria-label="Notificaciones"
      >
        <Bell className="h-5 w-5 text-[#B8D0E0]" />
        {noLeidas > 0 && (
          <span className="absolute -top-0.5 -right-0.5 h-4 w-4 bg-red-500 rounded-full text-white text-[10px] flex items-center justify-center font-bold">
            {noLeidas > 9 ? '9+' : noLeidas}
          </span>
        )}
      </button>

      {abierto && (
        <>
          {/* Backdrop para cerrar al hacer click fuera */}
          <div className="fixed inset-0 z-40" onClick={() => setAbierto(false)} />
          {/* Panel: posición fija dentro de la pantalla, fondo blanco sólido */}
          <div className="fixed left-[17rem] top-16 w-80 max-w-[calc(100vw-18rem)] bg-white rounded-xl shadow-2xl border border-slate-200 z-50 overflow-hidden text-slate-800">
            <div className="p-3 border-b border-slate-100 flex items-center justify-between">
              <h3 className="font-semibold text-sm">Notificaciones</h3>
              {noLeidas > 0 && (
                <button
                  onClick={marcarTodasLeidas}
                  className="text-xs text-sky-600 hover:text-sky-700 flex items-center gap-1"
                >
                  <Check className="h-3 w-3" /> Marcar todas
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

              {notificaciones.map((n) => (
                <button
                  key={n.id}
                  onClick={() => handleClick(n)}
                  className={`w-full text-left px-4 py-3 hover:bg-slate-50 transition-colors border-b border-slate-50 last:border-0 ${
                    !n.leida ? 'bg-sky-50/50' : ''
                  }`}
                >
                  <div className="flex gap-3">
                    <div className="mt-0.5">
                      <Calendar className="h-4 w-4 text-sky-500" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className={`text-sm ${!n.leida ? 'font-semibold text-slate-800' : 'text-slate-600'}`}>
                        {n.titulo}
                      </p>
                      {n.mensaje && (
                        <p className="text-xs text-slate-500 line-clamp-2">{n.mensaje}</p>
                      )}
                      <p className="text-[10px] text-slate-400 mt-1">
                        {new Date(n.created_at).toLocaleDateString('es-GT', {
                          day: 'numeric',
                          month: 'short',
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </p>
                    </div>
                    {!n.leida && <div className="w-2 h-2 bg-sky-500 rounded-full mt-1.5 shrink-0" />}
                  </div>
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  )
}
