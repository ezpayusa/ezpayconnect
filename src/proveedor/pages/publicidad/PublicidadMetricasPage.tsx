import { useNavigate } from 'react-router-dom'
import { useMetricasCampana } from '@/proveedor/hooks/useMetricasCampana'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { ArrowLeft, Eye, MousePointer, Users, TrendingUp, Megaphone, BarChart3 } from 'lucide-react'

export default function PublicidadMetricasPage() {
  const navigate = useNavigate()
  const { metricas, loading } = useMetricasCampana()

  const totalImpresiones = metricas.reduce((sum, m) => sum + m.impresiones, 0)
  const totalClicks = metricas.reduce((sum, m) => sum + m.clicks, 0)
  const ctrGlobal = totalImpresiones > 0 ? (totalClicks / totalImpresiones) * 100 : 0

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/publicidad/campanas')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Métricas de Publicidad</h1>
          <p className="text-sm text-muted-foreground">Rendimiento de tus campañas publicadas</p>
        </div>
      </div>

      {/* Resumen global */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 text-center">
            <Eye className="h-5 w-5 text-blue-600 mx-auto mb-1" />
            <div className="text-2xl font-bold">{totalImpresiones.toLocaleString()}</div>
            <div className="text-xs text-muted-foreground">Impresiones totales</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <MousePointer className="h-5 w-5 text-emerald-600 mx-auto mb-1" />
            <div className="text-2xl font-bold">{totalClicks.toLocaleString()}</div>
            <div className="text-xs text-muted-foreground">Clicks totales</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <TrendingUp className="h-5 w-5 text-purple-600 mx-auto mb-1" />
            <div className="text-2xl font-bold">{ctrGlobal.toFixed(1)}%</div>
            <div className="text-xs text-muted-foreground">CTR global</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <Megaphone className="h-5 w-5 text-amber-600 mx-auto mb-1" />
            <div className="text-2xl font-bold">{metricas.length}</div>
            <div className="text-xs text-muted-foreground">Campañas activas</div>
          </CardContent>
        </Card>
      </div>

      {/* Detalle por campaña */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <BarChart3 className="h-5 w-5 text-[#1E5C8E]" />
            Rendimiento por campaña
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <div className="p-4 space-y-3">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
            </div>
          ) : metricas.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground">
              <Megaphone className="h-10 w-10 mx-auto mb-3 text-slate-300" />
              <p>No tienes campañas publicadas aún.</p>
              <p className="text-sm mt-1">Las métricas aparecerán cuando una campaña sea aprobada y publicada.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/50">
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Campaña</th>
                    <th className="text-right px-4 py-3 font-medium text-muted-foreground">Impresiones</th>
                    <th className="text-right px-4 py-3 font-medium text-muted-foreground">Clicks</th>
                    <th className="text-right px-4 py-3 font-medium text-muted-foreground">CTR</th>
                    <th className="text-right px-4 py-3 font-medium text-muted-foreground">Usuarios únicos</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Vigencia</th>
                  </tr>
                </thead>
                <tbody>
                  {metricas.map((m) => (
                    <tr key={m.campana_id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          {m.imagen_url ? (
                            <img src={m.imagen_url} alt="" className="h-10 w-10 object-cover rounded" />
                          ) : (
                            <div className="h-10 w-10 bg-slate-100 rounded flex items-center justify-center">
                              <Megaphone className="h-4 w-4 text-slate-400" />
                            </div>
                          )}
                          <span className="font-medium">{m.titulo}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-right">{m.impresiones.toLocaleString()}</td>
                      <td className="px-4 py-3 text-right">{m.clicks.toLocaleString()}</td>
                      <td className="px-4 py-3 text-right">
                        <Badge variant={m.ctr >= 2 ? 'default' : 'secondary'} className={m.ctr >= 2 ? 'bg-emerald-600' : ''}>
                          {m.ctr.toFixed(1)}%
                        </Badge>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-1 text-muted-foreground">
                          <Users className="h-3.5 w-3.5" />
                          {m.usuarios_unicos}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-left text-muted-foreground text-xs">
                        {m.fecha_inicio} → {m.fecha_fin}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
