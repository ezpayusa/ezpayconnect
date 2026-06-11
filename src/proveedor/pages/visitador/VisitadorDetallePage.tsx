import { useState, useEffect, useCallback, useMemo } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import {
  ArrowLeft, Loader2, AlertTriangle, MapPin, Clock, CheckCircle, CalendarCheck,
  Stethoscope, TrendingUp, Timer, ClipboardList,
} from 'lucide-react'

interface Visita {
  id: string
  medico_id: string | null
  fecha_visita: string | null
  hora_inicio: string | null
  hora_fin: string | null
  tipo_visita: string | null
  estado: string | null
  checkin_fecha: string | null
  checkout_fecha: string | null
  notas_empresa: string | null
}

const ESTADO_BADGE: Record<string, string> = {
  completada: 'bg-emerald-100 text-emerald-700',
  confirmada: 'bg-blue-100 text-blue-700',
  pendiente: 'bg-amber-100 text-amber-700',
  propuesta: 'bg-amber-100 text-amber-700',
  cancelada: 'bg-red-100 text-red-700',
  rechazada: 'bg-red-100 text-red-700',
}

export default function VisitadorDetallePage() {
  const { id } = useParams<{ id: string }>()
  const { puede } = useProveedorAuth()
  const [visitador, setVisitador] = useState<{ nombre_completo: string; email: string; telefono: string | null } | null>(null)
  const [visitas, setVisitas] = useState<Visita[]>([])
  const [medicos, setMedicos] = useState<Record<string, string>>({})
  const [loading, setLoading] = useState(true)
  const [rango, setRango] = useState<'todo' | '30d' | 'mes'>('todo')

  const cargar = useCallback(async () => {
    if (!id) return
    setLoading(true)

    const { data: cuenta } = await supabase
      .from('cuentas_proveedor')
      .select('nombre_completo, email, telefono')
      .eq('id', id)
      .single()
    setVisitador(cuenta || null)

    const { data: vis, error } = await supabase
      .from('visitas_agendadas')
      .select('id, medico_id, fecha_visita, hora_inicio, hora_fin, tipo_visita, estado, checkin_fecha, checkout_fecha, notas_empresa')
      .eq('cuenta_proveedor_id', id)
      .order('fecha_visita', { ascending: false })

    if (error) {
      toast.error('Error cargando visitas')
      console.error(error)
      setVisitas([])
    } else {
      const lista = (vis || []) as Visita[]
      setVisitas(lista)
      const ids = [...new Set(lista.map((v) => v.medico_id).filter(Boolean))] as string[]
      if (ids.length > 0) {
        const { data: meds } = await supabase.from('medicos').select('id, nombre_completo').in('id', ids)
        const map: Record<string, string> = {}
        ;(meds || []).forEach((m: any) => { map[m.id] = m.nombre_completo })
        setMedicos(map)
      }
    }
    setLoading(false)
  }, [id])

  useEffect(() => { cargar() }, [cargar])

  // Filtro por rango de fecha
  const visitasFiltradas = useMemo(() => {
    if (rango === 'todo') return visitas
    return visitas.filter((v) => {
      if (!v.fecha_visita) return false
      const f = new Date(v.fecha_visita)
      const hoy = new Date()
      if (rango === '30d') {
        const limite = new Date(hoy)
        limite.setDate(limite.getDate() - 30)
        return f >= limite
      }
      // este mes
      return f.getMonth() === hoy.getMonth() && f.getFullYear() === hoy.getFullYear()
    })
  }, [visitas, rango])

  const kpis = useMemo(() => {
    const total = visitasFiltradas.length
    const completadas = visitasFiltradas.filter((v) => v.estado === 'completada').length
    const pendientes = visitasFiltradas.filter((v) => ['confirmada', 'pendiente'].includes(v.estado || '')).length
    const propuestas = visitasFiltradas.filter((v) => v.estado === 'propuesta').length
    const canceladas = visitasFiltradas.filter((v) => ['cancelada', 'rechazada'].includes(v.estado || '')).length
    const tasa = total > 0 ? Math.round((completadas / total) * 100) : 0
    const medicosUnicos = new Set(visitasFiltradas.map((v) => v.medico_id).filter(Boolean)).size
    // Horas trabajadas: suma de (checkout - checkin) cuando ambos existen
    let horasMin = 0
    visitasFiltradas.forEach((v) => {
      if (v.checkin_fecha && v.checkout_fecha) {
        const diff = new Date(v.checkout_fecha).getTime() - new Date(v.checkin_fecha).getTime()
        if (diff > 0) horasMin += diff / 60000
      }
    })
    return { total, completadas, pendientes, propuestas, canceladas, tasa, medicosUnicos, horasMin }
  }, [visitasFiltradas])

  const fmtHoras = (min: number) => {
    if (min <= 0) return '0h'
    const h = Math.floor(min / 60)
    const m = Math.round(min % 60)
    return h > 0 ? `${h}h ${m}m` : `${m}m`
  }

  if (!puede('visitadores.gestionar')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">No tienes permiso para ver el desempeño de visitadores.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <Link to="/proveedor/visitadores" className="inline-flex items-center text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="w-4 h-4 mr-1" /> Volver a Visitadores
      </Link>

      {/* Encabezado */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="h-12 w-12 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold text-lg">
            {(visitador?.nombre_completo || '?').split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()}
          </div>
          <div>
            <h1 className="text-2xl font-bold">{visitador?.nombre_completo || 'Visitador'}</h1>
            <p className="text-sm text-muted-foreground">
              {visitador?.email}{visitador?.telefono ? ` · ${visitador.telefono}` : ''}
            </p>
          </div>
        </div>
        <select
          className="h-9 rounded-md border border-input bg-background px-3 text-sm"
          value={rango}
          onChange={(e) => setRango(e.target.value as any)}
        >
          <option value="todo">Todo el historial</option>
          <option value="30d">Últimos 30 días</option>
          <option value="mes">Este mes</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : (
        <>
          {/* KPIs */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <KpiCard icon={CalendarCheck} color="blue" valor={kpis.total} label="Visitas" />
            <KpiCard icon={CheckCircle} color="green" valor={kpis.completadas} label="Completadas" />
            <KpiCard icon={TrendingUp} color="indigo" valor={`${kpis.tasa}%`} label="Cumplimiento" />
            <KpiCard icon={Timer} color="amber" valor={fmtHoras(kpis.horasMin)} label="Horas trabajadas" />
            <KpiCard icon={Clock} color="amber" valor={kpis.pendientes} label="Pendientes" />
            <KpiCard icon={ClipboardList} color="slate" valor={kpis.propuestas} label="Propuestas" />
            <KpiCard icon={AlertTriangle} color="red" valor={kpis.canceladas} label="Canceladas" />
            <KpiCard icon={Stethoscope} color="slate" valor={kpis.medicosUnicos} label="Médicos visitados" />
          </div>

          {/* Lista de visitas */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <ClipboardList className="w-5 h-5" /> Visitas ({visitasFiltradas.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {visitasFiltradas.length === 0 ? (
                <div className="text-center py-10 text-muted-foreground">
                  <CalendarCheck className="mx-auto h-10 w-10 mb-3" />
                  <p>Sin visitas en este periodo.</p>
                </div>
              ) : (
                visitasFiltradas.map((v) => (
                  <div key={v.id} className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border rounded-lg p-3">
                    <div className="min-w-0">
                      <p className="font-medium flex items-center gap-2">
                        <Stethoscope className="w-4 h-4 text-muted-foreground" />
                        {v.medico_id ? medicos[v.medico_id] || 'Médico' : 'Médico'}
                      </p>
                      <p className="text-sm text-muted-foreground flex items-center gap-2 flex-wrap">
                        <span className="flex items-center gap-1">
                          <MapPin className="w-3 h-3" />
                          {v.fecha_visita ? new Date(v.fecha_visita).toLocaleDateString('es-GT') : '—'}
                        </span>
                        {v.hora_inicio && (
                          <span className="flex items-center gap-1">
                            <Clock className="w-3 h-3" /> {v.hora_inicio.slice(0, 5)}{v.hora_fin ? `–${v.hora_fin.slice(0, 5)}` : ''}
                          </span>
                        )}
                        {v.tipo_visita && <span>· {v.tipo_visita}</span>}
                        {v.checkin_fecha && v.checkout_fecha && (
                          <span className="text-emerald-600">· {fmtHoras((new Date(v.checkout_fecha).getTime() - new Date(v.checkin_fecha).getTime()) / 60000)} en sitio</span>
                        )}
                      </p>
                    </div>
                    <Badge className={ESTADO_BADGE[v.estado || ''] || 'bg-slate-100 text-slate-700'}>
                      {v.estado || '—'}
                    </Badge>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}

function KpiCard({ icon: Icon, color, valor, label }: { icon: React.ElementType; color: string; valor: React.ReactNode; label: string }) {
  const bg: Record<string, string> = {
    blue: 'bg-blue-100 text-blue-600',
    green: 'bg-green-100 text-green-600',
    indigo: 'bg-indigo-100 text-indigo-600',
    amber: 'bg-amber-100 text-amber-600',
    red: 'bg-red-100 text-red-600',
    slate: 'bg-slate-100 text-slate-600',
  }
  return (
    <Card>
      <CardContent className="p-4 flex items-center gap-3">
        <div className={`h-9 w-9 rounded-full flex items-center justify-center ${bg[color] || bg.slate}`}>
          <Icon className="w-4 h-4" />
        </div>
        <div>
          <p className="text-xl font-bold leading-tight">{valor}</p>
          <p className="text-xs text-muted-foreground">{label}</p>
        </div>
      </CardContent>
    </Card>
  )
}
