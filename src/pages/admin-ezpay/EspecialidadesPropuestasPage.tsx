import { useState, useCallback, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Stethoscope, Loader2, CheckCircle2, XCircle, ShieldAlert } from 'lucide-react'

interface Propuesta {
  id: string
  nombre_propuesto: string
  estado: 'pendiente' | 'aprobada' | 'rechazada'
  created_at: string
  resolved_at: string | null
  resolved_by: string | null
  medico_id: string
  medico_nombre: string | null
  resolved_by_nombre: string | null
}

// Filtro por estado (canjes no tiene esto). 'todas' => sin p_estado.
type Filtro = 'pendiente' | 'aprobada' | 'rechazada' | 'todas'
const FILTROS: { key: Filtro; label: string }[] = [
  { key: 'pendiente', label: 'Pendientes' },
  { key: 'aprobada', label: 'Aprobadas' },
  { key: 'rechazada', label: 'Rechazadas' },
  { key: 'todas', label: 'Todas' },
]

const badgeClase: Record<Propuesta['estado'], string> = {
  pendiente: 'text-orange-600 border-orange-200 bg-orange-50',
  aprobada: 'text-emerald-600 border-emerald-200 bg-emerald-50',
  rechazada: 'text-slate-500 border-slate-200 bg-slate-50',
}

export default function EspecialidadesPropuestasPage() {
  const [propuestas, setPropuestas] = useState<Propuesta[]>([])
  const [loading, setLoading] = useState(true)
  const [noAutorizado, setNoAutorizado] = useState(false)
  const [resolviendo, setResolviendo] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<Filtro>('pendiente')  // lo más accionable primero

  const cargar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('listar_propuestas_especialidad', {
      p_estado: filtro === 'todas' ? null : filtro,
    })
    setLoading(false)
    if (error) {
      if (/no_autorizado/.test(error.message || '')) { setNoAutorizado(true); return }
      toast.error('Error cargando propuestas: ' + error.message)
      return
    }
    setPropuestas((Array.isArray(data) ? data : []) as Propuesta[])
  }, [filtro])

  useEffect(() => { cargar() }, [cargar])

  const resolver = async (p: Propuesta, aprobar: boolean) => {
    setResolviendo(p.id)
    const { error } = await supabase.rpc('resolver_propuesta_especialidad', {
      p_propuesta_id: p.id,
      p_aprobar: aprobar,
    })
    setResolviendo(null)
    if (error) {
      const m = error.message || ''
      if (/propuesta_ya_resuelta/.test(m)) {
        toast.info('Esa propuesta ya fue resuelta por otro administrador.')
      } else if (/no_autorizado/.test(m)) {
        setNoAutorizado(true)
      } else {
        toast.error('Error: ' + m)
      }
      await cargar() // refrescar en cualquier caso
      return
    }
    toast.success(aprobar ? 'Especialidad aprobada — ya disponible en el catálogo' : 'Propuesta rechazada')
    await cargar()
  }

  if (noAutorizado) {
    return (
      <div className="p-8">
        <div className="flex items-center gap-3 text-red-600 bg-red-50 border border-red-200 rounded-lg p-4 max-w-md">
          <ShieldAlert className="h-5 w-5 shrink-0" />
          <p className="text-sm">No autorizado: esta sección es solo para super administradores.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
          <Stethoscope className="h-6 w-6 text-sky-500" /> Especialidades propuestas
        </h1>
        <p className="text-slate-500 mt-1">Propuestas de especialidad enviadas por médicos, pendientes de aprobación</p>
      </div>

      {/* Filtro por estado */}
      <div className="flex flex-wrap gap-2">
        {FILTROS.map((f) => (
          <Button
            key={f.key}
            size="sm"
            variant={filtro === f.key ? 'default' : 'outline'}
            className={filtro === f.key ? 'bg-sky-600 hover:bg-sky-700' : ''}
            onClick={() => setFiltro(f.key)}
          >
            {f.label}
          </Button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
      ) : propuestas.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-slate-500 text-sm">No hay propuestas en este estado.</CardContent></Card>
      ) : (
        <div className="space-y-3">
          {propuestas.map((p) => (
            <Card key={p.id} className="bg-white">
              <CardContent className="p-4 flex flex-col md:flex-row md:items-center md:justify-between gap-3">
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-slate-800">{p.nombre_propuesto}</span>
                    <Badge variant="outline" className={`text-[10px] capitalize ${badgeClase[p.estado]}`}>{p.estado}</Badge>
                  </div>
                  <p className="text-sm text-slate-500 mt-1">
                    Médico: <span className="font-medium text-slate-700">{p.medico_nombre || '—'}</span> (#{p.medico_id.slice(0, 8)})
                    · {new Date(p.created_at).toLocaleString('es-GT')}
                  </p>
                  {p.estado !== 'pendiente' && (
                    <p className="text-xs text-slate-400 mt-0.5">
                      Resuelta por {p.resolved_by_nombre || '—'}
                      {p.resolved_at ? ` · ${new Date(p.resolved_at).toLocaleString('es-GT')}` : ''}
                    </p>
                  )}
                </div>
                {p.estado === 'pendiente' && (
                  <div className="flex gap-2 shrink-0">
                    <Button
                      size="sm" variant="outline"
                      className="border-red-200 text-red-600 hover:bg-red-50"
                      disabled={resolviendo === p.id}
                      onClick={() => resolver(p, false)}
                    >
                      <XCircle className="h-4 w-4 mr-1" /> Rechazar
                    </Button>
                    <Button
                      size="sm" className="bg-emerald-600 hover:bg-emerald-700"
                      disabled={resolviendo === p.id}
                      onClick={() => resolver(p, true)}
                    >
                      {resolviendo === p.id ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
                      Aprobar
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
