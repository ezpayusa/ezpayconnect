// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - PlanCheckout
// Modal de checkout para suscripción a plan
// ═══════════════════════════════════════════════════════════════

import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Check, CreditCard, Building, Smartphone, ArrowRight, Tag } from 'lucide-react';
import { PlanConfiguracion } from '@/types/planes';
import { formatearPrecio, calcularAhorroAnual, getColorPlan } from '@/lib/planes-utils';

interface PlanCheckoutProps {
  config: PlanConfiguracion | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirmar: (data: {
    configId: string;
    ciclo: 'mensual' | 'anual';
    metodoPago: string;
    codigoDescuento?: string;
  }) => void;
  precioConDescuento?: { precio: number; descuento: number; tipo: string };
}

export function PlanCheckout({ config, open, onOpenChange, onConfirmar, precioConDescuento }: PlanCheckoutProps) {
  const [ciclo, setCiclo] = useState<'mensual' | 'anual'>('mensual');
  const [metodoPago, setMetodoPago] = useState('tarjeta');
  const [codigoDescuento, setCodigoDescuento] = useState('');
  const [aplicandoDescuento, setAplicandoDescuento] = useState(false);

  if (!config) return null;

  const precioBase = ciclo === 'anual' ? config.precio_anual : config.precio_mensual;
  const precioFinal = precioConDescuento?.precio || precioBase;
  const descuento = precioConDescuento?.descuento || 0;
  const { porcentaje } = calcularAhorroAnual(config.precio_mensual, config.precio_anual);
  const color = getColorPlan(config.plan_base?.codigo || '');

  const handleConfirmar = () => {
    onConfirmar({
      configId: config.id,
      ciclo,
      metodoPago,
      codigoDescuento: codigoDescuento || undefined,
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <div className="p-1.5 rounded text-white" style={{ backgroundColor: color }}>
              <Check className="h-4 w-4" />
            </div>
            Suscribirse a {config.plan_base?.nombre}
          </DialogTitle>
          <DialogDescription>
            Configure los detalles de su suscripción
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6">
          {/* Selector de ciclo */}
          <div className="space-y-3">
            <Label>Periodicidad de pago</Label>
            <RadioGroup value={ciclo} onValueChange={(v) => setCiclo(v as any)} className="grid grid-cols-2 gap-4">
              <div className={`border rounded-lg p-4 cursor-pointer transition-all ${ciclo === 'mensual' ? 'border-2' : 'border'}`}
                   style={ciclo === 'mensual' ? { borderColor: color } : undefined}>
                <RadioGroupItem value="mensual" id="mensual" className="sr-only" />
                <Label htmlFor="mensual" className="cursor-pointer">
                  <div className="font-semibold">Mensual</div>
                  <div className="text-sm text-muted-foreground">
                    {formatearPrecio(config.precio_mensual, config.moneda)}/mes
                  </div>
                </Label>
              </div>
              <div className={`border rounded-lg p-4 cursor-pointer transition-all ${ciclo === 'anual' ? 'border-2' : 'border'}`}
                   style={ciclo === 'anual' ? { borderColor: color } : undefined}>
                <RadioGroupItem value="anual" id="anual" className="sr-only" />
                <Label htmlFor="anual" className="cursor-pointer">
                  <div className="font-semibold flex items-center gap-2">
                    Anual
                    {porcentaje > 0 && (
                      <Badge className="bg-green-100 text-green-700 text-xs">-{porcentaje}%</Badge>
                    )}
                  </div>
                  <div className="text-sm text-muted-foreground">
                    {formatearPrecio(config.precio_anual, config.moneda)}/año
                  </div>
                </Label>
              </div>
            </RadioGroup>
          </div>

          {/* Método de pago */}
          <div className="space-y-3">
            <Label>Método de pago</Label>
            <RadioGroup value={metodoPago} onValueChange={setMetodoPago} className="grid grid-cols-3 gap-3">
              <div className={`border rounded-lg p-3 cursor-pointer text-center transition-all ${metodoPago === 'tarjeta' ? 'border-2' : 'border'}`}
                   style={metodoPago === 'tarjeta' ? { borderColor: color } : undefined}>
                <RadioGroupItem value="tarjeta" id="tarjeta" className="sr-only" />
                <Label htmlFor="tarjeta" className="cursor-pointer flex flex-col items-center gap-1">
                  <CreditCard className="h-5 w-5" />
                  <span className="text-xs">Tarjeta</span>
                </Label>
              </div>
              <div className={`border rounded-lg p-3 cursor-pointer text-center transition-all ${metodoPago === 'transferencia' ? 'border-2' : 'border'}`}
                   style={metodoPago === 'transferencia' ? { borderColor: color } : undefined}>
                <RadioGroupItem value="transferencia" id="transferencia" className="sr-only" />
                <Label htmlFor="transferencia" className="cursor-pointer flex flex-col items-center gap-1">
                  <Building className="h-5 w-5" />
                  <span className="text-xs">Transferencia</span>
                </Label>
              </div>
              <div className={`border rounded-lg p-3 cursor-pointer text-center transition-all ${metodoPago === 'movil' ? 'border-2' : 'border'}`}
                   style={metodoPago === 'movil' ? { borderColor: color } : undefined}>
                <RadioGroupItem value="movil" id="movil" className="sr-only" />
                <Label htmlFor="movil" className="cursor-pointer flex flex-col items-center gap-1">
                  <Smartphone className="h-5 w-5" />
                  <span className="text-xs">Móvil</span>
                </Label>
              </div>
            </RadioGroup>
          </div>

          {/* Código de descuento */}
          <div className="space-y-2">
            <Label htmlFor="descuento" className="flex items-center gap-2">
              <Tag className="h-4 w-4" />
              Código de descuento (opcional)
            </Label>
            <div className="flex gap-2">
              <Input
                id="descuento"
                placeholder="Ingrese código"
                value={codigoDescuento}
                onChange={(e) => setCodigoDescuento(e.target.value)}
              />
              <Button 
                variant="outline" 
                onClick={() => setAplicandoDescuento(true)}
                disabled={!codigoDescuento}
              >
                Aplicar
              </Button>
            </div>
          </div>

          <Separator />

          {/* Resumen */}
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Plan {config.plan_base?.nombre}</span>
              <span>{formatearPrecio(precioBase, config.moneda)}</span>
            </div>
            {descuento > 0 && (
              <div className="flex justify-between text-green-600">
                <span>Descuento aplicado</span>
                <span>-{formatearPrecio(descuento, config.moneda)}</span>
              </div>
            )}
            <Separator />
            <div className="flex justify-between text-lg font-bold">
              <span>Total a pagar</span>
              <span style={{ color }}>{formatearPrecio(precioFinal, config.moneda)}</span>
            </div>
            <p className="text-xs text-muted-foreground text-center">
              {ciclo === 'mensual' ? 'Se renueva mensualmente' : 'Se renueva anualmente'}. Puede cancelar en cualquier momento.
            </p>
          </div>

          {/* Botón confirmar */}
          <Button 
            className="w-full text-white"
            style={{ backgroundColor: color }}
            onClick={handleConfirmar}
          >
            Confirmar suscripción
            <ArrowRight className="h-4 w-4 ml-2" />
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
