// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - PlanCountryConfig
// Configuración de precios y límites por país (Admin)
// ═══════════════════════════════════════════════════════════════

import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Save, RotateCcw, DollarSign, Users, UserCheck, Calendar, Globe } from 'lucide-react';
import { PlanConfiguracion, PaisCodigo, TipoSoporte } from '@/types/planes';
import { getNombrePais, getBanderaPais, formatearPrecio } from '@/lib/planes-utils';

interface PlanCountryConfigProps {
  config: PlanConfiguracion;
  onGuardar: (id: string, data: Partial<PlanConfiguracion>) => void;
  soloLectura?: boolean;
}

export function PlanCountryConfig({ config, onGuardar, soloLectura = false }: PlanCountryConfigProps) {
  const [editando, setEditando] = useState(false);
  const [datos, setDatos] = useState<PlanConfiguracion>(config);

  const handleChange = (campo: keyof PlanConfiguracion, valor: any) => {
    setDatos(prev => ({ ...prev, [campo]: valor }));
  };

  const handleGuardar = () => {
    onGuardar(config.id, {
      precio_mensual: datos.precio_mensual,
      precio_anual: datos.precio_anual,
      max_medicos: datos.max_medicos,
      max_pacientes: datos.max_pacientes,
      max_citas_mes: datos.max_citas_mes,
      incluye_recetas: datos.incluye_recetas,
      incluye_facturacion: datos.incluye_facturacion,
      incluye_farmacias: datos.incluye_farmacias,
      incluye_reportes_avanzados: datos.incluye_reportes_avanzados,
      incluye_whatsapp: datos.incluye_whatsapp,
      incluye_api: datos.incluye_api,
      soporte_tipo: datos.soporte_tipo,
    });
    setEditando(false);
  };

  const handleCancelar = () => {
    setDatos(config);
    setEditando(false);
  };

  const renderInput = (campo: keyof PlanConfiguracion, label: string, icon: React.ReactNode, type: 'number' | 'text' = 'number') => (
    <div className="space-y-2">
      <Label className="flex items-center gap-2 text-sm">
        {icon}
        {label}
      </Label>
      <Input
        type={type}
        value={datos[campo] as any}
        onChange={(e) => handleChange(campo, type === 'number' ? parseInt(e.target.value) || 0 : e.target.value)}
        disabled={!editando || soloLectura}
        className={!editando ? 'bg-muted' : ''}
      />
    </div>
  );

  const renderSwitch = (campo: keyof PlanConfiguracion, label: string) => (
    <div className="flex items-center justify-between py-2">
      <Label className="text-sm">{label}</Label>
      <Switch
        checked={datos[campo] as boolean}
        onCheckedChange={(v) => handleChange(campo, v)}
        disabled={!editando || soloLectura}
      />
    </div>
  );

  return (
    <Card className="overflow-hidden">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-2xl">{getBanderaPais(config.pais_codigo as PaisCodigo)}</span>
            <div>
              <CardTitle className="text-base">{getNombrePais(config.pais_codigo as PaisCodigo)}</CardTitle>
              <p className="text-xs text-muted-foreground">
                Moneda: <Badge variant="outline" className="text-xs">{config.moneda}</Badge>
              </p>
            </div>
          </div>

          {!soloLectura && (
            <div className="flex gap-2">
              {editando ? (
                <>
                  <Button size="sm" variant="outline" onClick={handleCancelar}>
                    <RotateCcw className="h-4 w-4 mr-1" />
                    Cancelar
                  </Button>
                  <Button size="sm" onClick={handleGuardar}>
                    <Save className="h-4 w-4 mr-1" />
                    Guardar
                  </Button>
                </>
              ) : (
                <Button size="sm" variant="outline" onClick={() => setEditando(true)}>
                  Editar
                </Button>
              )}
            </div>
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Precios */}
        <div className="grid grid-cols-2 gap-4">
          {renderInput('precio_mensual', 'Precio mensual', <DollarSign className="h-4 w-4 text-muted-foreground" />)}
          {renderInput('precio_anual', 'Precio anual', <DollarSign className="h-4 w-4 text-muted-foreground" />)}
        </div>

        <Separator />

        {/* Límites */}
        <div className="grid grid-cols-3 gap-4">
          {renderInput('max_medicos', 'Máx. médicos', <Users className="h-4 w-4 text-muted-foreground" />)}
          {renderInput('max_pacientes', 'Máx. pacientes', <UserCheck className="h-4 w-4 text-muted-foreground" />)}
          {renderInput('max_citas_mes', 'Citas/mes', <Calendar className="h-4 w-4 text-muted-foreground" />)}
        </div>

        <Separator />

        {/* Features */}
        <div className="space-y-1">
          {renderSwitch('incluye_recetas', 'Recetas electrónicas')}
          {renderSwitch('incluye_facturacion', 'Facturación')}
          {renderSwitch('incluye_farmacias', 'Farmacias')}
          {renderSwitch('incluye_reportes_avanzados', 'Reportes avanzados')}
          {renderSwitch('incluye_whatsapp', 'WhatsApp')}
          {renderSwitch('incluye_api', 'API Access')}
        </div>

        <Separator />

        {/* Soporte */}
        <div className="space-y-2">
          <Label className="flex items-center gap-2 text-sm">
            <Globe className="h-4 w-4 text-muted-foreground" />
            Tipo de soporte
          </Label>
          <select
            value={datos.soporte_tipo}
            onChange={(e) => handleChange('soporte_tipo', e.target.value as TipoSoporte)}
            disabled={!editando || soloLectura}
            className={`w-full rounded-md border border-input bg-background px-3 py-2 text-sm ${!editando ? 'bg-muted' : ''}`}
          >
            <option value="email">Email</option>
            <option value="chat">Chat en vivo</option>
            <option value="telefono">Teléfono</option>
            <option value="dedicado">Gerente de cuenta dedicado</option>
          </select>
        </div>
      </CardContent>
    </Card>
  );
}
