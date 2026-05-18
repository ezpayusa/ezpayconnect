import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { PlanCard } from '@/components/planes/PlanCard';
import { PlanCheckout } from '@/components/planes/PlanCheckout';
import type { CheckoutData } from '@/components/planes/PlanCheckout';
import { usePlanes } from '@/hooks/usePlanes';
import { useAuth } from '@/hooks/useAuth';
import { getBanderaPais } from '@/lib/planes-utils';
import { Building2, Shield, Globe, CheckCircle2 } from 'lucide-react';

export default function PlanesClinicaPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { planesConfig, paises, loading, crearAsignacionCheckout } = usePlanes();
  const [paisSeleccionado, setPaisSeleccionado] = useState<string>('');
  const [checkoutAbierto, setCheckoutAbierto] = useState(false);
  const [configCheckout, setConfigCheckout] = useState<any>(null);

  // Filtrar solo planes clinica activos
  const planesClinica = planesConfig.filter(p => p.plan_base?.tipo === 'clinica' && p.activo !== false);

  // Obtener paises unicos de las configuraciones clinica
  const paisesUnicos = paises.filter(p => planesClinica.some(pc => pc.pais_id === p.id));

  // Seleccionar primer pais por defecto
  if (!paisSeleccionado && paisesUnicos.length > 0) {
    setPaisSeleccionado(paisesUnicos[0].id);
  }

  const planesFiltrados = planesClinica.filter(p => p.pais_id === paisSeleccionado);

  const handleSeleccionarPlan = (planId: string, ciclo?: 'mensual' | 'anual') => {
    if (!user) {
      navigate('/login', { state: { redirect: '/planes-clinica' } });
      return;
    }

    const config = planesFiltrados.find(p => p.plan_base?.id === planId || p.plan_id === planId);
    if (config) {
      setConfigCheckout(config);
      setCheckoutAbierto(true);
    }
  };

  const handleConfirmarCheckout = async (datos: CheckoutData) => {
    if (!configCheckout) return;

    const result = await crearAsignacionCheckout({
      planId: datos.planId,
      configuracionId: configCheckout.id,
      ciclo: datos.ciclo,
      metodoPago: datos.metodoPago,
      precioFinal: datos.precioFinal,
      moneda: datos.moneda,
    });

    if (result) {
      setCheckoutAbierto(false);
      setConfigCheckout(null);
      navigate('/dashboard', { state: { planActivado: true } });
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-cyan-500" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-gradient-to-r from-blue-600 to-indigo-700 text-white py-16">
        <div className="container mx-auto px-4 text-center">
          <Badge className="mb-4 bg-white/20 text-white border-0">
            <Building2 className="h-3 w-3 mr-1" />
            Planes diseñados para clínicas
          </Badge>
          <h1 className="text-4xl font-bold mb-4">Soluciones para tu clínica</h1>
          <p className="text-lg text-blue-100 max-w-2xl mx-auto">
            Desde consultorios pequeños hasta redes médicas. Gestión completa de tu centro de salud.
          </p>
        </div>
      </div>

      <div className="container mx-auto px-4 py-12 max-w-6xl">
        {/* Selector de país */}
        {paisesUnicos.length > 0 && (
          <div className="flex justify-center mb-8">
            <Tabs value={paisSeleccionado} onValueChange={setPaisSeleccionado}>
              <TabsList className="bg-white border shadow-sm">
                {paisesUnicos.map(pais => (
                  <TabsTrigger key={pais.id} value={pais.id} className="flex items-center gap-2 data-[state=active]:bg-blue-50 data-[state=active]:text-blue-700">
                    <span className="text-lg">{getBanderaPais(pais.codigo as any)}</span>
                    {pais.nombre}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>
        )}

        {/* Grid de planes */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-16 items-start max-w-4xl mx-auto">
          {planesFiltrados.map((config) => (
            <PlanCard
              key={config.id}
              config={config}
              onSeleccionar={handleSeleccionarPlan}
            />
          ))}

          {planesFiltrados.length === 0 && (
            <div className="col-span-full text-center py-12">
              <p className="text-muted-foreground">No hay planes disponibles para este país.</p>
            </div>
          )}
        </div>

        {/* Features */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-16">
          <div className="text-center bg-white p-6 rounded-xl shadow-sm">
            <div className="h-12 w-12 rounded-full bg-blue-50 flex items-center justify-center mx-auto mb-4">
              <Shield className="h-6 w-6 text-blue-600" />
            </div>
            <h3 className="font-semibold mb-2">Seguridad Empresarial</h3>
            <p className="text-sm text-muted-foreground">Cumplimiento HIPAA y normativas internacionales de salud</p>
          </div>
          <div className="text-center bg-white p-6 rounded-xl shadow-sm">
            <div className="h-12 w-12 rounded-full bg-blue-50 flex items-center justify-center mx-auto mb-4">
              <Globe className="h-6 w-6 text-blue-600" />
            </div>
            <h3 className="font-semibold mb-2">Multi-sucursal</h3>
            <p className="text-sm text-muted-foreground">Gestiona todas tus ubicaciones desde un solo dashboard</p>
          </div>
          <div className="text-center bg-white p-6 rounded-xl shadow-sm">
            <div className="h-12 w-12 rounded-full bg-blue-50 flex items-center justify-center mx-auto mb-4">
              <CheckCircle2 className="h-6 w-6 text-blue-600" />
            </div>
            <h3 className="font-semibold mb-2">Sin contratos</h3>
            <p className="text-sm text-muted-foreground">Cancela en cualquier momento sin penalizaciones</p>
          </div>
        </div>

        {/* Nota de precios */}
        <div className="text-center text-sm text-gray-500 bg-white p-4 rounded-lg">
          <p>Los precios base se muestran en USD como referencia internacional.</p>
          <p>La facturación se realiza en la moneda local seleccionada.</p>
        </div>
      </div>

      {/* Checkout Modal */}
      {configCheckout && (
        <PlanCheckout
          plan={configCheckout.plan_base}
          configuracion={configCheckout}
          isOpen={checkoutAbierto}
          onClose={() => {
            setCheckoutAbierto(false);
            setConfigCheckout(null);
          }}
          onConfirmar={handleConfirmarCheckout}
        />
      )}
    </div>
  );
}
