// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - PlanComparison
// Tabla comparativa de planes
// ═══════════════════════════════════════════════════════════════

import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Check, X, Minus } from 'lucide-react';
import type { PlanConfiguracion } from '@/types/planes';
import { formatearPrecio, getColorPlan, getNombrePais, getBanderaPais } from '@/lib/planes-utils';

interface PlanComparisonProps {
  planes: PlanConfiguracion[];
  ciclo: 'mensual' | 'anual';
  pais: string;
}

export function PlanComparison({ planes, ciclo, pais }: PlanComparisonProps) {
  const features = [
    { key: 'max_medicos', label: 'Médicos', type: 'number' },
    { key: 'max_pacientes', label: 'Pacientes', type: 'number' },
    { key: 'max_citas_mes', label: 'Citas/mes', type: 'number' },
    { key: 'incluye_recetas', label: 'Recetas electrónicas', type: 'boolean' },
    { key: 'incluye_facturacion', label: 'Facturación', type: 'boolean' },
    { key: 'incluye_farmacias', label: 'Farmacias', type: 'boolean' },
    { key: 'incluye_reportes_avanzados', label: 'Reportes avanzados', type: 'boolean' },
    { key: 'incluye_whatsapp', label: 'WhatsApp', type: 'boolean' },
    { key: 'incluye_api', label: 'API Access', type: 'boolean' },
    { key: 'soporte_tipo', label: 'Soporte', type: 'text' },
  ];

  const renderValue = (plan: PlanConfiguracion, feature: typeof features[0]) => {
    const value = plan[feature.key as keyof PlanConfiguracion];

    if (feature.type === 'boolean') {
      return value ? (
        <Check className="h-5 w-5 text-green-500 mx-auto" />
      ) : (
        <X className="h-5 w-5 text-gray-300 mx-auto" />
      );
    }

    if (feature.type === 'number') {
      const num = value as number;
      return <span className="font-semibold">{num === -1 ? 'Ilimitado' : num}</span>;
    }

    return <span className="capitalize">{String(value).replace('_', ' ')}</span>;
  };

  return (
    <div className="rounded-lg border overflow-hidden">
      <div className="bg-muted px-4 py-3 flex items-center gap-2">
        <span className="text-lg">{getBanderaPais(pais as any)}</span>
        <span className="font-semibold">Comparación de planes en {getNombrePais(pais as any)}</span>
      </div>

      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[200px] bg-muted/50">Característica</TableHead>
              {planes.map(plan => (
                <TableHead 
                  key={plan.id} 
                  className="text-center min-w-[140px]"
                  style={{ color: getColorPlan(plan.plan_base?.codigo || '') }}
                >
                  <div className="font-bold">{plan.plan_base?.nombre}</div>
                  <div className="text-sm font-normal text-muted-foreground">
                    {formatearPrecio(
                      ciclo === 'anual' ? plan.precio_anual : plan.precio_mensual,
                      plan.moneda
                    )}
                    <span className="text-xs">/{ciclo === 'anual' ? 'año' : 'mes'}</span>
                  </div>
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {features.map((feature, idx) => (
              <TableRow key={feature.key} className={idx % 2 === 0 ? 'bg-muted/20' : ''}>
                <TableCell className="font-medium">{feature.label}</TableCell>
                {planes.map(plan => (
                  <TableCell key={`${plan.id}-${feature.key}`} className="text-center">
                    {renderValue(plan, feature)}
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
