import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { toast } from 'sonner'
import { ArrowLeft, CalendarDays, MapPin, CheckCircle, Loader2, Search, User } from 'lucide-react'

interface VisitaReporte {
  id: string
  medico_nombre: string
  medico_email: string
  fecha_visita: string
  hora_inicio: string
  hora_fin: string
  tipo_visita: string
  estado: string
  notas_empresa: string
  checkout_notas: string
  checkin_fecha: string
  checkin_evidencia_url: string
  visita_concretada: boolean
}

const estadoColor: Record<string, string> = {
  pendiente: 'bg-amber-100 text-amber-700',
  confirmada: 'bg-blue-100 text-blue-700',
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

export default function ProveedorReporteVisitasPage() {
  const navigate = useNavigate()
  const { empresa } = useProveedorAuth()
  const [visitas, setVisitas] = useState<VisitaReporte[]>([])
  const [loading, setLoading] = useState(false)
  const [filtroMedico, setFiltroMedico] = useState('')
  const [fechaDesde, setFechaDesde] = useState('')
  const [fechaHasta, setFechaHasta] = useState('')

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('visitas_agendadas')
      .select(`
        id, fecha_visita, hora_inicio, hora_fin, tipo_visita, estado,
        notas_empresa, checkout_notas, checkin_fecha, checkin_evidencia_url, visita_concretada,
        medico:medico_id(nombre_completo, email)
      `)
      .eq('empresa_id', empresa.id)
      .order('fecha_visita', { ascending: false })

    if (error) {
      toast.error('Error cargando reporte')
      console.error(error)
    } else {
      const mapped = (data || []).map((v: any) => ({
        id: v.id,
        medico_nombre: v.medico?.nombre_completo || 'Desconocido',
        medico_email: v.medico?.email || '',
        fecha_visita: v.fecha_visita,
        hora_inicio: v.hora_inicio,
        hora_fin: v.hora_fin,
        tipo_visita: v.tipo_visita,
        estado: v.estado,
        notas_empresa: v.notas_empresa,
        checkout_notas: v.checkout_notas,
        checkin_fecha: v.checkin_fecha,
        checkin_evidencia_url: v.checkin_evidencia_url,
        visita_concretada: v.visita_concretada,
      }))
      setVisitas(mapped)
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => { cargar() }, [cargar])

  const filtradas = visitas.filter((v) => {
    const matchMedico = v.medico_nombre.toLowerCase().includes(filtroMedico.toLowerCase())
    const matchDesde = !fechaDesde || v.fecha_visita >= fechaDesde
    const matchHasta = !fechaHasta || v.fecha_visita <= fechaHasta
    return matchMedico && matchDesde && matchHasta
  })

  const concretadas = filtradas.filter((v) => v.visita_concretada).length
  const canceladas = filtradas.filter((v) => v.estado === 'cancelada').length
  const noAsistio = filtradas.filter((v) => v.estado === 'no_asistio').length
  const total = filtradas.length

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/visitador/mis-visitas')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Reporte de Visitas</h1>
          <p className="text-sm text-muted-foreground">Historial completo de visitas a médicos</p>
        </div>
      </div>

      {/* Resumen */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-[#1E5C8E]">{total}</div>
          <div className="text-xs text-muted-foreground">Total visitas</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-emerald-600">{concretadas}</div>
          <div className="text-xs text-muted-foreground">Concretadas</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-red-600">{canceladas}</div>
          <div className="text-xs text-muted-foreground">Canceladas</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-slate-600">{noAsistio}</div>
          <div className="text-xs text-muted-foreground">No asistió</div>
        </CardContent></Card>
      </div>

      {/* Filtros */}
      <div className="flex flex-col md:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input placeholder="Buscar médico..." value={filtroMedico} onChange={(e) => setFiltroMedico(e.target.value)} className="pl-9" />
        </div>
        <Input type="date" placeholder="Desde" value={fechaDesde} onChange={(e) => setFechaDesde(e.target.value)} className="w-auto" />
        <Input type="date" placeholder="Hasta" value={fechaHasta} onChange={(e) => setFechaHasta(e.target.value)} className="w-auto" />
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : filtradas.length === 0 ? (
        <Card className="bg-gray-50 border-dashed"><CardContent className="p-8 text-center text-slate-500">No hay visitas en el período seleccionado</CardContent></Card>
      ) : (
        <div className="space-y-3">
          {filtradas.map((v) => (
            <Card key={v.id}>
              <CardContent className="p-4">
                <div className="flex items-start justify-between gap-4 flex-wrap">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1 flex-wrap">
                      <Badge className={estadoColor[v.estado]}>{v.estado}</Badge>
                      <Badge variant="outline">{TIPOS_VISITA[v.tipo_visita] || v.tipo_visita}</Badge>
                      {v.visita_concretada && <Badge className="bg-emerald-100 text-emerald-700">Concretada</Badge>}
                    </div>
                    <h3 className="font-semibold text-gray-900 flex items-center gap-2">
                      <User className="h-4 w-4 text-[#1E5C8E]" />
                      {v.medico_nombre}
                    </h3>
                    <p className="text-sm text-muted-foreground">
                      <CalendarDays className="h-3.5 w-3.5 inline mr-1" />
                      {v.fecha_visita} • {v.hora_inicio} – {v.hora_fin}
                    </p>
                    {v.checkin_fecha && (
                      <p className="text-xs text-blue-600 mt-1 flex items-center gap-1">
                        <MapPin className="h-3 w-3" />
                        Check-in: {new Date(v.checkin_fecha).toLocaleString()}
                      </p>
                    )}
                    {v.checkout_notas && (
                      <p className="text-sm text-muted-foreground mt-2 bg-gray-50 p-2 rounded">
                        <CheckCircle className="h-3.5 w-3.5 inline mr-1 text-emerald-500" />
                        {v.checkout_notas}
                      </p>
                    )}
                  </div>
                  {v.checkin_evidencia_url && (
                    <a href={v.checkin_evidencia_url} target="_blank" rel="noopener noreferrer" className="shrink-0">
                      <img src={v.checkin_evidencia_url} alt="Evidencia" className="h-20 w-20 object-cover rounded-lg border" />
                    </a>
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
