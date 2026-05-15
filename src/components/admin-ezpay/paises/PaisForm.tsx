import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';

export interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}

interface PaisFormProps {
  pais: PaisConfig | null;
  open: boolean;
  onClose: () => void;
  onSave: (id: string, data: Partial<PaisConfig>) => void;
  saving: boolean;
}

export function PaisForm({ pais, open, onClose, onSave, saving }: PaisFormProps) {
  const [formData, setFormData] = useState<Partial<PaisConfig>>({
    nombre: pais?.nombre || '',
    moneda: pais?.moneda || '',
    comisiones_activas: pais?.comisiones_activas || false,
    porcentaje_comision_default: pais?.porcentaje_comision_default || 0,
    activo: pais?.activo ?? true,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (pais) {
      onSave(pais.id, formData);
    }
  };

  if (!pais) return null;

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-[#1E5C8E]">
            <span className="text-2xl">
              {pais.codigo === 'GT' ? '🇬🇹' : pais.codigo === 'SV' ? '🇸🇻' : '🇭🇳'}
            </span>
            Editar {pais.nombre}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="nombre">Nombre del país</Label>
              <Input
                id="nombre"
                value={formData.nombre}
                onChange={(e) => setFormData({ ...formData, nombre: e.target.value })}
                className="border-gray-200 focus:ring-[#87CEEB]"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="moneda">Moneda</Label>
              <Input
                id="moneda"
                value={formData.moneda}
                onChange={(e) => setFormData({ ...formData, moneda: e.target.value })}
                className="border-gray-200 focus:ring-[#87CEEB]"
              />
            </div>
          </div>

          <div className="space-y-4">
            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
              <div>
                <Label className="font-medium text-gray-800">Comisiones activas</Label>
                <p className="text-sm text-gray-500">Permitir cobro de comisiones en este país</p>
              </div>
              <Switch
                checked={formData.comisiones_activas}
                onCheckedChange={(checked) => setFormData({ ...formData, comisiones_activas: checked })}
                className="data-[state=checked]:bg-[#87CEEB]"
              />
            </div>

            {formData.comisiones_activas && (
              <div className="space-y-2">
                <Label htmlFor="comision">Porcentaje de comisión (%)</Label>
                <Input
                  id="comision"
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  value={formData.porcentaje_comision_default}
                  onChange={(e) => setFormData({ ...formData, porcentaje_comision_default: parseFloat(e.target.value) })}
                  className="border-gray-200 focus:ring-[#87CEEB]"
                />
              </div>
            )}

            <div className="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
              <div>
                <Label className="font-medium text-gray-800">País activo</Label>
                <p className="text-sm text-gray-500">Determina si el país está disponible en la plataforma</p>
              </div>
              <Switch
                checked={formData.activo}
                onCheckedChange={(checked) => setFormData({ ...formData, activo: checked })}
                className="data-[state=checked]:bg-[#1E5C8E]"
              />
            </div>
          </div>

          <div className="flex gap-3 pt-2">
            <Button
              type="button"
              variant="outline"
              onClick={onClose}
              className="flex-1"
            >
              Cancelar
            </Button>
            <Button
              type="submit"
              disabled={saving}
              className="flex-1 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white"
            >
              {saving ? 'Guardando...' : 'Guardar cambios'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
