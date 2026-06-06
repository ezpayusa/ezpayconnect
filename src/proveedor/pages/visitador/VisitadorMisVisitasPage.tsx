import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Textarea } from '@/components/ui/textarea'
import { useVisitasAgendadas } from '@/proveedor/hooks/useVisitasAgendadas'
import { CalendarDays, ArrowLeft, Loader2, Clock, User, AlertCircle, MapPin, Camera, CheckCircle, XCircle } from 'lucide-react'

const estadoColor: Record<string, string> = {
  propuesta: 'bg-amber-100 text-amber-700',
  aprobada: 'bg-blue-100 text-blue-700',
  pendiente: 'bg-amber-100 text-amber-700',
  confirmada: 'bg-green-100 text-green-700',
  rechazada: 'bg-red-100 text-red-700',
  completada: 'bg-emerald-100 text-emerald-700',
  cancelada: 'bg-red-100 text-red-700',
  no_asistio: 'bg-slate-100 text-slate-700',
}

const TIPOS_VISITA: Record<string, string> = {
  presentacion_producto: 'Presentación',
  capacitacion: 'Capacitación',
  muestra_gratis: 'Muestra gratis',
  pedido: 'Pedido',
  otro: 'Otro',
}

export default function VisitadorMisVisitasPage() {
  const navigate = useNavigate()
  const { visitas, loading, cancelarVisita, checkinVisita, checkoutVisita, saving } = useVisitasAgendadas()
  const [visitaCheckout, setVisitaCheckout] = useState<string | null>(null)
  const [checkoutNotas, setCheckoutNotas] = useState('')

  const puedeCancelar = (v: typeof visitas[0]) => {
    // Propuesta: se puede cancelar libremente
    if (v.estado === 'propuesta') return true
    if (v.estado !== 'confirmada' && v.estado !== 'aprobada' && v.estado !== 'pendiente') return false
    const hoy = new Date()
    hoy.setHours(0, 0, 0, 0)
    const limite = v.fecha_limite_cancelacion ? new Date(v.fecha_limite_cancelacion) : null
    return !limite || hoy <= limite
  }

  const puedeCheckin = (v: typeof visitas[0]) => {
    if (v.estado !== 'confirmada' && v.estado !== 'aprobada') return false
    const hoy = new Date()
    const fechaVisita = new Date(v.fecha_visita)
    return hoy.toDateString() === fechaVisita.toDateString()
  }

  const puedeCheckout = (v: typeof visitas[0]) => {
    return (v.estado === 'confirmada' || v.estado === 'aprobada') && !!v.checkin_fecha && !v.checkout_fecha
  }

  const handleCheckin = async (id: string) => {
    // Opcional: pedir foto
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/*'
    input.capture = 'environment'
    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0]
      await checkinVisita(id, file)
    }
    input.click()
  }

  const handleCheckoutSubmit = async () => {
    if (!visitaCheckout) return
    await checkoutVisita(visitaCheckout, checkoutNotas)
    setVisitaCheckout(null)
    setCheckoutNotas('')
  }

  const propuestas = visitas.filter((v) => v.estado === 'propuesta')
  const confirmadas = visitas.filter((v) => ['confirmada', 'aprobada', 'pendiente'].includes(v.estado))
  const pasadas = visitas.filter((v) => ['completada', 'cancelada', 'no_asistio', 'rechazada'].includes(v.estado))

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/visitador/planes')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Mis Visitas</h1>
          <p className="text-sm text-muted-foreground">Calendario y estado de tus visitas agendadas</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => navigate('/proveedor/visitador/ruta')}>
            Mi ruta
          </Button>
          <Button variant="outline" size="sm" onClick={() => navigate('/proveedor/visitador/reporte')}>
            Ver reporte completo
          </Button>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : visitas.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <CalendarDays className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">Sin visitas agendadas</h3>
            <Button className="mt-4 bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate('/proveedor/visitador/agendar')}>
              Agendar primera visita
            </Button>
          </CardContent>
        </Card>
      ) : (
        <>
          {propuestas.length > 0 && (
            <div className="space-y-3">
              <h2 className="text-lg font-semibold flex items-center gap-2">
                <Clock className="h-5 w-5 text-amber-500" />
                Mis propuestas pendientes
              </h2>
              {propuestas.map((v) => (
                <Card key={v.id} className="border-amber-200">
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between gap-4 flex-wrap">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <Badge className={estadoColor[v.estado]}>Propuesta pendiente</Badge>
                          <Badge variant="outline">{TIPOS_VISITA[v.tipo_visita] || v.tipo_visita}</Badge>
                        </div>
                        <h3 className="font-semibold text-gray-900 flex items-center gap-2">
                          <User className="h-4 w-4 text-[#1E5C8E]" />
                          {v.medico?.nombre_completo || 'Médico'}
                        </h3>
                        <p className="text-sm text-muted-foreground mt-1">
                          <CalendarDays className="h-3.5 w-3.5 inline mr-1" />
                          {v.fecha_visita} • {v.hora_inicio} – {v.hora_fin}
                        </p>
                        <p className="text-xs text-amber-600 mt-1">
                          ⏳ Esperando aprobación del administrador
                        </p>
                      </div>
                      <div className="flex flex-col gap-2">
                        {puedeCancelar(v) && (
                          <Button size="sm" variant="outline" className="text-red-600 hover:bg-red-50" onClick={() => cancelarVisita(v.id)}>
                            <XCircle className="h-4 w-4 mr-1" />
                            Cancelar
                          </Button>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}

          {confirmadas.length > 0 && (
            <div className="space-y-3">
              <h2 className="text-lg font-semibold flex items-center gap-2">
                <CheckCircle className="h-5 w-5 text-green-600" />
                Visitas confirmadas
              </h2>
              {confirmadas.map((v) => (
                <Card key={v.id}>
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between gap-4 flex-wrap">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <Badge className={estadoColor[v.estado]}>{v.estado}</Badge>
                          <Badge variant="outline">{TIPOS_VISITA[v.tipo_visita] || v.tipo_visita}</Badge>
                          {v.fecha_limite_cancelacion && (
                            <span className="text-xs text-muted-foreground">
                              Cancelar hasta: {v.fecha_limite_cancelacion}
                            </span>
                          )}
                        </div>
                        <h3 className="font-semibold text-gray-900 flex items-center gap-2">
                          <User className="h-4 w-4 text-[#1E5C8E]" />
                          {v.medico?.nombre_completo || 'Médico'}
                        </h3>
                        <p className="text-sm text-muted-foreground mt-1">
                          <CalendarDays className="h-3.5 w-3.5 inline mr-1" />
                          {v.fecha_visita} • {v.hora_inicio} – {v.hora_fin}
                        </p>
                        {v.checkin_fecha && (
                          <p className="text-xs text-emerald-600 mt-1 flex items-center gap-1">
                            <MapPin className="h-3 w-3" />
                            Check-in: {new Date(v.checkin_fecha).toLocaleString()}
                          </p>
                        )}
                      </div>
                      <div className="flex flex-col gap-2">
                        {puedeCheckin(v) && (
                          <Button size="sm" className="bg-blue-600 hover:bg-blue-700 text-white" disabled={saving} onClick={() => handleCheckin(v.id)}>
                            <Camera className="h-4 w-4 mr-1" />
                            Check-in
                          </Button>
                        )}
                        {puedeCheckout(v) && (
                          <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={saving} onClick={() => setVisitaCheckout(v.id)}>
                            <CheckCircle className="h-4 w-4 mr-1" />
                            Check-out
                          </Button>
                        )}
                        {puedeCancelar(v) && (
                          <Button size="sm" variant="outline" className="text-red-600 hover:bg-red-50" onClick={() => cancelarVisita(v.id)}>
                            <XCircle className="h-4 w-4 mr-1" />
                            Cancelar
                          </Button>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}

          {pasadas.length > 0 && (
            <div className="space-y-3">
              <h2 className="text-lg font-semibold flex items-center gap-2">
                <AlertCircle className="h-5 w-5 text-slate-500" />
                Historial
              </h2>
              {pasadas.map((v) => (
                <Card key={v.id} className="opacity-70">
                  <CardContent className="p-4">
                    <div className="flex items-center gap-2 mb-1">
                      <Badge className={estadoColor[v.estado]}>{v.estado}</Badge>
                      <span className="text-sm text-muted-foreground">{TIPOS_VISITA[v.tipo_visita] || v.tipo_visita}</span>
                    </div>
                    <p className="text-sm font-medium">{v.medico?.nombre_completo || 'Médico'}</p>
                    <p className="text-sm text-muted-foreground">{v.fecha_visita} • {v.hora_inicio} – {v.hora_fin}</p>
                    {v.visita_concretada && (
                      <p className="text-xs text-emerald-600 mt-1">✓ Visita concretada</p>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </>
      )}

      <Dialog open={!!visitaCheckout} onOpenChange={() => setVisitaCheckout(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Check-out de visita</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">Registra lo que se conversó o entregó en la visita.</p>
            <Textarea
              value={checkoutNotas}
              onChange={(e) => setCheckoutNotas(e.target.value)}
              placeholder="Productos presentados, muestras entregadas, acuerdos, observaciones..."
              rows={4}
            />
            <div className="flex gap-3">
              <Button variant="outline" className="flex-1" onClick={() => setVisitaCheckout(null)}>Cancelar</Button>
              <Button className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white" disabled={saving} onClick={handleCheckoutSubmit}>
                Guardar check-out
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
