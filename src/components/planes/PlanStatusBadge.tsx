import { Badge } from '@/components/ui/badge';
import { Clock, CheckCircle2, XCircle, AlertTriangle, PauseCircle } from 'lucide-react';
import type { EstadoPlan } from '@/types/planes';
import { getEstadoConfig, diasRestantes, expiraPronto } from '@/lib/planes-utils';

interface PlanStatusBadgeProps {
  estado: EstadoPlan;
  fechaFin?: string | null;
  showDias?: boolean;
}

const iconosEstado: Record<string, React.ReactNode> = {
  activo: <CheckCircle2 className="h-3 w-3" />,
  inactivo: <PauseCircle className="h-3 w-3" />,
  pendiente: <Clock className="h-3 w-3" />,
  suspendido: <AlertTriangle className="h-3 w-3" />,
  cancelado: <XCircle className="h-3 w-3" />,
};

export function PlanStatusBadge({ estado, fechaFin, showDias = true }: PlanStatusBadgeProps) {
  const config = getEstadoConfig(estado);
  const dias = fechaFin ? diasRestantes(fechaFin) : -1;
  const alerta = fechaFin ? expiraPronto(fechaFin) : false;

  return (
    <div className="flex items-center gap-2">
      <Badge 
        variant="secondary" 
        className={`${config.bg} ${config.color} gap-1`}
      >
        {iconosEstado[estado]}
        {config.label}
      </Badge>
      
      {showDias && fechaFin && dias >= 0 && (
        <Badge 
          variant="outline" 
          className={`text-xs ${alerta ? 'border-red-300 text-red-600 bg-red-50' : 'text-muted-foreground'}`}
        >
          {dias === 0 ? 'Expira hoy' : dias === 1 ? '1 día restante' : `${dias} días`}
        </Badge>
      )}
    </div>
  );
}