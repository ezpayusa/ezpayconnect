import { Link } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useProductosEmpresa } from '@/proveedor/hooks/useProductosEmpresa'
import { Package, Plus, Pencil, Trash2, Loader2 } from 'lucide-react'

const estadoColor: Record<string, string> = {
  activo: 'bg-emerald-100 text-emerald-700',
  agotado: 'bg-amber-100 text-amber-700',
  descontinuado: 'bg-slate-100 text-slate-700',
}

export default function ProductosListPage() {
  const { productos, loading, eliminarProducto } = useProductosEmpresa()

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Productos</h1>
          <p className="text-sm text-muted-foreground">
            {productos.length} producto{productos.length !== 1 ? 's' : ''} en catálogo
          </p>
        </div>
        <Link to="/proveedor/productos/nuevo">
          <Button className="bg-[#1E5C8E] hover:bg-[#164a70]">
            <Plus className="h-4 w-4 mr-2" />
            Nuevo producto
          </Button>
        </Link>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : productos.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Package className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">No hay productos aún</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Agrega tu primer producto para que los médicos puedan encontrarlo en las búsquedas.
            </p>
            <Link to="/proveedor/productos/nuevo" className="inline-block mt-4">
              <Button variant="outline">
                <Plus className="h-4 w-4 mr-2" />
                Agregar producto
              </Button>
            </Link>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {productos.map((p) => (
            <Card key={p.id} className="overflow-hidden">
              <div className="h-40 bg-slate-100 relative">
                {p.imagen_url ? (
                  <img
                    src={p.imagen_url}
                    alt={p.nombre_producto}
                    className="w-full h-full object-cover"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                  />
                ) : (
                  <div className="flex items-center justify-center h-full">
                    <Package className="h-10 w-10 text-slate-300" />
                  </div>
                )}
                <div className="absolute top-2 right-2">
                  <Badge className={estadoColor[p.estado] || estadoColor.activo}>
                    {p.estado}
                  </Badge>
                </div>
              </div>
              <CardContent className="p-4">
                <h3 className="font-semibold text-gray-900 truncate">{p.nombre_producto}</h3>
                <p className="text-sm text-muted-foreground mt-1">
                  {p.principio_activo || '-'} • {p.presentacion || '-'} • {p.concentracion || '-'}
                </p>
                <div className="flex items-center justify-between mt-3">
                  <div className="text-lg font-bold text-[#1E5C8E]">
                    Q {Number(p.precio_unitario).toFixed(2)}
                  </div>
                  <div className="text-sm text-muted-foreground">
                    Stock: {p.stock_disponible}
                  </div>
                </div>
                {p.requiere_receta && (
                  <Badge variant="outline" className="mt-2 text-amber-600 border-amber-600">
                    Requiere receta
                  </Badge>
                )}
                <div className="flex items-center gap-2 mt-4">
                  <Link to={`/proveedor/productos/${p.id}/editar`} className="flex-1">
                    <Button variant="outline" size="sm" className="w-full">
                      <Pencil className="h-3.5 w-3.5 mr-1" />
                      Editar
                    </Button>
                  </Link>
                  <Button
                    size="sm"
                    variant="outline"
                    className="text-red-600 hover:bg-red-50 hover:text-red-700"
                    onClick={() => eliminarProducto(p.id)}
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
