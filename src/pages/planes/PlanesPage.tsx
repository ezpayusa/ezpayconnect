import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { PlanCard } from '@/components/planes/PlanCard';
import { usePlanes } from '@/hooks/usePlanes';
import { useAuth } from '@/hooks/useAuth';
import type { PlanConfiguracion } from '@/types/planes';
import { getNombrePais, getBanderaPais, getColorPlan } from '@/lib/planes-utils';
import { Zap, Shield, Globe, CheckCircle2 } from 'lucide-react';

export default function PlanesPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { planesConfig, paises, loading } = usePlanes();
  const [paisSeleccionado, setPaisSeleccionado] = useState<string>('');

  // Filtrar solo planes médicos
  const planesMedicos = planesConfig.filter(p => p.plan_base?.tipo === 'medico');

  // Obtener países únicos de las configuraciones
  const paisesUnicos = paises.filter(p => planesMedicos.some(pm => pm.pais_id === p.id));

  // Seleccionar primer país por defecto
  if (!paisSeleccionado && paisesUnicos.length > 0) {
    setPaisSeleccionado(paisesUnicos[0].id);
  }

  const planesFiltrados = planesMedicos.filter(p => p.pais_id === paisSeleccionado);
  const paisActual = paises.find(p => p.id === paisSeleccionado);

  const handleSeleccionar = (config: PlanConfiguracion) => {
    if (!user) {
      navigate('/login', { state: { redirect: '/planes', plan: config.id } });
      return;
    }
    // Aquí iría el checkout
    navigate('/dashboard');
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary" />
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-6xl">
      <div className="text-center mb-12">
        <Badge variant="secondary" className="mb-4 bg-[#1E5C8E]/10 text-[#1E5C8E]">
          <Zap className="h-3 w-3 mr-1" />
          Planes diseñados para médicos
        </Badge>
        <h1 className="text-4xl font-bold mb-4">Elige el plan perfecto para tu práctica</h1>
        <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
          Desde médicos independientes hasta grandes grupos médicos.
        </p>
      </div>

      {paisesUnicos.length > 0 && (
        <div className="flex justify-center mb-8">
          <Tabs value={paisSeleccionado} onValueChange={setPaisSeleccionado}>
            <TabsList className="bg-muted">
              {paisesUnicos.map(pais => (
                <TabsTrigger key={pais.id} value={pais.id} className="flex items-center gap-2">
                  {getBanderaPais(pais.codigo as any)}
                  {pais.nombre}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16 items-start">
        {planesFiltrados.map((config) => (
          <PlanCard
            key={config.id}
            config={config}
            destacado={config.plan_base?.nombre?.toLowerCase().includes('profesional')}
            onSeleccionar={handleSeleccionar}
          />
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-16">
        <div className="text-center">
          <div className="h-12 w-12 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center mx-auto mb-4">
            <Shield className="h-6 w-6 text-[#1E5C8E]" />
          </div>
          <h3 className="font-semibold mb-2">Seguridad HIPAA</h3>
          <p className="text-sm text-muted-foreground">Cumplimiento total con normativas de protección de datos médicos</p>
        </div>
        <div className="text-center">
          <div className="h-12 w-12 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center mx-auto mb-4">
            <Globe className="h-6 w-6 text-[#1E5C8E]" />
          </div>
          <h3 className="font-semibold mb-2">Multi-país</h3>
          <p className="text-sm text-muted-foreground">Operaciones en Guatemala, El Salvador y Honduras</p>
        </div>
        <div className="text-center">
          <div className="h-12 w-12 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center mx-auto mb-4">
            <CheckCircle2 className="h-6 w-6 text-[#1E5C8E]" />
          </div>
          <h3 className="font-semibold mb-2">Sin contratos</h3>
          <p className="text-sm text-muted-foreground">Cancela en cualquier momento sin penalizaciones</p>
        </div>
      </div>
    </div>
  );
}