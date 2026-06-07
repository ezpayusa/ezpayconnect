import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Stethoscope, Building2, FlaskConical, Truck, Check, ArrowRight, CreditCard } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { usePlanes } from '@/hooks/usePlanes';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { formatearPrecio, getBanderaPais } from '@/lib/planes-utils';

const categorias = [
  { id: 'medico', label: 'Médico', icon: Stethoscope, color: 'blue', path: '/planes' },
  { id: 'clinica', label: 'Clínica', icon: Building2, color: 'blue', path: '/planes-clinica' },
  { id: 'lab', label: 'Laboratorio', icon: FlaskConical, color: 'green', path: '/planes-lab' },
  { id: 'visitador', label: 'Visitador', icon: Truck, color: 'orange', path: '/planes-visitador' },
];

const colorClasses: any = {
  blue: { bg: 'from-blue-600 to-cyan-700', badge: 'bg-blue-100 text-blue-700', button: 'bg-blue-600 hover:bg-blue-700' },
  green: { bg: 'from-green-600 to-emerald-700', badge: 'bg-green-100 text-green-700', button: 'bg-green-600 hover:bg-green-700' },
  orange: { bg: 'from-orange-600 to-amber-700', badge: 'bg-orange-100 text-orange-700', button: 'bg-orange-600 hover:bg-orange-700' },
};

