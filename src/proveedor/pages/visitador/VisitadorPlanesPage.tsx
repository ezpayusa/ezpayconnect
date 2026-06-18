import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { usePlanesVisitador } from '@/proveedor/hooks/usePlanesVisitador'
import { etiquetaRol } from '@/proveedor/lib/permisos'
import { CalendarCheck, CheckCircle, Loader2, ShoppingCart } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'

export default function VisitadorPlanesPage() {
  const navigate = useNavigate()
  const { planesBase, planesContratados, visitasDisponibles, loading } = usePlanesVisitador()

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Planes de {etiquetaRol('visitador_medico')}</h1>
          <p className="text-sm text-muted-foreground">
            Contrata planes para agendar visitas con médicos
          </p>
        </div>
        {visitasDisponibles > 0 && (
          <Badge className="bg-emerald-100 text-emerald-700 text-sm px-3 py-1">
            {visitasDisponibles} visitas disponibles
          </Badge>
        )}
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : (
        <>
          {/* Planes contratados activos */}
          {planesContratados.length > 0 && (
            <div className="space-y-3">
              <h2 className="text-lg font-semibold">Mis planes activos</h2>
              {planesContratados.map((plan) => (
                <Card key={plan.id}>
                  <CardContent className="p-4 flex items-center justify-between">
                    <div>
                      <p className="font-medium">Plan de visitador</p>
                      <p className="text-sm text-muted-foreground">
                        Visitas incluidas: {plan.cantidad_visitas_incluidas}
                      </p>
                      <p className="text-sm text-muted-foreground">
                        Válido hasta: {plan.fecha_fin}
                      </p>
                    </div>
                    <div className="flex items-center gap-3">
                      <Badge className={plan.estado === 'activo' ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-700'}>
                        {plan.estado}
                      </Badge>
                      {plan.estado === 'activo' && (
                        <Link to="/proveedor/visitador/agendar">
                          <Button size="sm" className="bg-[#1E5C8E] hover:bg-[#164a70]">
                            <CalendarCheck className="h-4 w-4 mr-1" />
                            Agendar visita
                          </Button>
                        </Link>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}

          {/* Planes disponibles para contratar */}
          <div className="space-y-3">
            <h2 className="text-lg font-semibold">Contratar nuevo plan</h2>
            {planesBase.length === 0 ? (
              <Card>
                <CardContent className="py-12 text-center text-slate-500">
                  <p>No hay planes disponibles en este momento.</p>
                  <p className="text-sm mt-1">Contacta al administrador para más información.</p>
                </CardContent>
              </Card>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {planesBase.map((plan) => (
                  <Card key={plan.id} className="flex flex-col">
                    <CardHeader className="pb-3">
                      <CardTitle className="text-lg">{plan.nombre}</CardTitle>
                      <p className="text-sm text-muted-foreground">{plan.descripcion}</p>
                    </CardHeader>
                    <CardContent className="flex-1 flex flex-col">
                      <ul className="space-y-2 text-sm mb-4 flex-1">
                        <li className="flex items-center gap-2">
                          <CheckCircle className="h-4 w-4 text-emerald-500" />
                          {plan.cantidad_visitas} visitas incluidas
                        </li>
                        <li className="flex items-center gap-2">
                          <CheckCircle className="h-4 w-4 text-emerald-500" />
                          Vigencia: {plan.duracion_dias} días
                        </li>
                      </ul>
                      <div className="text-2xl font-bold text-[#1E5C8E] mb-4">
                        {plan.moneda === 'GTQ' ? 'Q' : plan.moneda} {plan.precio_referencia.toLocaleString()}
                      </div>
                      <Button
                        className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
                        onClick={() =>
                          navigate(
                            `/proveedor/checkout?tipo=plan_visitador&referencia_id=${plan.id}&monto=${plan.precio_referencia}&descripcion=${encodeURIComponent(plan.nombre)}`
                          )
                        }
                      >
                        <ShoppingCart className="h-4 w-4 mr-2" />
                        Contratar plan
                      </Button>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}
