import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Check, Zap, Building2 } from 'lucide-react';
import type { PlanBase, PlanConfiguracion, PlanAsignacion } from '@/types/planes';
import { formatearPrecio } from '@/lib/planes-utils';

interface PlanCardProps {
  plan?: PlanBase;
  configuracion?: PlanConfiguracion;
  config?: PlanConfiguracion;
  asignacionActual?: PlanAsignacion;
  onSeleccionar?: (planId: string, ciclo?: 'mensual' | 'anual') => void;
  onSeleccionarConfig?: (config: PlanConfiguracion) => void;
  compacto?: boolean;
  destacado?: boolean;
}

export function PlanCard({ 
  plan, 
  configuracion, 
  config,
  asignacionActual, 
  onSeleccionar, 
  onSeleccionarConfig,
  compacto = false,
  destacado = false
}: PlanCardProps) {
  const [cicloSeleccionado, setCicloSeleccionado] = useState<'mensual' | 'anual'>('mensual');

  // Usar config o configuracion (ambos nombres soportados)
  const configFinal = config || configuracion;
  const planFinal = plan || configFinal?.plan_base;

  if (!planFinal || !configFinal) {
    return null;
  }

  // CORRECCIÓN: Precio base siempre en USD (del plan base)
  const precioBaseUSD = planFinal.precio_base;
  
  // Precios locales según ciclo
  const precioLocalMensual = configFinal.precio_local;
  const precioAnualLocal = configFinal.precio_anual || precioLocalMensual * 10; // 2 meses gratis por defecto
  
  // Cálculo de ahorro anual
  const ahorroAnual = configFinal.precio_anual
    ? Math.round(((precioLocalMensual * 12 - precioAnualLocal) / (precioLocalMensual * 12)) * 100)
    : 16; // ~16% si no está definido (2 meses gratis)

  const precioMostrar = cicloSeleccionado === 'mensual' ? precioLocalMensual : precioAnualLocal;
  const monedaLocal = configFinal.moneda_local || 'USD';

  const esPopular = planFinal.nombre?.toLowerCase().includes('pro') || 
                    planFinal.nombre?.toLowerCase().includes('profesional') || 
                    planFinal.popular || 
                    destacado;
  
  const estaActivo = asignacionActual?.estado === 'activo';

  const handleClick = () => {
    if (onSeleccionar) {
      onSeleccionar(planFinal.id, cicloSeleccionado);
    }
    if (onSeleccionarConfig) {
      onSeleccionarConfig(configFinal);
    }
  };

  return (
    <Card className={`relative overflow-hidden transition-all duration-300 hover:shadow-lg ${
      esPopular ? 'border-2 border-cyan-400 shadow-cyan-100' : 'border border-gray-200'
    } ${compacto ? 'max-w-sm' : 'w-full'}`}>
      
      {esPopular && (
        <div className="absolute top-0 right-0 bg-gradient-to-l from-cyan-500 to-blue-500 text-white px-4 py-1 text-xs font-bold rounded-bl-lg">
          MÁS POPULAR
        </div>
      )}

      {estaActivo && (
        <Badge className="absolute top-4 left-4 bg-green-500 text-white">
          Plan Actual
        </Badge>
      )}

      <CardHeader className="text-center pb-4">
        <div className="mx-auto w-12 h-12 bg-cyan-50 rounded-full flex items-center justify-center mb-3">
          {planFinal.tipo === 'medico' ? <Zap className="w-6 h-6 text-cyan-600" /> : <Building2 className="w-6 h-6 text-cyan-600" />}
        </div>
        <CardTitle className="text-xl font-bold text-gray-900">{planFinal.nombre}</CardTitle>
        <CardDescription className="text-sm text-gray-500">{planFinal.descripcion}</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* PRECIO BASE EN USD (CORRECCIÓN) */}
        <div className="text-center space-y-1">
          <div className="text-3xl font-bold text-gray-900">
            {formatearPrecio(precioMostrar, monedaLocal)}
            <span className="text-sm font-normal text-gray-500">/{cicloSeleccionado === 'mensual' ? 'mes' : 'año'}</span>
          </div>
          
          {/* Precio base en USD con etiqueta */}
          <div className="text-sm text-gray-500 font-medium">
            {formatearPrecio(precioBaseUSD, 'USD')} <span className="text-xs text-gray-400">(USD base)</span>
          </div>

          {/* Selector de ciclo */}
          <div className="flex justify-center gap-2 mt-3">
            <button
              onClick={() => setCicloSeleccionado('mensual')}
              className={`px-3 py-1 text-xs rounded-full transition-colors ${
                cicloSeleccionado === 'mensual' 
                  ? 'bg-cyan-500 text-white' 
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              Mensual
            </button>
            <button
              onClick={() => setCicloSeleccionado('anual')}
              className={`px-3 py-1 text-xs rounded-full transition-colors relative ${
                cicloSeleccionado === 'anual' 
                  ? 'bg-cyan-500 text-white' 
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              Anual
              <span className="absolute -top-2 -right-2 bg-green-500 text-white text-[10px] px-1.5 py-0.5 rounded-full">
                Ahorra {ahorroAnual}%
              </span>
            </button>
          </div>
        </div>

        {/* Características */}
        <ul className="space-y-2 text-sm">
          {planFinal.caracteristicas?.map((caracteristica, idx) => (
            <li key={idx} className="flex items-start gap-2">
              <Check className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
              <span className="text-gray-600">{caracteristica}</span>
            </li>
          )) || (
            <>
              <li className="flex items-start gap-2">
                <Check className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                <span className="text-gray-600">Acceso completo al dashboard médico</span>
              </li>
              <li className="flex items-start gap-2">
                <Check className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                <span className="text-gray-600">Gestión de pacientes ilimitada</span>
              </li>
              <li className="flex items-start gap-2">
                <Check className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                <span className="text-gray-600">Soporte técnico prioritario</span>
              </li>
            </>
          )}
        </ul>
      </CardContent>

      <CardFooter className="pt-4">
        <Button 
          className={`w-full ${esPopular ? 'bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600' : 'bg-gray-900 hover:bg-gray-800'}`}
          onClick={handleClick}
          disabled={estaActivo}
        >
          {estaActivo ? 'Plan Activo' : cicloSeleccionado === 'anual' ? 'Elegir Plan Anual' : 'Elegir Plan Mensual'}
        </Button>
      </CardFooter>
    </Card>
  );
}