export default function PlanesTodosPage() {
  const { paisId } = usePaisFiltro();
  const { planesBase, planesConfig, paises, loading } = usePlanes({ pais_id: paisId || undefined });
  const navigate = useNavigate();
  const [esAnual, setEsAnual] = useState(false);
  const [paisSeleccionado, setPaisSeleccionado] = useState(paisId || 'GT');

  const getConfigForPlan = (planId: string) => {
    return planesConfig.find(c => c.plan_base_id === planId && c.pais?.codigo === paisSeleccionado);
  };

  const getPlanesByTipo = (tipo: string) => planesBase.filter(p => p.tipo === tipo && p.activo);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      {/* Header simple (sin gradiente ni min-h-screen) */}
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          <CreditCard className="h-8 w-8 text-[#1E5C8E]" />
          <h1 className="text-2xl font-bold text-gray-900">Todos los Planes EZPayConnect</h1>
        </div>
        <p className="text-muted-foreground">
          Elige la solución perfecta para tu negocio. Compara precios y características por categoría.
        </p>
      </div>

      {/* Controles */}
      <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4 bg-white p-4 rounded-xl shadow-sm border">
        <div className="flex gap-2 flex-wrap">
          {paises && paises.map((pais: any) => (
            <Button
              key={pais.id}
              variant={paisSeleccionado === pais.codigo ? 'default' : 'outline'}
              size="sm"
              onClick={() => setPaisSeleccionado(pais.codigo)}
              className={paisSeleccionado === pais.codigo ? 'bg-[#1E5C8E] hover:bg-[#164a70]' : ''}
            >
              {getBanderaPais(pais.codigo)} {pais.nombre}
            </Button>
          ))}
        </div>

        <div className="flex items-center gap-3">
          <Label htmlFor="anual-todos" className={!esAnual ? 'font-semibold text-[#1E5C8E]' : 'text-gray-500'}>
            Mensual
          </Label>
          <Switch id="anual-todos" checked={esAnual} onCheckedChange={setEsAnual} />
          <Label htmlFor="anual-todos" className={esAnual ? 'font-semibold text-[#1E5C8E]' : 'text-gray-500'}>
            Anual
          </Label>
          {esAnual && <Badge className="bg-blue-100 text-blue-700">Ahorra 20%</Badge>}
        </div>
      </div>

      {/* Tabs por categoría */}
      <Tabs defaultValue="medico" className="w-full">
        <TabsList className="grid grid-cols-4 w-full max-w-2xl mx-auto mb-8">
          {categorias.map((cat) => {
            const Icon = cat.icon;
            return (
              <TabsTrigger key={cat.id} value={cat.id} className="flex items-center gap-2">
                <Icon className="h-4 w-4" />
                <span className="hidden sm:inline">{cat.label}</span>
              </TabsTrigger>
            );
          })}
        </TabsList>

        {categorias.map((cat) => {
          const planes = getPlanesByTipo(cat.id);
          const colors = colorClasses[cat.color];

          return (
            <TabsContent key={cat.id} value={cat.id}>
              <div className="mb-6 flex justify-between items-center">
                <h2 className="text-2xl font-bold text-gray-900">Planes {cat.label}</h2>
                <Button variant="outline" onClick={() => navigate(cat.path)}>
                  Ver página dedicada <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>

              {planes.length === 0 ? (
                <Card className="p-8 text-center text-gray-500">
                  No hay planes de {cat.label.toLowerCase()} disponibles.
                </Card>
              ) : (
                <div className={`grid gap-6 ${planes.length === 2 ? 'md:grid-cols-2 max-w-4xl mx-auto' : planes.length === 3 ? 'md:grid-cols-3' : 'md:grid-cols-2 lg:grid-cols-4'}`}>
                  {planes.map((plan) => {
                    const config = getConfigForPlan(plan.id);
                    const precio = esAnual 
                      ? (config?.precio_anual || plan.precio_base * 12 * 0.8)
                      : (config?.precio_local || plan.precio_base);
                    const precioOriginal = esAnual ? (config?.precio_local || plan.precio_base) * 12 : null;
                    const moneda = config?.pais?.moneda || plan.moneda || 'USD';
                    const isPro = plan.nombre.includes('Pro') || plan.nombre.includes('Enterprise');

                    return (
                      <Card key={plan.id} className={`relative overflow-hidden border-2 ${isPro ? `border-${cat.color}-500 shadow-xl` : 'border-gray-200'}`}>
                        {isPro && (
                          <div className={`absolute top-0 right-0 bg-gradient-to-l ${colors.bg} text-white px-4 py-1 rounded-bl-lg text-sm font-semibold`}>
                            Recomendado
                          </div>
                        )}

                        <CardHeader className={`bg-gradient-to-r ${colors.bg} text-white p-6`}>
                          <h3 className="text-xl font-bold">{plan.nombre}</h3>
                          <p className="text-white/80 text-sm mt-1">{plan.descripcion}</p>
                        </CardHeader>

                        <CardContent className="p-6">
                          <div className="mb-4">
                            <div className="flex items-baseline gap-1">
                              <span className="text-3xl font-bold text-gray-900">
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

                          <Button
                            className={`w-full ${isPro ? colors.button : 'bg-gray-900 hover:bg-gray-800'}`}
                            onClick={() => navigate(cat.path)}
                          >
                            Ver detalles <ArrowRight className="ml-2 h-4 w-4" />
                          </Button>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              )}
            </TabsContent>
          );
        })}
      </Tabs>

      {/* Tabla comparativa */}
      <div className="mt-16">
        <h2 className="text-2xl font-bold text-gray-900 mb-6 text-center">Comparativa General</h2>
        <div className="bg-white rounded-xl shadow-sm overflow-x-auto border">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-gray-50">
                <th className="text-left py-3 px-4">Característica</th>
                <th className="text-center py-3 px-4 text-blue-700">Médico</th>
                <th className="text-center py-3 px-4 text-blue-700">Clínica</th>
                <th className="text-center py-3 px-4 text-green-700">Laboratorio</th>
                <th className="text-center py-3 px-4 text-orange-700">Visitador</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Precio desde</td>
                <td className="text-center py-3 px-4">$29.99/mes</td>
                <td className="text-center py-3 px-4">$99.99/mes</td>
                <td className="text-center py-3 px-4">$19.99/mes</td>
                <td className="text-center py-3 px-4">$14.99/mes</td>
              </tr>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Usuarios</td>
                <td className="text-center py-3 px-4">1 - Ilimitados</td>
                <td className="text-center py-3 px-4">5 - Ilimitados</td>
                <td className="text-center py-3 px-4">3 - Ilimitados</td>
                <td className="text-center py-3 px-4">1 - Ilimitados</td>
              </tr>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Pacientes/Clientes</td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4">Órdenes ilimitadas</td>
                <td className="text-center py-3 px-4">50 - Ilimitados</td>
              </tr>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Citas/Rutas</td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4">—</td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
              </tr>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Facturación</td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4">—</td>
                <td className="text-center py-3 px-4">Pedidos</td>
              </tr>
              <tr className="border-b">
                <td className="py-3 px-4 font-medium">Recetas/Órdenes</td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4"><Check className="h-4 w-4 text-green-500 mx-auto" /></td>
                <td className="text-center py-3 px-4">—</td>
              </tr>
              <tr>
                <td className="py-3 px-4 font-medium">Soporte</td>
                <td className="text-center py-3 px-4">Email / 24-7</td>
                <td className="text-center py-3 px-4">Email / 24-7</td>
                <td className="text-center py-3 px-4">Email / 24-7</td>
                <td className="text-center py-3 px-4">Email / 24-7</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
