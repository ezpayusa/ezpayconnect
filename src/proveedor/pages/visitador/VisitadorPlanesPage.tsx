import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { usePlanesVisitador } from '@/proveedor/hooks/usePlanesVisitador'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { etiquetaRol } from '@/proveedor/lib/permisos'
import { CalendarCheck, CheckCircle, Loader2, ShoppingCart } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'

interface Props {
  /**
   * Montaje del PWA del visitador (/visitador/planes): solo su cupo y vigencia, sin catálogo comprable.
   * El montaje de gestión (/proveedor/visitador/planes) lo deja en false.
   */
  soloCupo?: boolean
}

const formatearPrecio = (moneda: string, monto: number) => `${moneda === 'GTQ' ? 'Q' : moneda} ${monto.toLocaleString()}`

export default function VisitadorPlanesPage({ soloCupo = false }: Props) {
  const navigate = useNavigate()
  const { puede } = useProveedorAuth()
  const { planesBase, planesVigentes, planesVencidos, visitasDisponibles, tieneIlimitado, cupos, cupoConDesglose, loading } = usePlanesVisitador()
  const puedeContratar = !soloCupo && puede('planes.contratar')

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">
            {soloCupo ? 'Mi cupo de visitas' : `Planes de ${etiquetaRol('visitador_medico')}`}
          </h1>
          <p className="text-sm text-muted-foreground">
            {soloCupo ? 'Visitas disponibles de tu empresa y su vigencia' : 'Planes para agendar visitas con médicos'}
          </p>
        </div>
        {/* Cupo por país (criterio del gate): el del país de la empresa, o un desglose si hay cupo en otro país. */}
        {cupoConDesglose ? (
          <div className="flex flex-wrap justify-end gap-1">
            {cupos.map((c) => (
              <Badge key={c.pais_id} className="bg-emerald-100 text-emerald-700 text-sm px-3 py-1">
                {c.pais_nombre ?? 'País'}: {c.ilimitado ? 'ilimitadas' : `${c.restante} disponibles`}
              </Badge>
            ))}
          </div>
        ) : tieneIlimitado ? (
          <Badge className="bg-emerald-100 text-emerald-700 text-sm px-3 py-1">Visitas ilimitadas</Badge>
        ) : visitasDisponibles > 0 ? (
          <Badge className="bg-emerald-100 text-emerald-700 text-sm px-3 py-1">{visitasDisponibles} visitas disponibles</Badge>
        ) : null}
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : (
        <>
          {/* Bolsas vigentes (fecha_inicio <= hoy <= fecha_fin, hoy en UTC: esBolsaVigente) */}
          <div className="space-y-3">
            <h2 className="text-lg font-semibold">{soloCupo ? 'Cupo vigente' : 'Mis planes vigentes'}</h2>
            {planesVigentes.length === 0 ? (
              <Card>
                <CardContent className="py-8 text-center text-slate-500">
                  <p>No hay un plan vigente.</p>
                  {soloCupo && <p className="text-sm mt-1">Pedile a un administrador de tu empresa que contrate un plan.</p>}
                </CardContent>
              </Card>
            ) : (
              planesVigentes.map((plan) => (
                <Card key={plan.id}>
                  <CardContent className="p-4 flex items-center justify-between">
                    <div>
                      <p className="font-medium">Plan de visitador{plan.pais_nombre ? ` · ${plan.pais_nombre}` : ''}</p>
                      <p className="text-sm text-muted-foreground">
                        {plan.ilimitado
                          ? 'Visitas: Ilimitado'
                          : `Visitas restantes: ${plan.restante ?? 0} de ${plan.cantidad_visitas_incluidas ?? 0}`}
                      </p>
                      <p className="text-sm text-muted-foreground">Vigente hasta: {plan.fecha_fin}</p>
                    </div>
                    <div className="flex items-center gap-3">
                      <Badge className="bg-emerald-100 text-emerald-700">vigente</Badge>
                      <Link to="/visitador/agendar">
                        <Button size="sm" className="bg-[#1E5C8E] hover:bg-[#164a70]">
                          <CalendarCheck className="h-4 w-4 mr-1" />
                          Agendar visita
                        </Button>
                      </Link>
                    </div>
                  </CardContent>
                </Card>
              ))
            )}
          </div>

          {/* Bolsas vencidas: aparte y discretas, solo en el montaje de gestión */}
          {!soloCupo && planesVencidos.length > 0 && (
            <details className="text-sm">
              <summary className="cursor-pointer text-muted-foreground">Planes vencidos ({planesVencidos.length})</summary>
              <ul className="mt-2 space-y-1 text-muted-foreground">
                {planesVencidos.map((plan) => (
                  <li key={plan.id}>
                    {plan.pais_nombre ? `${plan.pais_nombre} · ` : ''}
                    {plan.ilimitado ? 'Ilimitado' : `${plan.cantidad_visitas_incluidas ?? 0} visitas`} · venció el {plan.fecha_fin}
                  </li>
                ))}
              </ul>
            </details>
          )}

          {/* Catálogo: nunca en el PWA del visitador */}
          {!soloCupo && (
            <div className="space-y-3">
              <h2 className="text-lg font-semibold">{puedeContratar ? 'Contratar nuevo plan' : 'Planes disponibles'}</h2>
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
                          {formatearPrecio(plan.moneda, plan.precio_referencia)}
                        </div>
                        {puedeContratar && (
                          <Button
                            className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
                            onClick={() =>
                              navigate(
                                `/proveedor/checkout?tipo=plan_visitador&referencia_id=${plan.id}&descripcion=${encodeURIComponent(plan.nombre)}`
                              )
                            }
                          >
                            <ShoppingCart className="h-4 w-4 mr-2" />
                            Contratar plan
                          </Button>
                        )}
                      </CardContent>
                    </Card>
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  )
}
