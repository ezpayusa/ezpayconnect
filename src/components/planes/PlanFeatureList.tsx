// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - PlanFeatureList
// Lista visual de características de un plan
// ═══════════════════════════════════════════════════════════════

import { Check, X, Users, UserCheck, Calendar, FileText, Receipt, Pill, BarChart3, MessageCircle, Code, Headphones, Infinity } from 'lucide-react';
import type { PlanConfiguracion, PlanFeature } from '@/types/planes';
import { generarFeaturesPlan } from '@/lib/planes-utils';

interface PlanFeatureListProps {
  config: PlanConfiguracion;
  compact?: boolean;
  showExcluded?: boolean;
}

const iconMap: Record<string, React.ReactNode> = {
  Users: <Users className="h-4 w-4" />,
  UserCheck: <UserCheck className="h-4 w-4" />,
  Calendar: <Calendar className="h-4 w-4" />,
  FileText: <FileText className="h-4 w-4" />,
  Receipt: <Receipt className="h-4 w-4" />,
  Pill: <Pill className="h-4 w-4" />,
  BarChart3: <BarChart3 className="h-4 w-4" />,
  MessageCircle: <MessageCircle className="h-4 w-4" />,
  Code: <Code className="h-4 w-4" />,
  Headphones: <Headphones className="h-4 w-4" />,
};

export function PlanFeatureList({ config, compact = false, showExcluded = true }: PlanFeatureListProps) {
  const features = generarFeaturesPlan(config);

  if (compact) {
    return (
      <div className="flex flex-wrap gap-2">
        {features.filter(f => f.included).map((feature, idx) => (
          <div key={idx} className="flex items-center gap-1 text-xs bg-muted px-2 py-1 rounded-full">
            <Check className="h-3 w-3 text-green-500" />
            {feature.label}
            {feature.value !== undefined && <span className="font-semibold">{feature.value}</span>}
          </div>
        ))}
      </div>
    );
  }

  return (
    <ul className="space-y-2">
      {features.map((feature, idx) => {
        if (!feature.included && !showExcluded) return null;

        return (
          <li 
            key={idx} 
            className={`flex items-center gap-3 text-sm ${!feature.included ? 'text-muted-foreground' : ''}`}
          >
            <div className="shrink-0">
              {feature.included ? (
                <div className="h-5 w-5 rounded-full bg-green-100 flex items-center justify-center">
                  <Check className="h-3 w-3 text-green-600" />
                </div>
              ) : (
                <div className="h-5 w-5 rounded-full bg-gray-100 flex items-center justify-center">
                  <X className="h-3 w-3 text-gray-400" />
                </div>
              )}
            </div>

            <div className="flex items-center gap-2">
              {feature.icon && iconMap[feature.icon] && (
                <span className="text-muted-foreground">{iconMap[feature.icon]}</span>
              )}
              <span>{feature.label}</span>
              {feature.value !== undefined && feature.included && (
                <span className="font-semibold text-foreground">
                  {feature.value === 'Ilimitados' || feature.value === 'Ilimitadas' ? (
                    <span className="flex items-center gap-1">
                      <Infinity className="h-3 w-3" />
                      Ilimitado
                    </span>
                  ) : (
                    feature.value
                  )}
                </span>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}
