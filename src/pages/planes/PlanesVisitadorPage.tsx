import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { MapPin, Check, ArrowRight, Navigation, Route, CalendarCheck, ClipboardCheck, BarChart3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { usePlanes } from '@/hooks/usePlanes';
import { useAuth } from '@/hooks/useAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { formatearPrecio, getBanderaPais } from '@/lib/planes-utils';
import { configComprable } from '@/proveedor/lib/compraPlanVisitador';

// Solo se describe lo que el módulo de visitas hace hoy.
const FUNCIONES_REALES = [
  'Agenda de visitas a médicos',
  'Aprobación del supervisor',
  'Check-in y check-out con evidencia',
  'Ruta del día',
  'Reporte de visitas',
];

export default function PlanesVisitadorPage() {
  const { paisId } = usePaisFiltro();
  const { planesBase, planesConfig, paises, loading } = usePlanes({ pais_id: paisId || undefined });
  const { user } = useAuth();
  const navigate = useNavigate();
  const [paisSeleccionado, setPaisSeleccionado] = useState(paisId || 'GT');
  const [planCheckout, setPlanCheckout] = useState<any>(null);

  const planesVisitador = planesBase.filter(p => p.tipo === 'visitador');

  // La compra cobra el precio mensual de la configuración del país y suma sus visitas por su duración (mig 351).
  const getConfigForPlan = (planId: string) => {
    return planesConfig.find(c => c.plan_base_id === planId && c.pais?.codigo === paisSeleccionado);
  };

  const getIcono = (nombre: string) => {
    if (nombre.includes('Pro')) return <Route className="h-8 w-8" />;
    return <Navigation className="h-8 w-8" />;
  };

  const getGradient = (nombre: string) => {
    if (nombre.includes('Pro')) return 'from-orange-600 to-amber-700';
    return 'from-amber-500 to-orange-600';
  };

  const handleElegirPlan = (plan: any) => {
    const config = getConfigForPlan(plan.id);
    if (!config || !configComprable(config)) {
      toast.error('Este plan no está disponible para el país seleccionado.');
      return;
    }
    setPlanCheckout({
      ...plan,
      config_id: config.id,
      precio_local: config.precio_local,
      moneda: config.moneda_local || config.pais?.moneda || 'USD',
      visitas_incluidas: config.visitas_incluidas,
      duracion_dias: config.duracion_dias,
      pais: config.pais,
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-amber-50 to-white">
      {/* Header */}
      <div className="bg-gradient-to-r from-orange-600 to-amber-700 text-white py-16">
        <div className="container mx-auto px-4 text-center">
          <div className="flex justify-center mb-4">
            <MapPin className="h-16 w-16 text-amber-200" />
          </div>
          <h1 className="text-4xl font-bold mb-4">Planes para Visitadores</h1>
          <p className="text-xl text-amber-100 max-w-2xl mx-auto">
            Organiza las visitas de tu equipo a médicos: agenda, aprobación del supervisor, check-in y check-out con
            evidencia, ruta del día y reporte de visitas.
          </p>
        </div>
      </div>

      <div className="container mx-auto px-4 py-12">
        {/* Selector de país */}
        <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4">
          <div className="flex gap-2">
            {paises && paises.map((pais: any) => (
              <Button
                key={pais.id}
                variant={paisSeleccionado === pais.codigo ? 'default' : 'outline'}
                size="sm"
                onClick={() => setPaisSeleccionado(pais.codigo)}
                className={paisSeleccionado === pais.codigo ? 'bg-orange-600 hover:bg-orange-700' : ''}
              >
                {getBanderaPais(pais.codigo)} {pais.nombre}
              </Button>
            ))}
          </div>
        </div>

        {/* Loading */}
        {loading && (
          <div className="flex justify-center py-12">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-orange-600"></div>
          </div>
        )}

        {/* Grid planes */}
        {!loading && planesVisitador.length > 0 && (
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            {planesVisitador.map((plan) => {
              const config = getConfigForPlan(plan.id);
              const disponible = !!config && configComprable(config);
              const moneda = config?.moneda_local || config?.pais?.moneda || plan.moneda || 'USD';

              return (
                <Card
                  key={plan.id}
                  className={`relative overflow-hidden border-2 ${plan.nombre.includes('Pro') ? 'border-orange-500 shadow-xl scale-105' : 'border-gray-200'}`}
                >
                  {plan.nombre.includes('Pro') && (
                    <div className="absolute top-0 right-0 bg-gradient-to-l from-orange-500 to-amber-600 text-white px-4 py-1 rounded-bl-lg text-sm font-semibold">
                      Recomendado
                    </div>
                  )}

                  <CardHeader className={`bg-gradient-to-r ${getGradient(plan.nombre)} text-white p-6`}>
                    <div className="flex items-center gap-3 mb-2">
                      {getIcono(plan.nombre)}
                      <h3 className="text-2xl font-bold">{plan.nombre}</h3>
                    </div>
                    <p className="text-amber-100 text-sm">{plan.descripcion}</p>
                  </CardHeader>

                  <CardContent className="p-6">
                    <div className="mb-6">
                      {disponible ? (
                        <div className="flex items-baseline gap-1">
                          <span className="text-4xl font-bold text-gray-900">{formatearPrecio(config!.precio_local, moneda)}</span>
                          <span className="text-gray-500">/{config!.duracion_dias} días</span>
                        </div>
                      ) : (
                        <p className="text-sm text-gray-500">No disponible en el país seleccionado.</p>
                      )}
                    </div>

                    <ul className="space-y-3 mb-6">
                      {disponible && (
                        <>
                          <li className="flex items-start gap-2 text-sm">
                            <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                            <span className="text-gray-700 font-medium">{config!.visitas_incluidas} visitas incluidas</span>
                          </li>
                          <li className="flex items-start gap-2 text-sm">
                            <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                            <span className="text-gray-700 font-medium">Vigencia de {config!.duracion_dias} días</span>
                          </li>
                        </>
                      )}
                      {FUNCIONES_REALES.map((f) => (
                        <li key={f} className="flex items-start gap-2 text-sm">
                          <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                          <span className="text-gray-700">{f}</span>
                        </li>
                      ))}
                    </ul>

                    <Button
                      className={`w-full ${plan.nombre.includes('Pro') ? 'bg-gradient-to-r from-orange-600 to-amber-600 hover:from-orange-700 hover:to-amber-700' : 'bg-gray-900 hover:bg-gray-800'}`}
                      size="lg"
                      disabled={!disponible}
                      onClick={() => handleElegirPlan(plan)}
                    >
                      Elegir Plan <ArrowRight className="ml-2 h-4 w-4" />
                    </Button>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}

        {!loading && planesVisitador.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            No hay planes de visitador disponibles.
          </div>
        )}

        {/* Lo que incluye el módulo (solo lo que existe) */}
        <div className="mt-16 grid md:grid-cols-3 gap-8">
          <div className="text-center p-6">
            <CalendarCheck className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Agenda y aprobación</h3>
            <p className="text-gray-600">El visitador propone las visitas a médicos y el supervisor las aprueba.</p>
          </div>
          <div className="text-center p-6">
            <ClipboardCheck className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Check-in y check-out</h3>
            <p className="text-gray-600">Cada visita se registra al llegar y al salir, con evidencia.</p>
          </div>
          <div className="text-center p-6">
            <BarChart3 className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Ruta y reporte</h3>
            <p className="text-gray-600">La ruta del día de cada visitador y el reporte de visitas realizadas.</p>
          </div>
        </div>
      </div>

      {/* Checkout Modal */}
      <Dialog open={!!planCheckout} onOpenChange={() => setPlanCheckout(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-orange-600" />
              Confirmar compra
            </DialogTitle>
          </DialogHeader>
          {planCheckout && (
            <div className="space-y-4">
              <div className="bg-orange-50 p-4 rounded-lg">
                <h3 className="font-bold text-lg">{planCheckout.nombre}</h3>
                <p className="text-sm text-gray-600">{planCheckout.descripcion}</p>
                <div className="mt-2">
                  <span className="text-2xl font-bold text-orange-700">
                    {formatearPrecio(planCheckout.precio_local, planCheckout.moneda)}
                  </span>
                </div>
              </div>

              <div className="space-y-2">
                <p className="text-sm"><strong>País:</strong> {getBanderaPais(planCheckout.pais?.codigo)} {planCheckout.pais?.nombre || paisSeleccionado}</p>
                <p className="text-sm"><strong>Incluye:</strong> {planCheckout.visitas_incluidas} visitas, vigentes {planCheckout.duracion_dias} días</p>
                <p className="text-sm"><strong>Usuario:</strong> {user?.email || 'Invitado'}</p>
              </div>

              <div className="flex gap-2">
                <Button
                  className="flex-1 bg-orange-600 hover:bg-orange-700"
                  onClick={() => {
                    navigate(`/proveedor/checkout?tipo=plan_visitador&referencia_id=${planCheckout.config_id}&descripcion=${encodeURIComponent(planCheckout.nombre)}`);
                    setPlanCheckout(null);
                  }}
                >
                  Proceder al Pago
                </Button>
                <Button variant="outline" onClick={() => setPlanCheckout(null)}>
                  Cancelar
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
