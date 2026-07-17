import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { Pill, Check, ArrowRight, Package, Store, Truck, Clock, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { usePlanes } from '@/hooks/usePlanes';
import { useAuth } from '@/hooks/useAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { formatearPrecio, getBanderaPais } from '@/lib/planes-utils';

export default function PlanesFarmaciaPage() {
  const { paisId } = usePaisFiltro();
  const { planesBase, planesConfig, paises, loading } = usePlanes({ pais_id: paisId || undefined });
  const { user } = useAuth();
  const navigate = useNavigate();
  const [esAnual, setEsAnual] = useState(false);
  const [paisSeleccionado, setPaisSeleccionado] = useState(paisId || 'GT');
  const [planCheckout, setPlanCheckout] = useState<any>(null);

  const planesFarmacia = planesBase.filter(p => p.tipo === 'farmacia');

  const getConfigForPlan = (planId: string) => {
    return planesConfig.find(c => c.plan_base_id === planId && c.pais?.codigo === paisSeleccionado);
  };

  const getIcono = (nombre: string) => {
    if (nombre.includes('Pro')) return <Store className="h-8 w-8" />;
    return <Pill className="h-8 w-8" />;
  };

  const getGradient = (nombre: string) => {
    if (nombre.includes('Pro')) return 'from-blue-600 to-indigo-700';
    return 'from-sky-500 to-blue-600';
  };

  const handleElegirPlan = (plan: any) => {
    const config = getConfigForPlan(plan.id);
    const precio = esAnual
      ? (config?.precio_anual || plan.precio_base * 12 * 0.8)
      : (config?.precio_local || plan.precio_base);
    const moneda = config?.pais?.moneda || plan.moneda || 'USD';

    setPlanCheckout({
      ...plan,
      config_id: config?.id,
      precio_local: precio,
      precio_anual: config?.precio_anual || plan.precio_base * 12 * 0.8,
      moneda: moneda,
      pais: config?.pais,
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-sky-50 to-white">
      <div className="bg-gradient-to-r from-blue-600 to-indigo-700 text-white py-16">
        <div className="container mx-auto px-4 text-center">
          <div className="flex justify-center mb-4">
            <Pill className="h-16 w-16 text-sky-200" />
          </div>
          <h1 className="text-4xl font-bold mb-4">Planes para Farmacias</h1>
          <p className="text-xl text-sky-100 max-w-2xl mx-auto">
            Digitaliza tu farmacia. Gestiona recetas entrantes, inventario y entregas desde una sola plataforma.
          </p>
        </div>
      </div>

      <div className="container mx-auto px-4 py-12">
        <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4">
          <div className="flex gap-2">
            {paises && paises.map((pais: any) => (
              <Button
                key={pais.id}
                variant={paisSeleccionado === pais.codigo ? 'default' : 'outline'}
                size="sm"
                onClick={() => setPaisSeleccionado(pais.codigo)}
                className={paisSeleccionado === pais.codigo ? 'bg-blue-600 hover:bg-blue-700' : ''}
              >
                {getBanderaPais(pais.codigo)} {pais.nombre}
              </Button>
            ))}
          </div>

          <div className="flex items-center gap-3 bg-white px-4 py-2 rounded-lg shadow-sm border">
            <Label htmlFor="anual-farmacia" className={!esAnual ? 'font-semibold text-blue-700' : 'text-gray-500'}>
              Mensual
            </Label>
            <Switch id="anual-farmacia" checked={esAnual} onCheckedChange={setEsAnual} />
            <Label htmlFor="anual-farmacia" className={esAnual ? 'font-semibold text-blue-700' : 'text-gray-500'}>
              Anual
            </Label>
            {esAnual && <Badge className="bg-blue-100 text-blue-700 hover:bg-blue-100">Ahorra 20%</Badge>}
          </div>
        </div>

        {loading && (
          <div className="flex justify-center py-12">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
          </div>
        )}

        {!loading && planesFarmacia.length > 0 && (
          <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            {planesFarmacia.map((plan) => {
              const config = getConfigForPlan(plan.id);
              const precio = esAnual
                ? (config?.precio_anual || plan.precio_base * 12 * 0.8)
                : (config?.precio_local || plan.precio_base);
              const precioOriginal = esAnual ? (config?.precio_local || plan.precio_base) * 12 : null;
              const moneda = config?.pais?.moneda || plan.moneda || 'USD';

              return (
                <Card
                  key={plan.id}
                  className={`relative overflow-hidden border-2 ${plan.nombre.includes('Pro') ? 'border-blue-500 shadow-xl scale-105' : 'border-gray-200'}`}
                >
                  {plan.nombre.includes('Pro') && (
                    <div className="absolute top-0 right-0 bg-gradient-to-l from-blue-500 to-indigo-600 text-white px-4 py-1 rounded-bl-lg text-sm font-semibold">
                      Recomendado
                    </div>
                  )}

                  <CardHeader className={`bg-gradient-to-r ${getGradient(plan.nombre)} text-white p-6`}>
                    <div className="flex items-center gap-3 mb-2">
                      {getIcono(plan.nombre)}
                      <h3 className="text-2xl font-bold">{plan.nombre}</h3>
                    </div>
                    <p className="text-sky-100 text-sm">{plan.descripcion}</p>
                  </CardHeader>

                  <CardContent className="p-6">
                    <div className="mb-6">
                      <div className="flex items-baseline gap-1">
                        <span className="text-4xl font-bold text-gray-900">
                          {formatearPrecio(precio, moneda)}
                        </span>
                        <span className="text-gray-500">/{esAnual ? 'año' : 'mes'}</span>
                      </div>
                      {precioOriginal && (
                        <p className="text-sm text-gray-400 line-through">
                          {formatearPrecio(precioOriginal, moneda)}/año
                        </p>
                      )}
                    </div>

                    <ul className="space-y-3 mb-6">
                      <li className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-blue-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">Recetas entrantes ilimitadas</span>
                      </li>
                      <li className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-blue-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">Gestión de inventario</span>
                      </li>
                      <li className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-blue-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">{plan.nombre.includes('Pro') ? 'Sucursales ilimitadas' : 'Hasta 1 sucursal'}</span>
                      </li>
                      <li className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-blue-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">{plan.nombre.includes('Pro') ? 'Entregas a domicilio con tracking' : 'Retiro en farmacia'}</span>
                      </li>
                      <li className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-blue-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">{plan.nombre.includes('Pro') ? 'Soporte prioritario 24/7' : 'Soporte por email'}</span>
                      </li>
                    </ul>

                    <Button
                      className={`w-full ${plan.nombre.includes('Pro') ? 'bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700' : 'bg-gray-900 hover:bg-gray-800'}`}
                      size="lg"
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

        {!loading && planesFarmacia.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            No hay planes de farmacia disponibles.
          </div>
        )}

        <div className="mt-16 grid md:grid-cols-3 gap-8">
          <div className="text-center p-6">
            <Package className="h-12 w-12 text-blue-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Inventario Digital</h3>
            <p className="text-gray-600">Controla tu stock y evita quiebres con alertas automáticas.</p>
          </div>
          <div className="text-center p-6">
            <Clock className="h-12 w-12 text-blue-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Recetas en Tiempo Real</h3>
            <p className="text-gray-600">Recibí recetas de los médicos al instante y despachá más rápido.</p>
          </div>
          <div className="text-center p-6">
            <Truck className="h-12 w-12 text-blue-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Entregas a Domicilio</h3>
            <p className="text-gray-600">Coordina entregas con seguimiento y confirmación del paciente.</p>
          </div>
        </div>
      </div>

      <Dialog open={!!planCheckout} onOpenChange={() => setPlanCheckout(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pill className="h-5 w-5 text-blue-600" />
              Confirmar Suscripción
            </DialogTitle>
          </DialogHeader>
          {planCheckout && (
            <div className="space-y-4">
              <div className="bg-sky-50 p-4 rounded-lg">
                <h3 className="font-bold text-lg">{planCheckout.nombre}</h3>
                <p className="text-sm text-gray-600">{planCheckout.descripcion}</p>
                <div className="mt-2">
                  <span className="text-2xl font-bold text-blue-700">
                    {formatearPrecio(esAnual ? planCheckout.precio_anual : planCheckout.precio_local, planCheckout.moneda)}
                  </span>
                  <span className="text-gray-500">/{esAnual ? 'año' : 'mes'}</span>
                </div>
              </div>

              <div className="space-y-2">
                <p className="text-sm"><strong>País:</strong> {getBanderaPais(planCheckout.pais?.codigo)} {planCheckout.pais?.nombre || paisSeleccionado}</p>
                <p className="text-sm"><strong>Periodicidad:</strong> {esAnual ? 'Anual (ahorras 20%)' : 'Mensual'}</p>
                <p className="text-sm"><strong>Usuario:</strong> {user?.email || 'Invitado'}</p>
              </div>

              <div className="flex gap-2">
                <Button
                  className="flex-1 bg-blue-600 hover:bg-blue-700"
                  onClick={() => {
                    if (!planCheckout.config_id) {
                      toast.error('Este plan no está configurado para el país seleccionado.');
                      return;
                    }
                    const monto = esAnual ? planCheckout.precio_anual : planCheckout.precio_local;
                    navigate(`/proveedor/checkout?tipo=plan_farmacia&referencia_id=${planCheckout.config_id}&monto=${monto}&descripcion=${encodeURIComponent(planCheckout.nombre)}`);
                    setPlanCheckout(null);
                  }}
                >
                  Proceder al Pago
                </Button>
                <Button variant="outline" onClick={() => setPlanCheckout(null)}>
                  <X className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
