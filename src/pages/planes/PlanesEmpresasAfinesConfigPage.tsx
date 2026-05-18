import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { usePlanes } from '@/hooks/usePlanes';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { formatearPrecio, getBanderaPais } from '@/lib/planes-utils';
import { ArrowLeft, Plus, Search, RefreshCw, Edit, Trash2, Handshake } from 'lucide-react';

export default function PlanesEmpresasAfinesConfigPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const { planesBase, planesConfig, paises, loading, crearPlanBase, crearPlanConfig, actualizarPlanConfig, eliminarPlanConfig, recargar } = usePlanes();
  const [search, setSearch] = useState('');
  const [dialogoCrear, setDialogoCrear] = useState(false);
  const [dialogoConfig, setDialogoConfig] = useState(false);
  const [planSeleccionado, setPlanSeleccionado] = useState<any>(null);
  const [nuevoPlan, setNuevoPlan] = useState({
    nombre: '',
    descripcion: '',
    precio_base: 0,
    moneda: 'USD',
    periodicidad: 'mensual',
  });
  const [nuevaConfig, setNuevaConfig] = useState({
    plan_base_id: '',
    pais_id: '',
    precio_local: 0,
    precio_anual: 0,
    comision_aplicada: 0,
    descuento_porcentaje: 0,
  });

  if (adminLoading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#4f46e5]" />
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h2 className="text-xl font-bold mb-2">Acceso restringido</h2>
            <p className="text-sm text-muted-foreground mb-4">Necesitas rol de administrador para ver esta página.</p>
            <Button onClick={() => navigate('/dashboard')}>Volver al dashboard</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const planesEmpresasAfines = planesBase.filter(p => p.tipo === 'empresas_afines');
  const configsEmpresasAfines = planesConfig.filter(p => p.plan_base?.tipo === 'empresas_afines');

  const planesFiltrados = planesEmpresasAfines.filter(p => 
    !search || p.nombre.toLowerCase().includes(search.toLowerCase())
  );

  const handleCrearPlan = async () => {
    await crearPlanBase({
      ...nuevoPlan,
      tipo: 'empresas_afines',
      activo: true,
    });
    setDialogoCrear(false);
    setNuevoPlan({ nombre: '', descripcion: '', precio_base: 0, moneda: 'USD', periodicidad: 'mensual' });
  };

  const handleCrearConfig = async () => {
    await crearPlanConfig({
      ...nuevaConfig,
      moneda_local: paises.find(p => p.id === nuevaConfig.pais_id)?.moneda || 'USD',
    });
    setDialogoConfig(false);
    setNuevaConfig({ plan_base_id: '', pais_id: '', precio_local: 0, precio_anual: 0, comision_aplicada: 0, descuento_porcentaje: 0 });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <RefreshCw className="h-8 w-8 animate-spin text-[#4f46e5]" />
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Configuración Planes Empresas Afines</h1>
            <p className="text-sm text-muted-foreground">Gestiona planes para empresas afines al sector salud</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={recargar}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          <Button onClick={() => setDialogoCrear(true)} className="bg-[#4f46e5] hover:bg-[#4f46e5]/90"><Plus className="h-4 w-4 mr-2" /> Nuevo Plan</Button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Planes Base</p>
            <p className="text-2xl font-bold">{planesEmpresasAfines.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Configuraciones</p>
            <p className="text-2xl font-bold">{configsEmpresasAfines.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Países</p>
            <p className="text-2xl font-bold">{paises.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Precio Base Máx</p>
            <p className="text-2xl font-bold">{planesEmpresasAfines.length > 0 ? Math.max(...planesEmpresasAfines.map(p => p.precio_base)) : 0} USD</p>
          </CardContent>
        </Card>
      </div>

      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-lg">Planes Base Empresas Afines</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-4 mb-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input placeholder="Buscar plan..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
            </div>
          </div>

          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nombre</TableHead>
                  <TableHead>Descripción</TableHead>
                  <TableHead>Precio Base</TableHead>
                  <TableHead>Moneda</TableHead>
                  <TableHead>Periodicidad</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {planesFiltrados.map((plan) => (
                  <TableRow key={plan.id}>
                    <TableCell className="font-medium">{plan.nombre}</TableCell>
                    <TableCell className="text-sm text-muted-foreground max-w-xs truncate">{plan.descripcion}</TableCell>
                    <TableCell>{formatearPrecio(plan.precio_base, plan.moneda || 'USD')}</TableCell>
                    <TableCell><Badge variant="outline">{plan.moneda}</Badge></TableCell>
                    <TableCell className="capitalize">{plan.periodicidad}</TableCell>
                    <TableCell>
                      <Badge className={plan.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-700'}>
                        {plan.activo ? 'Activo' : 'Inactivo'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <Button variant="ghost" size="icon" onClick={() => { setPlanSeleccionado(plan); setDialogoConfig(true); }}>
                        <Plus className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="icon">
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="icon" className="text-red-500" onClick={() => eliminarPlanConfig(plan.id)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {planesFiltrados.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                      No se encontraron planes empresas afines
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Configuraciones por País</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Plan</TableHead>
                  <TableHead>País</TableHead>
                  <TableHead>Precio Local</TableHead>
                  <TableHead>Precio Anual</TableHead>
                  <TableHead>Comisión</TableHead>
                  <TableHead>Descuento</TableHead>
                  <TableHead>Estado</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {configsEmpresasAfines.map((config) => (
                  <TableRow key={config.id}>
                    <TableCell className="font-medium">{config.plan_base?.nombre}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <span>{getBanderaPais(config.pais?.codigo as any)}</span>
                        {config.pais?.nombre}
                      </div>
                    </TableCell>
                    <TableCell>{formatearPrecio(config.precio_local, config.pais?.moneda || 'USD')}</TableCell>
                    <TableCell>{formatearPrecio(config.precio_anual || 0, config.pais?.moneda || 'USD')}</TableCell>
                    <TableCell>{config.comision_aplicada}%</TableCell>
                    <TableCell>{config.descuento_porcentaje}%</TableCell>
                    <TableCell>
                      <Badge className={config.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-700'}>
                        {config.activo ? 'Activo' : 'Inactivo'}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
                {configsEmpresasAfines.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                      No hay configuraciones de empresas afines
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Dialog open={dialogoCrear} onOpenChange={setDialogoCrear}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Handshake className="h-5 w-5 text-[#4f46e5]" />
              Nuevo Plan Empresas Afines
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="nombre">Nombre *</Label>
              <Input id="nombre" value={nuevoPlan.nombre} onChange={(e) => setNuevoPlan({...nuevoPlan, nombre: e.target.value})} placeholder="Ej: Empresas Afines Premium" />
            </div>
            <div>
              <Label htmlFor="descripcion">Descripción</Label>
              <Input id="descripcion" value={nuevoPlan.descripcion} onChange={(e) => setNuevoPlan({...nuevoPlan, descripcion: e.target.value})} placeholder="Descripción del plan..." />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="precio">Precio Base (USD)</Label>
                <Input id="precio" type="number" value={nuevoPlan.precio_base} onChange={(e) => setNuevoPlan({...nuevoPlan, precio_base: parseFloat(e.target.value)})} />
              </div>
              <div>
                <Label htmlFor="periodicidad">Periodicidad</Label>
                <Select value={nuevoPlan.periodicidad} onValueChange={(v) => setNuevoPlan({...nuevoPlan, periodicidad: v})}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="mensual">Mensual</SelectItem>
                    <SelectItem value="anual">Anual</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoCrear(false)}>Cancelar</Button>
              <Button onClick={handleCrearPlan} disabled={!nuevoPlan.nombre} className="bg-[#4f46e5] hover:bg-[#4f46e5]/90">
                <Plus className="h-4 w-4 mr-2" /> Crear Plan
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={dialogoConfig} onOpenChange={setDialogoConfig}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Nueva Configuración por País</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Plan Base</Label>
              <Select value={nuevaConfig.plan_base_id} onValueChange={(v) => setNuevaConfig({...nuevaConfig, plan_base_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar plan" /></SelectTrigger>
                <SelectContent>
                  {planesEmpresasAfines.map(p => (
                    <SelectItem key={p.id} value={p.id}>{p.nombre}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>País</Label>
              <Select value={nuevaConfig.pais_id} onValueChange={(v) => setNuevaConfig({...nuevaConfig, pais_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar país" /></SelectTrigger>
                <SelectContent>
                  {paises.map(p => (
                    <SelectItem key={p.id} value={p.id}>{getBanderaPais(p.codigo as any)} {p.nombre}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Precio Local Mensual</Label>
                <Input type="number" value={nuevaConfig.precio_local} onChange={(e) => setNuevaConfig({...nuevaConfig, precio_local: parseFloat(e.target.value)})} />
              </div>
              <div>
                <Label>Precio Anual</Label>
                <Input type="number" value={nuevaConfig.precio_anual} onChange={(e) => setNuevaConfig({...nuevaConfig, precio_anual: parseFloat(e.target.value)})} />
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoConfig(false)}>Cancelar</Button>
              <Button onClick={handleCrearConfig} disabled={!nuevaConfig.plan_base_id || !nuevaConfig.pais_id} className="bg-[#4f46e5] hover:bg-[#4f46e5]/90">
                <Plus className="h-4 w-4 mr-2" /> Crear Configuración
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
