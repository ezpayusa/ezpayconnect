import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { usePlanes } from '@/hooks/usePlanes';
import { useAuth } from '@/hooks/useAuth';
import { ArrowLeft, Plus, Save, RotateCcw, Globe, DollarSign, Percent } from 'lucide-react';

export default function PlanesConfigPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { planesBase, planesConfig, paises, loading, actualizarPlanConfig, recargar } = usePlanes();
  const [paisActivo, setPaisActivo] = useState<string>('');
  const [editando, setEditando] = useState<Record<string, boolean>>({});
  const [datos, setDatos] = useState<Record<string, any>>({});

  if (user?.rol !== 'super_admin' && user?.rol !== 'admin') {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h2 className="text-xl font-bold mb-2">Acceso restringido</h2>
            <Button onClick={() => navigate('/dashboard')}>Volver al dashboard</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const planesMedicos = planesBase.filter(p => p.tipo === 'medico');
  const paisesConConfig = paises.filter(p => planesConfig.some(c => c.pais_id === p.id && planesMedicos.some(b => b.id === c.plan_base_id)));

  if (!paisActivo && paisesConConfig.length > 0) setPaisActivo(paisesConConfig[0].id);

  const configsPorPais = (paisId: string) => 
    planesConfig.filter(p => p.pais_id === paisId && planesMedicos.some(b => b.id === p.plan_base_id));

  const handleGuardar = async (configId: string) => {
    const d = datos[configId];
    if (!d) return;
    await actualizarPlanConfig(configId, {
      precio_local: parseFloat(d.precio_local),
      comision_aplicada: parseFloat(d.comision_aplicada),
      descuento_porcentaje: parseFloat(d.descuento_porcentaje),
    });
    setEditando(prev => ({ ...prev, [configId]: false }));
  };

  const handleChange = (configId: string, campo: string, valor: string) => {
    setDatos(prev => ({
      ...prev,
      [configId]: { ...prev[configId], [campo]: valor }
    }));
  };

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Configuración de Planes Médico</h1>
            <p className="text-sm text-muted-foreground">Gestiona precios, comisiones y descuentos por país</p>
          </div>
        </div>
        <Button variant="outline" onClick={recargar}>Recargar</Button>
      </div>

      <Tabs value={paisActivo} onValueChange={setPaisActivo}>
        <TabsList className="mb-6 bg-muted">
          {paisesConConfig.map(pais => (
            <TabsTrigger key={pais.id} value={pais.id} className="flex items-center gap-2">
              <Globe className="h-4 w-4" />
              {pais.nombre}
              <Badge variant="secondary" className="ml-1">{pais.moneda}</Badge>
            </TabsTrigger>
          ))}
        </TabsList>

        {paisesConConfig.map(pais => (
          <TabsContent key={pais.id} value={pais.id}>
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              {configsPorPais(pais.id).map(config => {
                const base = config.plan_base;
                if (!base) return null;
                const isEdit = editando[config.id];
                const d = datos[config.id] || {
                  precio_local: config.precio_local,
                  comision_aplicada: config.comision_aplicada,
                  descuento_porcentaje: config.descuento_porcentaje,
                };

                return (
                  <Card key={config.id}>
                    <CardHeader>
                      <div className="flex items-center justify-between">
                        <CardTitle className="text-base">{base.nombre}</CardTitle>
                        <Badge variant="outline">{base.moneda}</Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">{base.descripcion}</p>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="space-y-2">
                        <Label className="flex items-center gap-2 text-sm">
                          <DollarSign className="h-4 w-4 text-muted-foreground" />
                          Precio local
                        </Label>
                        <Input
                          type="number"
                          value={d.precio_local}
                          onChange={(e) => handleChange(config.id, 'precio_local', e.target.value)}
                          disabled={!isEdit}
                          className={!isEdit ? 'bg-muted' : ''}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label className="flex items-center gap-2 text-sm">
                          <Percent className="h-4 w-4 text-muted-foreground" />
                          Comisión aplicada (%)
                        </Label>
                        <Input
                          type="number"
                          value={d.comision_aplicada}
                          onChange={(e) => handleChange(config.id, 'comision_aplicada', e.target.value)}
                          disabled={!isEdit}
                          className={!isEdit ? 'bg-muted' : ''}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label className="flex items-center gap-2 text-sm">
                          <Percent className="h-4 w-4 text-muted-foreground" />
                          Descuento (%)
                        </Label>
                        <Input
                          type="number"
                          value={d.descuento_porcentaje}
                          onChange={(e) => handleChange(config.id, 'descuento_porcentaje', e.target.value)}
                          disabled={!isEdit}
                          className={!isEdit ? 'bg-muted' : ''}
                        />
                      </div>
                      <div className="flex gap-2">
                        {isEdit ? (
                          <>
                            <Button size="sm" variant="outline" onClick={() => setEditando(prev => ({ ...prev, [config.id]: false }))}>
                              <RotateCcw className="h-4 w-4 mr-1" /> Cancelar
                            </Button>
                            <Button size="sm" onClick={() => handleGuardar(config.id)}>
                              <Save className="h-4 w-4 mr-1" /> Guardar
                            </Button>
                          </>
                        ) : (
                          <Button size="sm" variant="outline" onClick={() => {
                            setDatos(prev => ({ ...prev, [config.id]: {
                              precio_local: config.precio_local,
                              comision_aplicada: config.comision_aplicada,
                              descuento_porcentaje: config.descuento_porcentaje,
                            }}));
                            setEditando(prev => ({ ...prev, [config.id]: true }));
                          }}>
                            Editar
                          </Button>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}