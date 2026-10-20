import { useCallback, useEffect, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Loader2, UserPlus, X } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { useEnrolamiento } from '@/visitador/hooks/useEnrolamiento'
import { usePuedeEnrolar } from '@/visitador/hooks/usePuedeEnrolar'
import { badgeEstadoSolicitud, puedeCancelarSolicitud, type SolicitudAlta } from '@/visitador/lib/enrolamiento'

// Mis solicitudes de alta (listar_solicitudes_alta, mig 377): el visitador ve las suyas. Solo una pendiente se
// puede cancelar (cancelar_solicitud_alta; si cambió de estado con la lista abierta, PV022 y se recarga).
const fechaCorta = (iso: string) => {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('es', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function SolicitudesPage() {
  const navigate = useNavigate()
  const { listarSolicitudes, cancelarSolicitud } = useEnrolamiento()
  const { puedeEnrolar, loading } = usePuedeEnrolar()
  const [solicitudes, setSolicitudes] = useState<SolicitudAlta[]>([])
  const [cargando, setCargando] = useState(true)
  const [cancelando, setCancelando] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    setCargando(true)
    const r = await listarSolicitudes()
    if (r.ok) setSolicitudes(r.data)
    else toast.error(r.error.mensaje)
    setCargando(false)
  }, [listarSolicitudes])

  // Solo con el gate: sin él la RPC devolvería 0 filas igual, pero no se consulta ni se muestra la pantalla.
  useEffect(() => { if (puedeEnrolar) cargar() }, [cargar, puedeEnrolar])

  const cancelar = async (s: SolicitudAlta) => {
    if (!window.confirm(`¿Cancelar la solicitud de alta de ${s.nombre_completo}?`)) return
    setCancelando(s.id)
    const r = await cancelarSolicitud(s.id)
    setCancelando(null)
    if (!r.ok) {
      toast.error(r.error.mensaje)
      if (r.error.recargar === 'solicitudes') cargar()
      return
    }
    toast.success('Solicitud cancelada.')
    cargar()
  }

  if (loading) {
    return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }
  // Gate visual (pieza 6). La RPC no le devuelve nada a quien no corresponde.
  if (!puedeEnrolar) return <Navigate to="/visitador/agendar" replace />

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2">
        <h1 className="text-xl font-bold text-gray-900">Mis solicitudes</h1>
        <Button size="sm" className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate('/visitador/solicitar-alta')}>
          <UserPlus className="h-4 w-4 mr-1" /> Solicitar alta
        </Button>
      </div>

      {cargando ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : solicitudes.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-6 text-center text-sm text-muted-foreground">
            Todavía no tienes solicitudes de alta.
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-3">
          {solicitudes.map((s) => {
            const badge = badgeEstadoSolicitud(s.estado)
            return (
              <li key={s.id} data-testid="solicitud">
                <Card>
                  <CardContent className="p-4 space-y-2 text-sm">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="font-semibold break-words">{s.nombre_completo}</p>
                        <p className="text-muted-foreground break-all">{s.email}</p>
                        {s.especialidad_nombre && <p className="text-muted-foreground">{s.especialidad_nombre}</p>}
                      </div>
                      <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${badge.clase}`} data-testid="badge-estado">
                        {badge.label}
                      </span>
                    </div>
                    {s.estado === 'rechazada' && s.motivo_rechazo && (
                      <p className="rounded-md bg-red-50 p-2 text-red-700" data-testid="motivo-rechazo">Motivo: {s.motivo_rechazo}</p>
                    )}
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs text-muted-foreground">{fechaCorta(s.created_at)}</span>
                      {puedeCancelarSolicitud(s.estado) && (
                        <Button size="sm" variant="outline" disabled={cancelando === s.id} onClick={() => cancelar(s)}>
                          {cancelando === s.id ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <X className="h-4 w-4 mr-1" />}
                          Cancelar
                        </Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
