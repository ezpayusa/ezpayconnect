import { Link, useNavigate } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useSolicitudesCampana } from '@/proveedor/hooks/useSolicitudesCampana'
import { Megaphone, Plus, Trash2, Pencil, Loader2, CreditCard } from 'lucide-react'

const estadoColor: Record<string, string> = {
  borrador: 'bg-slate-100 text-slate-700',
  enviada: 'bg-blue-100 text-blue-700',
  en_revision: 'bg-amber-100 text-amber-700',
  aprobada: 'bg-emerald-100 text-emerald-700',
  rechazada: 'bg-red-100 text-red-700',
  publicada: 'bg-purple-100 text-purple-700',
}

export default function PublicidadCampanasPage() {
  const navigate = useNavigate()
  const { solicitudes, loading, eliminarSolicitud } = useSolicitudesCampana()

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Mis Campañas</h1>
          <p className="text-sm text-muted-foreground">
            {solicitudes.length} campaña{solicitudes.length !== 1 ? 's' : ''} registrada{solicitudes.length !== 1 ? 's' : ''}
          </p>
        </div>
        <Link to="/proveedor/publicidad/campanas/nueva">
          <Button className="bg-[#1E5C8E] hover:bg-[#164a70]">
            <Plus className="h-4 w-4 mr-2" />
            Nueva campaña
          </Button>
        </Link>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : solicitudes.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Megaphone className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">No tienes campañas aún</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Crea tu primera campaña para aparecer en los banners del portal.
            </p>
            <Link to="/proveedor/publicidad/campanas/nueva" className="inline-block mt-4">
              <Button variant="outline">
                <Plus className="h-4 w-4 mr-2" />
                Crear campaña
              </Button>
            </Link>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {solicitudes.map((c) => (
            <Card key={c.id} className="overflow-hidden">
              <div className="h-40 bg-slate-100 relative">
                {c.imagen_url ? (
                  <img
                    src={c.imagen_url}
                    alt={c.titulo}
                    className="w-full h-full object-cover"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                  />
                ) : (
                  <div className="flex items-center justify-center h-full">
                    <Megaphone className="h-10 w-10 text-slate-300" />
                  </div>
                )}
                <div className="absolute top-2 right-2">
                  <Badge className={estadoColor[c.estado] || estadoColor.borrador}>
                    {c.estado}
                  </Badge>
                </div>
              </div>
              <CardContent className="p-4">
                <h3 className="font-semibold text-gray-900 truncate">{c.titulo}</h3>
                <p className="text-sm text-muted-foreground mt-1 line-clamp-2">
                  {c.descripcion || 'Sin descripción'}
                </p>
                <div className="text-xs text-muted-foreground mt-2">
                  {c.fecha_inicio} → {c.fecha_fin}
                </div>
                {(c.condicion_filtro || c.genero_filtro || c.edad_min || c.edad_max) && (
                  <div className="text-xs text-muted-foreground mt-1">
                    Filtros: {[c.condicion_filtro, c.genero_filtro, c.edad_min && `≥${c.edad_min}`, c.edad_max && `≤${c.edad_max}`].filter(Boolean).join(' · ')}
                  </div>
                )}
                {c.notas_admin && (
                  <div className="mt-2 p-2 bg-amber-50 text-amber-700 text-xs rounded">
                    <strong>Nota admin:</strong> {c.notas_admin}
                  </div>
                )}
                <div className="flex items-center gap-2 mt-4">
                  {c.estado === 'borrador' && (
                    <Button
                      size="sm"
                      className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white"
                      onClick={() =>
                        navigate(
                          `/proveedor/checkout?tipo=campana&referencia_id=${c.id}&monto=500&descripcion=${encodeURIComponent(c.titulo)}`
                        )
                      }
                    >
                      <CreditCard className="h-3.5 w-3.5 mr-1" />
                      Pagar y enviar
                    </Button>
                  )}
                  {c.estado === 'rechazada' && (
                    <Link to={`/proveedor/publicidad/campanas/${c.id}/editar`} className="flex-1">
                      <Button variant="outline" size="sm" className="w-full">
                        <Pencil className="h-3.5 w-3.5 mr-1" />
                        Editar
                      </Button>
                    </Link>
                  )}
                  <Button
                    size="sm"
                    variant="outline"
                    className="text-red-600 hover:bg-red-50"
                    onClick={() => eliminarSolicitud(c.id)}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
