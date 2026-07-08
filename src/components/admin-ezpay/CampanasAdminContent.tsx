import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import { useMetricasCampanaAdmin } from '@/hooks/admin/useMetricasCampanaAdmin'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import {
  Megaphone,
  Eye,
  MousePointerClick,
  TrendingUp,
  Search,
  RefreshCw,
  Trash2,
  EyeOff,
  ArrowLeft,
  Globe,
} from 'lucide-react'

interface CampanaAdmin {
  id: number
  titulo: string
  descripcion: string | null
  tipo: string
  imagen_url: string | null
  link_url: string | null
  fecha_inicio: string
  fecha_fin: string
  activa: boolean
  pais_id: string
  pais_nombre?: string
  impresiones?: number
  clicks?: number
  ctr?: number
}

export default function CampanasAdminContent() {
  const navigate = useNavigate()
  const { paisId } = usePaisFiltro()
  const { metricasDetalle, loading: loadingMetricas, fetchMetricasPorPais } = useMetricasCampanaAdmin()
  const [campanas, setCampanas] = useState<CampanaAdmin[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filtroActiva, setFiltroActiva] = useState<'todas' | 'activas' | 'inactivas'>('todas')

  const cargarCampanas = useCallback(async () => {
    setLoading(true)
    let query = supabase
      .from('campanas_publicitarias')
      .select('*')
      .order('created_at', { ascending: false })

    if (paisId) query = query.eq('pais_id', paisId)

    const { data, error } = await query

    if (error) {
      console.error('Error cargando campañas:', error)
    } else {
      setCampanas(data || [])
    }
    setLoading(false)
  }, [paisId])

  useEffect(() => {
    cargarCampanas()
    if (paisId) fetchMetricasPorPais(paisId)
  }, [cargarCampanas, fetchMetricasPorPais, paisId])

  const toggleActiva = async (id: number, nuevaActiva: boolean) => {
    const { error } = await supabase
      .from('campanas_publicitarias')
      .update({ activa: nuevaActiva })
      .eq('id', id)

    if (!error) {
      setCampanas((prev) => prev.map((c) => (c.id === id ? { ...c, activa: nuevaActiva } : c)))
    }
  }

  const eliminarCampana = async (id: number) => {
    if (!confirm('¿Eliminar esta campaña permanentemente?')) return
    const { error } = await supabase.from('campanas_publicitarias').delete().eq('id', id)
    if (!error) {
      setCampanas((prev) => prev.filter((c) => c.id !== id))
    }
  }

  const campanasFiltradas = campanas.filter((c) => {
    const matchSearch = !search || c.titulo.toLowerCase().includes(search.toLowerCase())
    const matchActiva =
      filtroActiva === 'todas' ||
      (filtroActiva === 'activas' && c.activa) ||
      (filtroActiva === 'inactivas' && !c.activa)
    return matchSearch && matchActiva
  })

  const totalImpresiones = metricasDetalle.reduce((sum, m) => sum + m.impresiones, 0)
  const totalClicks = metricasDetalle.reduce((sum, m) => sum + m.clicks, 0)
  const ctrPromedio = totalImpresiones > 0 ? Math.round((totalClicks / totalImpresiones) * 100 * 100) / 100 : 0
  const activas = campanas.filter((c) => c.activa).length

  const metricasMap = new Map(metricasDetalle.map((m) => [m.campana_id, m]))

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Campañas Publicitarias</h1>
            <p className="text-sm text-muted-foreground">
              {paisId ? `Filtrado por país activo` : 'Mostrando todas las campañas'}
            </p>
          </div>
        </div>
        <Button variant="outline" onClick={cargarCampanas}>
          <RefreshCw className="h-4 w-4 mr-2" /> Recargar
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-purple-100 rounded-lg">
                <Megaphone className="h-5 w-5 text-purple-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Campañas Activas</p>
                <p className="text-xl font-bold">{activas}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 rounded-lg">
                <Eye className="h-5 w-5 text-blue-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Impresiones</p>
                <p className="text-xl font-bold">{totalImpresiones.toLocaleString()}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-emerald-100 rounded-lg">
                <MousePointerClick className="h-5 w-5 text-emerald-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Clicks</p>
                <p className="text-xl font-bold">{totalClicks.toLocaleString()}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-amber-100 rounded-lg">
                <TrendingUp className="h-5 w-5 text-amber-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">CTR Promedio</p>
                <p className="text-xl font-bold">{ctrPromedio}%</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filtros */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <Input
            placeholder="Buscar campaña..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <div className="flex gap-2">
          {(['todas', 'activas', 'inactivas'] as const).map((f) => (
            <Button
              key={f}
              variant={filtroActiva === f ? 'default' : 'outline'}
              size="sm"
              onClick={() => setFiltroActiva(f)}
            >
              {f === 'todas' ? 'Todas' : f === 'activas' ? 'Activas' : 'Inactivas'}
            </Button>
          ))}
        </div>
      </div>

      {/* Tabla */}
      {loading || loadingMetricas ? (
        <div className="flex justify-center py-12">
          <RefreshCw className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : campanasFiltradas.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Megaphone className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">No hay campañas</h3>
            <p className="text-sm text-muted-foreground">
              {paisId ? 'No hay campañas para el país seleccionado.' : 'No hay campañas registradas.'}
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Campaña</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Tipo</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Vigencia</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Impresiones</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Clicks</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">CTR</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Estado</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Acciones</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {campanasFiltradas.map((c) => {
                const m = metricasMap.get(c.id)
                const impresiones = m?.impresiones || 0
                const clicks = m?.clicks || 0
                const ctr = impresiones > 0 ? Math.round((clicks / impresiones) * 100 * 100) / 100 : 0
                const vencida = new Date(c.fecha_fin) < new Date()

                return (
                  <tr key={c.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {c.imagen_url ? (
                          <img src={c.imagen_url} alt="" className="w-10 h-10 rounded object-cover" />
                        ) : (
                          <div className="w-10 h-10 rounded bg-gray-100 flex items-center justify-center">
                            <Megaphone className="h-4 w-4 text-gray-400" />
                          </div>
                        )}
                        <div>
                          <p className="font-medium text-gray-900">{c.titulo}</p>
                          {c.link_url && (
                            <a href={c.link_url} target="_blank" rel="noreferrer" className="text-xs text-blue-600 hover:underline">
                              {c.link_url.substring(0, 30)}...
                            </a>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <Badge variant="outline">{c.tipo}</Badge>
                    </td>
                    <td className="px-4 py-3 text-gray-500">
                      {c.fecha_inicio} → {c.fecha_fin}
                      {vencida && <span className="ml-1 text-red-500 text-xs">(vencida)</span>}
                    </td>
                    <td className="px-4 py-3">{impresiones.toLocaleString()}</td>
                    <td className="px-4 py-3">{clicks.toLocaleString()}</td>
                    <td className="px-4 py-3">
                      <span className={ctr >= 2 ? 'text-emerald-600 font-medium' : ctr >= 0.5 ? 'text-amber-600' : 'text-gray-400'}>
                        {ctr}%
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {c.activa && !vencida ? (
                        <Badge className="bg-emerald-100 text-emerald-700">Activa</Badge>
                      ) : c.activa && vencida ? (
                        <Badge className="bg-red-100 text-red-700">Vencida</Badge>
                      ) : (
                        <Badge className="bg-gray-100 text-gray-700">Inactiva</Badge>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end gap-1">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => toggleActiva(c.id, !c.activa)}
                          title={c.activa ? 'Desactivar' : 'Activar'}
                        >
                          {c.activa ? <EyeOff className="h-4 w-4 text-amber-600" /> : <Eye className="h-4 w-4 text-emerald-600" />}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => eliminarCampana(c.id)}
                          title="Eliminar"
                        >
                          <Trash2 className="h-4 w-4 text-red-600" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
