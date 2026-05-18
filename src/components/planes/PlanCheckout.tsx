import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { CreditCard, Banknote, Smartphone, Check, ArrowRight, Shield, Loader2 } from 'lucide-react';
import type { PlanBase, PlanConfiguracion } from '@/types/planes';
import { formatearPrecio } from '@/lib/planes-utils';

export interface CheckoutData {
  planId: string;
  ciclo: 'mensual' | 'anual';
  metodoPago: 'tarjeta' | 'transferencia' | 'movil';
  precioFinal: number;
  moneda: string;
}

interface PlanCheckoutProps {
  plan: PlanBase;
  configuracion: PlanConfiguracion;
  isOpen: boolean;
  onClose: () => void;
  onConfirmar: (datos: CheckoutData) => void;
}

export function PlanCheckout({ plan, configuracion, isOpen, onClose, onConfirmar }: PlanCheckoutProps) {
  const [ciclo, setCiclo] = useState<'mensual' | 'anual'>('mensual');
  const [metodoPago, setMetodoPago] = useState<'tarjeta' | 'transferencia' | 'movil'>('tarjeta');
  const [paso, setPaso] = useState<1 | 2 | 3>(1);
  const [procesando, setProcesando] = useState(false);

  const precioMensual = configuracion.precio_local;
  const precioAnual = configuracion.precio_anual || precioMensual * 10;

  const ahorroAnual = configuracion.precio_anual
    ? Math.round(((precioMensual * 12 - precioAnual) / (precioMensual * 12)) * 100)
    : 16;

  const precioFinal = ciclo === 'mensual' ? precioMensual : precioAnual;
  const moneda = configuracion.moneda_local || 'USD';

  const handleConfirmar = async () => {
    setProcesando(true);
    try {
      await onConfirmar({
        planId: plan.id,
        ciclo,
        metodoPago,
        precioFinal,
        moneda,
      });
      setPaso(3);
    } catch (error) {
      console.error('Error en checkout:', error);
    } finally {
      setProcesando(false);
    }
  };

  const handleCerrar = () => {
    setPaso(1);
    setCiclo('mensual');
    setMetodoPago('tarjeta');
    onClose();
  };

  return (
    <Dialog open={isOpen} onOpenChange={handleCerrar}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-xl font-bold text-gray-900">
            {paso === 3 ? 'Plan Activado!' : `Contratar ${plan.nombre}`}
          </DialogTitle>
          <DialogDescription>
            {paso === 1 && 'Selecciona tu ciclo de facturacion preferido'}
            {paso === 2 && 'Elige tu metodo de pago'}
            {paso === 3 && 'Tu plan ha sido asignado correctamente'}
          </DialogDescription>
        </DialogHeader>

        {paso === 1 && (
          <div className="space-y-4">
            <RadioGroup value={ciclo} onValueChange={(v: 'mensual' | 'anual') => setCiclo(v)} className="space-y-3">
              <div>
                <RadioGroupItem value="mensual" id="mensual" className="peer sr-only" />
                <Label 
                  htmlFor="mensual" 
                  className="flex items-center justify-between p-4 border-2 rounded-lg cursor-pointer transition-all peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-50 hover:bg-gray-50"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-4 h-4 rounded-full border-2 border-gray-300 peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-500" />
                    <div>
                      <div className="font-semibold text-gray-900">Pago Mensual</div>
                      <div className="text-sm text-gray-500">Flexibilidad total, cancela cuando quieras</div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-bold text-lg text-gray-900">{formatearPrecio(precioMensual, moneda)}/mes</div>
                  </div>
                </Label>
              </div>

              <div>
                <RadioGroupItem value="anual" id="anual" className="peer sr-only" />
                <Label 
                  htmlFor="anual" 
                  className="flex items-center justify-between p-4 border-2 rounded-lg cursor-pointer transition-all peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-50 hover:bg-gray-50 relative overflow-hidden"
                >
                  <div className="absolute top-0 right-0 bg-green-500 text-white text-xs px-2 py-1 rounded-bl-lg font-bold">
                    AHORRA {ahorroAnual}%
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="w-4 h-4 rounded-full border-2 border-gray-300 peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-500" />
                    <div>
                      <div className="font-semibold text-gray-900">Pago Anual</div>
                      <div className="text-sm text-gray-500">2 meses gratis, mejor valor</div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-bold text-lg text-gray-900">{formatearPrecio(precioAnual, moneda)}/ano</div>
                    <div className="text-xs text-green-600 line-through">{formatearPrecio(precioMensual * 12, moneda)}</div>
                  </div>
                </Label>
              </div>
            </RadioGroup>

            <Button 
              className="w-full bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600"
              onClick={() => setPaso(2)}
            >
              Continuar <ArrowRight className="w-4 h-4 ml-2" />
            </Button>
          </div>
        )}

        {paso === 2 && (
          <div className="space-y-4">
            <div className="bg-gray-50 p-4 rounded-lg space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Plan:</span>
                <span className="font-medium">{plan.nombre}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Ciclo:</span>
                <Badge variant="outline">{ciclo === 'mensual' ? 'Mensual' : 'Anual'}</Badge>
              </div>
              <div className="border-t pt-2 flex justify-between items-center">
                <span className="font-semibold text-gray-900">Total a pagar:</span>
                <span className="text-xl font-bold text-cyan-600">{formatearPrecio(precioFinal, moneda)}</span>
              </div>
            </div>

            <div className="space-y-2">
              <Label className="text-sm font-medium">Metodo de Pago</Label>
              <RadioGroup value={metodoPago} onValueChange={(v: 'tarjeta' | 'transferencia' | 'movil') => setMetodoPago(v)} className="grid grid-cols-3 gap-2">
                <div>
                  <RadioGroupItem value="tarjeta" id="tarjeta" className="peer sr-only" />
                  <Label htmlFor="tarjeta" className="flex flex-col items-center p-3 border-2 rounded-lg cursor-pointer peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-50 hover:bg-gray-50">
                    <CreditCard className="w-6 h-6 mb-1 text-gray-600" />
                    <span className="text-xs font-medium">Tarjeta</span>
                  </Label>
                </div>
                <div>
                  <RadioGroupItem value="transferencia" id="transferencia" className="peer sr-only" />
                  <Label htmlFor="transferencia" className="flex flex-col items-center p-3 border-2 rounded-lg cursor-pointer peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-50 hover:bg-gray-50">
                    <Banknote className="w-6 h-6 mb-1 text-gray-600" />
                    <span className="text-xs font-medium">Transferencia</span>
                  </Label>
                </div>
                <div>
                  <RadioGroupItem value="movil" id="movil" className="peer sr-only" />
                  <Label htmlFor="movil" className="flex flex-col items-center p-3 border-2 rounded-lg cursor-pointer peer-data-[state=checked]:border-cyan-500 peer-data-[state=checked]:bg-cyan-50 hover:bg-gray-50">
                    <Smartphone className="w-6 h-6 mb-1 text-gray-600" />
                    <span className="text-xs font-medium">Movil</span>
                  </Label>
                </div>
              </RadioGroup>
            </div>

            <div className="flex items-center gap-2 text-xs text-gray-500 bg-blue-50 p-3 rounded-lg">
              <Shield className="w-4 h-4 text-blue-500" />
              <span>Pago seguro procesado por EZPayConnect. Tu informacion esta protegida.</span>
            </div>

            <div className="flex gap-3">
              <Button variant="outline" className="flex-1" onClick={() => setPaso(1)}>Atras</Button>
              <Button 
                className="flex-1 bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600"
                onClick={handleConfirmar}
                disabled={procesando}
              >
                {procesando ? (
                  <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Procesando...</>
                ) : (
                  'Confirmar Pago'
                )}
              </Button>
            </div>
          </div>
        )}

        {paso === 3 && (
          <div className="text-center space-y-4 py-4">
            <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto">
              <Check className="w-8 h-8 text-green-600" />
            </div>
            <div>
              <h3 className="font-bold text-lg text-gray-900">Activacion Exitosa!</h3>
              <p className="text-sm text-gray-500 mt-1">
                Tu plan <span className="font-medium text-cyan-700">{plan.nombre}</span> ha sido activado con ciclo {ciclo}.
              </p>
            </div>
            <div className="bg-gray-50 p-4 rounded-lg text-left space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-600">ID de asignacion:</span>
                <span className="font-mono text-xs">Generado automaticamente</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Proximo pago:</span>
                <span className="font-medium">{ciclo === 'mensual' ? '30 dias' : '12 meses'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Metodo:</span>
                <span className="font-medium capitalize">{metodoPago}</span>
              </div>
            </div>
            <Button className="w-full bg-cyan-500 hover:bg-cyan-600" onClick={handleCerrar}>
              Ir al Dashboard
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
