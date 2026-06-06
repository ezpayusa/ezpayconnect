import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Link } from 'react-router-dom'
import { Megaphone, CheckCircle, Eye } from 'lucide-react'

const planesPublicidad = [
  {
    id: 1,
    nombre: 'Banner Básico',
    descripcion: 'Aparece en banners del portal paciente y médico por 7 días',
    dias: 7,
    precio: 1500,
    moneda: 'GTQ',
  },
  {
    id: 2,
    nombre: 'Banner Profesional',
    descripcion: 'Aparece en banners + notificación push por 15 días',
    dias: 15,
    precio: 3500,
    moneda: 'GTQ',
  },
  {
    id: 3,
    nombre: 'Campaña Premium',
    descripcion: 'Banner destacado + segmentación por edad/género/condición por 30 días',
    dias: 30,
    precio: 8000,
    moneda: 'GTQ',
  },
]

export default function PublicidadPlanesPage() {
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

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {planesPublicidad.map((plan) => (
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
                Q {plan.precio.toLocaleString()}
              </div>
              <Link to="/proveedor/publicidad/campanas/nueva">
                <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
                  <Megaphone className="h-4 w-4 mr-2" />
                  Crear campaña
                </Button>
              </Link>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
