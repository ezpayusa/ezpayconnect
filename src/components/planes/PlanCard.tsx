import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Check, Sparkles, Crown, Stethoscope } from 'lucide-react';
import type { PlanConfiguracion } from '@/types/planes';
import { formatearPrecio, getColorPlan } from '@/lib/planes-utils';

interface PlanCardProps {
  config: PlanConfiguracion;
  destacado?: boolean;
  onSeleccionar: (config: PlanConfiguracion) => void;
}

const iconosPlan: Record<string, React.ReactNode> = {
  basico: <Sparkles className="h-6 w-6" />,
  profesional: <Crown className="h-6 w-6" />,
  medico: <Stethoscope className="h-6 w-6" />,
};

export function PlanCard({ config, destacado, onSeleccionar }: PlanCardProps) {
  const base = config.plan_base;
  if (!base) return null;

  const color = getColorPlan(base.tipo);
  const precioFinal = config.precio_local * (1 - config.descuento_porcentaje / 100);

  return (
    <Card className={`relative overflow-hidden transition-all duration-300 hover:shadow-xl ${destacado ? 'border-2 scale-105 shadow-lg' : 'border'}`}
      style={destacado ? { borderColor: color } : undefined}>
      {destacado && (
        <div className="absolute top-0 left-0 right-0 text-center py-1 text-xs font-bold text-white" style={{ backgroundColor: color }}>
          MÁS POPULAR
        </div>
      )}
      <CardHeader className="pb-4 pt-8">
        <div className="flex items-center gap-3 mb-2">
          <div className="p-2 rounded-lg text-white" style={{ backgroundColor: color }}>
            {iconosPlan[base.tipo] || <Stethoscope className="h-6 w-6" />}
          </div>
          <div>
            <h3 className="text-xl font-bold">{base.nombre}</h3>
            <p className="text-sm text-muted-foreground">{base.descripcion}</p>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="text-center">
          <div className="flex items-baseline justify-center gap-1">
            <span className="text-4xl font-bold">{formatearPrecio(precioFinal, base.moneda)}</span>
            <span className="text-muted-foreground">/{base.periodicidad}</span>
          </div>
          {config.descuento_porcentaje > 0 && (
            <Badge variant="secondary" className="mt-2 bg-green-100 text-green-700">
              -{config.descuento_porcentaje}% descuento
            </Badge>
          )}
          {config.comision_aplicada > 0 && (
            <p className="text-xs text-muted-foreground mt-1">
              +{config.comision_aplicada}% comisión aplicada
            </p>
          )}
        </div>
        <ul className="space-y-3">
          <li className="flex items-center gap-3 text-sm">
            <Check className="h-4 w-4 text-green-500 shrink-0" />
            <span>Precio base: {formatearPrecio(base.precio_base, 'USD')} <span className="text-muted-foreground">(USD)</span></span>
          </li>
          <li className="flex items-center gap-3 text-sm">
            <Check className="h-4 w-4 text-green-500 shrink-0" />
            <span>Precio local: {formatearPrecio(config.precio_local, base.moneda)}</span>
          </li>
          {config.descuento_porcentaje > 0 && (
            <li className="flex items-center gap-3 text-sm text-green-600">
              <Check className="h-4 w-4 shrink-0" />
              <span>Descuento: {config.descuento_porcentaje}%</span>
            </li>
          )}
        </ul>
        <Button className="w-full text-white" style={{ backgroundColor: color }} onClick={() => onSeleccionar(config)}>
          Seleccionar Plan
        </Button>
      </CardContent>
    </Card>
  );
}