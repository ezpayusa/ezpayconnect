import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { Link } from 'react-router-dom'
import { Megaphone, CheckCircle, Eye, Loader2 } from 'lucide-react'
import { usePlanesPublicidad } from '@/proveedor/hooks/usePlanesPublicidad'

export default function PublicidadPlanesPage() {
  const { planes, loading } = usePlanesPublicidad()

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Planes de Publicidad</h1>
          <p className="text-sm text-muted-foreground">
            Contrata un plan para publicitar en EzPayConnect
          </p>
        </div>
        <Link to="/proveedor/publicidad/campanas">
          <Button variant="outline">
            <Eye className="h-4 w-4 mr-2" />
            Mis campañas
          </Button>
        </Link>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-64 w-full" />
          ))}
        </div>
      ) : planes.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Megaphone className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">No hay planes disponibles</h3>
            <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
              Contacta a soporte para más información.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {planes.map((plan) => (
            <Card key={plan.id} className="flex flex-col">
              <CardHeader className="pb-3">
                <CardTitle className="text-lg">{plan.nombre}</CardTitle>
                <p className="text-sm text-muted-foreground">{plan.descripcion}</p>
              </CardHeader>
              <CardContent className="flex-1 flex flex-col">
                <ul className="space-y-2 text-sm mb-4 flex-1">
                  <li className="flex items-center gap-2">
                    <CheckCircle className="h-4 w-4 text-emerald-500" />
                    {plan.dias} días de vigencia
                  </li>
                  <li className="flex items-center gap-2">
                    <CheckCircle className="h-4 w-4 text-emerald-500" />
                    Aprobación por EzPay Admin
                  </li>
                </ul>
                <div className="text-2xl font-bold text-[#1E5C8E] mb-4">
                  {new Intl.NumberFormat('es-GT', {
                    style: 'currency',
                    currency: plan.moneda,
                  }).format(plan.precio)}
                </div>
                <Link to={`/proveedor/publicidad/campanas/nueva?plan_id=${plan.id}`}>
                  <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
                    <Megaphone className="h-4 w-4 mr-2" />
                    Crear campaña
                  </Button>
                </Link>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
