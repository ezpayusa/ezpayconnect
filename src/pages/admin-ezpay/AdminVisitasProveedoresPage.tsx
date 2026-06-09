import { useState, useEffect, useCallback } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import { toast } from 'sonner'
import { CalendarDays, MapPin, CheckCircle, Loader2, Search, User } from 'lucide-react'

interface VisitaAdmin {
  id: string
  empresa_nombre: string
  medico_nombre: string
  fecha_visita: string
  hora_inicio: string
  hora_fin: string
  tipo_visita: string
  estado: string
  checkout_notas: string
  checkin_fecha: string
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

export default function AdminVisitasProveedoresPage() {
  const [visitas, setVisitas] = useState<VisitaAdmin[]>([])
  const [loading, setLoading] = useState(false)
  const [filtroEmpresa, setFiltroEmpresa] = useState('')
  const [filtroEstado, setFiltroEstado] = useState('')
  const { paisId } = usePaisFiltro()

  const cargar = useCallback(async () => {
    setLoading(true)
    let query = supabase
      .from('visitas_agendadas')
      .select(`
        id, fecha_visita, hora_inicio, hora_fin, tipo_visita, estado,
        checkout_notas, checkin_fecha, visita_concretada,
        medico:medico_id(nombre_completo),
        empresa:empresa_id(nombre_empresa)
      `)
      .order('fecha_visita', { ascending: false })
      .limit(200)
    if (paisId) query = query.eq('pais_id', paisId)
    const { data, error } = await query

    if (error) {
      toast.error('Error cargando visitas')
      console.error(error)
    } else {
      const mapped = (data || []).map((v: any) => ({
        id: v.id,
        empresa_nombre: v.empresa?.nombre_empresa || 'Desconocida',
        medico_nombre: v.medico?.nombre_completo || 'Desconocido',
        fecha_visita: v.fecha_visita,
        hora_inicio: v.hora_inicio,
        hora_fin: v.hora_fin,
        tipo_visita: v.tipo_visita,
        estado: v.estado,
        checkout_notas: v.checkout_notas,
        checkin_fecha: v.checkin_fecha,
        visita_concretada: v.visita_concretada,
      }))
      setVisitas(mapped)
    }
    setLoading(false)
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const filtradas = visitas.filter((v) => {
    const matchEmpresa = v.empresa_nombre.toLowerCase().includes(filtroEmpresa.toLowerCase())
    const matchEstado = !filtroEstado || v.estado === filtroEstado
    return matchEmpresa && matchEstado
  })

  const total = filtradas.length
  const concretadas = filtradas.filter((v) => v.visita_concretada).length
  const canceladas = filtradas.filter((v) => v.estado === 'cancelada').length
  const noAsistio = filtradas.filter((v) => v.estado === 'no_asistio').length
  const tasaConcrecion = total > 0 ? Math.round((concretadas / total) * 100) : 0

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
          <CalendarDays className="h-6 w-6 text-[#1E5C8E]" />
          Visitas de Proveedores
        </h1>
        <p className="text-slate-500 mt-1">Monitoreo de visitas médicas concretadas y canceladas</p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-[#1E5C8E]">{total}</div><div className="text-xs text-muted-foreground">Total</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-emerald-600">{concretadas}</div><div className="text-xs text-muted-foreground">Concretadas</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-red-600">{canceladas}</div><div className="text-xs text-muted-foreground">Canceladas</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-slate-600">{noAsistio}</div><div className="text-xs text-muted-foreground">No asistió</div>
        </CardContent></Card>
        <Card><CardContent className="p-4 text-center">
          <div className="text-2xl font-bold text-blue-600">{tasaConcrecion}%</div><div className="text-xs text-muted-foreground">Tasa concreción</div>
        </CardContent></Card>
      </div>

      {/* Filtros */}
      <div className="flex flex-col md:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input placeholder="Buscar empresa..." value={filtroEmpresa} onChange={(e) => setFiltroEmpresa(e.target.value)} className="pl-9" />
        </div>
        <select value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)} className="h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">
          <option value="">Todos los estados</option>
          <option value="pendiente">Pendiente</option>
          <option value="confirmada">Confirmada</option>
          <option value="completada">Completada</option>
          <option value="cancelada">Cancelada</option>
          <option value="no_asistio">No asistió</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : filtradas.length === 0 ? (
        <Card className="bg-gray-50 border-dashed"><CardContent className="p-8 text-center text-slate-500">No hay visitas registradas</CardContent></Card>
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
                    <div className="flex items-center gap-4 text-sm">
                      <span className="font-medium flex items-center gap-1"><MapPin className="h-3.5 w-3.5 text-slate-400" />{v.empresa_nombre}</span>
                      <span className="flex items-center gap-1"><User className="h-3.5 w-3.5 text-slate-400" />{v.medico_nombre}</span>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">
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
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
