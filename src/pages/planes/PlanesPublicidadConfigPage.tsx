import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { useState, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { usePlanes } from '@/hooks/usePlanes';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { formatearPrecio, getBanderaPais } from '@/lib/planes-utils';
import { ArrowLeft, Plus, Search, RefreshCw, Edit, Trash2, X, AlertTriangle, Megaphone, CreditCard } from 'lucide-react';
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import CampanasPublicitariasContent from '@/webapp/components/CampanasPublicitariasContent';

// ════════════════════════════════════════════════════
// COMPONENTE REUTILIZABLE: Ventana Arrastrable
// ════════════════════════════════════════════════════
function DraggableWindow({ 
  isOpen, 
  onClose, 
  title, 
  children,
  initialPosition = { x: 100, y: 100 }
}: { 
  isOpen: boolean; 
  onClose: () => void; 
  title: string; 
  children: React.ReactNode;
  initialPosition?: { x: number; y: number };
}) {
  const [position, setPosition] = useState(initialPosition);
  const [isDragging, setIsDragging] = useState(false);
  const dragOffset = useRef({ x: 0, y: 0 });

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('.drag-handle')) {
      setIsDragging(true);
      dragOffset.current = {
        x: e.clientX - position.x,
        y: e.clientY - position.y
      };
    }
  }, [position]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (isDragging) {
      setPosition({
        x: e.clientX - dragOffset.current.x,
        y: e.clientY - dragOffset.current.y
      });
    }
  }, [isDragging]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
  }, []);

  if (!isOpen) return null;

  return (
    <>
      <div className="fixed inset-0 bg-black/50 z-50" onClick={onClose} />
      <div
        className="fixed z-[60] w-[500px] bg-white rounded-lg border shadow-lg"
        style={{ left: position.x, top: position.y }}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
      >
        <div 
          className="drag-handle flex items-center justify-between p-4 border-b cursor-move bg-amber-50 rounded-t-lg select-none"
          onMouseDown={handleMouseDown}
        >
          <h2 className="text-lg font-semibold">{title}</h2>
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
        <div className="p-4">
          {children}
        </div>
      </div>
    </>
  );
}

// Monedas disponibles
const MONEDAS = [
  { codigo: 'USD', nombre: 'Dólar Estadounidense' },
  { codigo: 'GTQ', nombre: 'Quetzal Guatemalteco' },
  { codigo: 'HNL', nombre: 'Lempira Hondureño' },
  { codigo: 'NIO', nombre: 'Córdoba Nicaragüense' },
  { codigo: 'CRC', nombre: 'Colón Costarricense' },
  { codigo: 'PAB', nombre: 'Balboa Panameño' },
  { codigo: 'DOP', nombre: 'Peso Dominicano' },
  { codigo: 'CUP', nombre: 'Peso Cubano' },
  { codigo: 'MXN', nombre: 'Peso Mexicano' },
  { codigo: 'EUR', nombre: 'Euro' },
];

export default function PlanesPublicidadConfigPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const { 
    planesBase, 
    planesConfig, 
    paises, 
    loading, 
    crearPlanBase, 
    crearPlanConfig, 
    actualizarPlanBase, 
    eliminarPlanBase, 
    eliminarPlanConfig,
    recargar 
  } = usePlanes();

  const [search, setSearch] = useState('');

  // Modales de Plan Base
  const [dialogoCrear, setDialogoCrear] = useState(false);
  const [dialogoEditar, setDialogoEditar] = useState<any>(null);
  const [dialogoEliminarPlan, setDialogoEliminarPlan] = useState<string | null>(null);

  // Modal de Configuración
  const [dialogoConfig, setDialogoConfig] = useState(false);
  const [planSeleccionado, setPlanSeleccionado] = useState<any>(null);

  // Modal eliminar configuración
  const [dialogoEliminarConfig, setDialogoEliminarConfig] = useState<string | null>(null);

  // Estados formularios
  const [nuevoPlan, setNuevoPlan] = useState({
    nombre: '',
    descripcion: '',
    precio_base: '',
    moneda: 'USD',
    periodicidad: 'mensual',
    limite_medicos: '',
    limite_pacientes: '',
    caracteristicas: '',
  });

  const [vista, setVista] = useState<'planes' | 'campanas'>('planes');

  const [nuevaConfig, setNuevaConfig] = useState({
    plan_base_id: '',
    pais_id: '',
    precio_local: '',
    precio_anual: '',
    comision_aplicada: '',
    descuento_porcentaje: '',
  });

  if (adminLoading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-amber-600" />
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h2 className="text-xl font-bold mb-2">Acceso restringido</h2>
            <p className="text-sm text-muted-foreground mb-4">Necesitas rol de administrador para ver esta pagina.</p>
            <Button onClick={() => navigate('/dashboard')}>Volver al dashboard</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const planesPublicidad = planesBase.filter(p => p.tipo === 'publicidad');
  const configsPublicidad = planesConfig.filter(p => p.plan_base?.tipo === 'publicidad');

  const planesFiltrados = planesPublicidad.filter(p => 
    !search || p.nombre.toLowerCase().includes(search.toLowerCase())
  );

  // ════════════════════════════════════════════════════
  // HANDLERS CREAR PLAN
  // ════════════════════════════════════════════════════
  const handleCrearPlan = async () => {
    if (!nuevoPlan.nombre.trim()) {
      alert('El nombre del plan es obligatorio');
      return;
    }

    await crearPlanBase({
      nombre: nuevoPlan.nombre.trim(),
      descripcion: nuevoPlan.descripcion.trim(),
      tipo: 'publicidad',
      precio_base: parseFloat(nuevoPlan.precio_base) || 0,
      moneda: nuevoPlan.moneda,
      periodicidad: nuevoPlan.periodicidad,
      limite_medicos: nuevoPlan.limite_medicos ? parseInt(nuevoPlan.limite_medicos) : undefined,
      limite_pacientes: nuevoPlan.limite_pacientes ? parseInt(nuevoPlan.limite_pacientes) : undefined,
      caracteristicas: nuevoPlan.caracteristicas.split(',').map(c => c.trim()).filter(Boolean),
      activo: true,
    });
    setDialogoCrear(false);
    setNuevoPlan({ nombre: '', descripcion: '', precio_base: '', moneda: 'USD', periodicidad: 'mensual', limite_medicos: '', limite_pacientes: '', caracteristicas: '' });
    recargar();
  };

  // ════════════════════════════════════════════════════
  // HANDLERS EDITAR PLAN
  // ════════════════════════════════════════════════════
  const handleEditarPlan = async () => {
    if (!dialogoEditar) return;

    let caracteristicasArray: string[] = [];
    if (typeof dialogoEditar.caracteristicas === 'string') {
      caracteristicasArray = dialogoEditar.caracteristicas.split(',').map((c: string) => c.trim()).filter(Boolean);
    } else if (Array.isArray(dialogoEditar.caracteristicas)) {
      caracteristicasArray = dialogoEditar.caracteristicas;
    }

    await actualizarPlanBase(dialogoEditar.id, {
      nombre: dialogoEditar.nombre,
      descripcion: dialogoEditar.descripcion,
      precio_base: parseFloat(dialogoEditar.precio_base) || 0,
      moneda: dialogoEditar.moneda,
      periodicidad: dialogoEditar.periodicidad,
      limite_medicos: dialogoEditar.limite_medicos ? parseInt(dialogoEditar.limite_medicos) : undefined,
      limite_pacientes: dialogoEditar.limite_pacientes ? parseInt(dialogoEditar.limite_pacientes) : undefined,
      caracteristicas: caracteristicasArray,
      activo: dialogoEditar.activo,
    });
    setDialogoEditar(null);
    recargar();
  };

  // ════════════════════════════════════════════════════
  // HANDLERS ELIMINAR PLAN
  // ════════════════════════════════════════════════════
  const handleEliminarPlan = async () => {
    if (!dialogoEliminarPlan) return;
    await eliminarPlanBase(dialogoEliminarPlan);
    setDialogoEliminarPlan(null);
    recargar();
  };

  // ════════════════════════════════════════════════════
  // HANDLERS CREAR CONFIGURACIÓN
  // ════════════════════════════════════════════════════
  const handleCrearConfig = async () => {
    if (!nuevaConfig.plan_base_id || !nuevaConfig.pais_id) {
      alert('Debes seleccionar un plan y un país');
      return;
    }

    await crearPlanConfig({
      plan_base_id: nuevaConfig.plan_base_id,
      pais_id: nuevaConfig.pais_id,
      precio_local: parseFloat(nuevaConfig.precio_local) || 0,
      precio_anual: nuevaConfig.precio_anual ? parseFloat(nuevaConfig.precio_anual) : undefined,
      comision_aplicada: parseFloat(nuevaConfig.comision_aplicada) || 0,
      descuento_porcentaje: parseFloat(nuevaConfig.descuento_porcentaje) || 0,
    });
    setDialogoConfig(false);
    setNuevaConfig({ plan_base_id: '', pais_id: '', precio_local: '', precio_anual: '', comision_aplicada: '', descuento_porcentaje: '' });
    recargar();
  };

  // ════════════════════════════════════════════════════
  // HANDLERS ELIMINAR CONFIGURACIÓN
  // ════════════════════════════════════════════════════
  const handleEliminarConfig = async () => {
    if (!dialogoEliminarConfig) return;
    await eliminarPlanConfig(dialogoEliminarConfig);
    setDialogoEliminarConfig(null);
    recargar();
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <RefreshCw className="h-8 w-8 animate-spin text-amber-600" />
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
            <h1 className="text-2xl font-bold">Configuracion Planes Publicidad</h1>
            <p className="text-sm text-muted-foreground">Gestiona planes para publicidad médica y marketing en salud</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={recargar}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          {vista === 'planes' && (
            <Button onClick={() => setDialogoCrear(true)} className="bg-amber-600 hover:bg-amber-700"><Plus className="h-4 w-4 mr-2" /> Nuevo Plan</Button>
          )}
        </div>
      </div>

      {/* Tabs de navegación */}
      <Tabs value={vista} onValueChange={(v) => setVista(v as 'planes' | 'campanas')} className="w-full mb-6">
        <TabsList className="grid w-full max-w-md grid-cols-2">
          <TabsTrigger value="planes" className="flex items-center gap-2">
            <CreditCard className="h-4 w-4" /> Planes de Suscripción
          </TabsTrigger>
          <TabsTrigger value="campanas" className="flex items-center gap-2">
            <Megaphone className="h-4 w-4" /> Campañas Publicitarias
          </TabsTrigger>
        </TabsList>
      </Tabs>

      {vista === 'campanas' ? (
        <CampanasPublicitariasContent />
      ) : (
        <>
      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Planes Base</p><p className="text-2xl font-bold">{planesPublicidad.length}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Configuraciones</p><p className="text-2xl font-bold">{configsPublicidad.length}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Paises</p><p className="text-2xl font-bold">{paises.length}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Precio Base Max</p><p className="text-2xl font-bold">{planesPublicidad.length > 0 ? Math.max(...planesPublicidad.map(p => p.precio_base)) : 0} USD</p></CardContent></Card>
      </div>

      {/* Tabla de Planes Base */}
      <Card className="mb-6">
        <CardHeader><CardTitle className="text-lg">Planes Base Publicidad</CardTitle></CardHeader>
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
                  <TableHead>Descripcion</TableHead>
                  <TableHead>Precio Base</TableHead>
                  <TableHead>Moneda</TableHead>
                  <TableHead>Periodicidad</TableHead>
                  <TableHead>Límite Médicos</TableHead>
                  <TableHead>Límite Pacientes</TableHead>
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
                    <TableCell>{plan.limite_medicos ?? 'Ilimitado'}</TableCell>
                    <TableCell>{plan.limite_pacientes ?? 'Ilimitado'}</TableCell>
                    <TableCell>
                      <Badge className={plan.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-700'}>
                        {plan.activo ? 'Activo' : 'Inactivo'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <Button variant="ghost" size="icon" onClick={() => { setPlanSeleccionado(plan); setNuevaConfig({...nuevaConfig, plan_base_id: plan.id}); setDialogoConfig(true); }} title="Agregar configuracion por pais">
                        <Plus className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="icon" onClick={() => setDialogoEditar(plan)} title="Editar plan">
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="icon" className="text-red-500" onClick={() => setDialogoEliminarPlan(plan.id)} title="Eliminar plan">
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {planesFiltrados.length === 0 && (
                  <TableRow><TableCell colSpan={9} className="text-center py-8 text-muted-foreground">No se encontraron planes publicidad</TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Tabla de Configuraciones */}
      <Card>
        <CardHeader><CardTitle className="text-lg">Configuraciones por Pais</CardTitle></CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Plan</TableHead>
                  <TableHead>Pais</TableHead>
                  <TableHead>Precio Local</TableHead>
                  <TableHead>Precio Anual</TableHead>
                  <TableHead>Comision</TableHead>
                  <TableHead>Descuento</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {configsPublicidad.map((config) => (
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
                    <TableCell className="text-right">
                      <Button variant="ghost" size="icon" className="text-red-500" onClick={() => setDialogoEliminarConfig(config.id)} title="Eliminar configuracion">
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {configsPublicidad.length === 0 && (
                  <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">No hay configuraciones de publicidad</TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* ════════════════════════════════════════════════════
          VENTANA ARRASTRABLE: Nuevo Plan Publicidad
          ════════════════════════════════════════════════════ */}
      <DraggableWindow
        isOpen={dialogoCrear}
        onClose={() => setDialogoCrear(false)}
        title="Nuevo Plan Publicidad"
        initialPosition={{ x: typeof window !== 'undefined' ? window.innerWidth / 2 - 250 : 100, y: 100 }}
      >
        <div className="space-y-4">
          <div>
            <Label htmlFor="nombre">Nombre *</Label>
            <Input id="nombre" value={nuevoPlan.nombre} onChange={(e) => setNuevoPlan({...nuevoPlan, nombre: e.target.value})} placeholder="Ej: Publicidad Premium" />
          </div>
          <div>
            <Label htmlFor="descripcion">Descripcion</Label>
            <Input id="descripcion" value={nuevoPlan.descripcion} onChange={(e) => setNuevoPlan({...nuevoPlan, descripcion: e.target.value})} placeholder="Descripcion del plan..." />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="precio">Precio Base (USD)</Label>
              <Input id="precio" type="number" value={nuevoPlan.precio_base} onChange={(e) => setNuevoPlan({...nuevoPlan, precio_base: e.target.value})} placeholder="0" />
            </div>
            <div>
              <Label htmlFor="moneda">Moneda</Label>
              <Select value={nuevoPlan.moneda} onValueChange={(v) => setNuevoPlan({...nuevoPlan, moneda: v})}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent position="popper" className="z-[70]">
                  {MONEDAS.map(m => (
                    <SelectItem key={m.codigo} value={m.codigo}>{m.codigo} - {m.nombre}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="periodicidad">Periodicidad</Label>
              <Select value={nuevoPlan.periodicidad} onValueChange={(v) => setNuevoPlan({...nuevoPlan, periodicidad: v})}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent position="popper" className="z-[70]">
                  <SelectItem value="mensual">Mensual</SelectItem>
                  <SelectItem value="anual">Anual</SelectItem>
                  <SelectItem value="semestral">Semestral</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="limite_medicos">Límite Médicos (opcional)</Label>
              <Input id="limite_medicos" type="number" value={nuevoPlan.limite_medicos} onChange={(e) => setNuevoPlan({...nuevoPlan, limite_medicos: e.target.value})} placeholder="Ilimitado" />
            </div>
            <div>
              <Label htmlFor="limite_pacientes">Límite Pacientes (opcional)</Label>
              <Input id="limite_pacientes" type="number" value={nuevoPlan.limite_pacientes} onChange={(e) => setNuevoPlan({...nuevoPlan, limite_pacientes: e.target.value})} placeholder="Ilimitado" />
            </div>
          </div>
          <div>
            <Label htmlFor="caracteristicas">Características (separadas por coma)</Label>
            <Input id="caracteristicas" value={nuevoPlan.caracteristicas} onChange={(e) => setNuevoPlan({...nuevoPlan, caracteristicas: e.target.value})} placeholder="Ej: Recetas ilimitadas, Soporte 24/7, API access" />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setDialogoCrear(false)}>Cancelar</Button>
            <Button onClick={handleCrearPlan} disabled={!nuevoPlan.nombre} className="bg-amber-600 hover:bg-amber-700">
              <Plus className="h-4 w-4 mr-2" /> Crear Plan
            </Button>
          </div>
        </div>
      </DraggableWindow>

      {/* ════════════════════════════════════════════════════
          VENTANA ARRASTRABLE: Editar Plan Publicidad
          ════════════════════════════════════════════════════ */}
      <DraggableWindow
        isOpen={!!dialogoEditar}
        onClose={() => setDialogoEditar(null)}
        title="Editar Plan Publicidad"
        initialPosition={{ x: typeof window !== 'undefined' ? window.innerWidth / 2 - 250 : 100, y: 100 }}
      >
        {dialogoEditar && (
          <div className="space-y-4">
            <div>
              <Label>Nombre</Label>
              <Input value={dialogoEditar.nombre} onChange={(e) => setDialogoEditar({...dialogoEditar, nombre: e.target.value})} />
            </div>
            <div>
              <Label>Descripcion</Label>
              <Input value={dialogoEditar.descripcion || ''} onChange={(e) => setDialogoEditar({...dialogoEditar, descripcion: e.target.value})} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Precio Base (USD)</Label>
                <Input type="number" value={dialogoEditar.precio_base} onChange={(e) => setDialogoEditar({...dialogoEditar, precio_base: e.target.value})} />
              </div>
              <div>
                <Label>Moneda</Label>
                <Select value={dialogoEditar.moneda} onValueChange={(v) => setDialogoEditar({...dialogoEditar, moneda: v})}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent position="popper" className="z-[70]">
                    {MONEDAS.map(m => (
                      <SelectItem key={m.codigo} value={m.codigo}>{m.codigo} - {m.nombre}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Periodicidad</Label>
                <Select value={dialogoEditar.periodicidad} onValueChange={(v) => setDialogoEditar({...dialogoEditar, periodicidad: v})}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent position="popper" className="z-[70]">
                    <SelectItem value="mensual">Mensual</SelectItem>
                    <SelectItem value="anual">Anual</SelectItem>
                    <SelectItem value="semestral">Semestral</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div></div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label>Límite Médicos</Label>
                <Input type="number" value={dialogoEditar.limite_medicos || ''} onChange={(e) => setDialogoEditar({...dialogoEditar, limite_medicos: e.target.value})} placeholder="Ilimitado" />
              </div>
              <div>
                <Label>Límite Pacientes</Label>
                <Input type="number" value={dialogoEditar.limite_pacientes || ''} onChange={(e) => setDialogoEditar({...dialogoEditar, limite_pacientes: e.target.value})} placeholder="Ilimitado" />
              </div>
            </div>
            <div>
              <Label>Características (separadas por coma)</Label>
              <Input value={Array.isArray(dialogoEditar.caracteristicas) ? dialogoEditar.caracteristicas.join(', ') : dialogoEditar.caracteristicas || ''} onChange={(e) => setDialogoEditar({...dialogoEditar, caracteristicas: e.target.value})} placeholder="Ej: Recetas ilimitadas, Soporte 24/7" />
            </div>
            <div className="flex items-center gap-2">
              <input type="checkbox" checked={dialogoEditar.activo} onChange={(e) => setDialogoEditar({...dialogoEditar, activo: e.target.checked})} className="h-4 w-4" />
              <Label>Plan activo</Label>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setDialogoEditar(null)}>Cancelar</Button>
              <Button onClick={handleEditarPlan} className="bg-amber-600 hover:bg-amber-700">
                <Edit className="h-4 w-4 mr-2" /> Guardar Cambios
              </Button>
            </div>
          </div>
        )}
      </DraggableWindow>

      {/* ════════════════════════════════════════════════════
          MODAL ELIMINAR PLAN (AlertDialog estándar)
          ════════════════════════════════════════════════════ */}
      <AlertDialog open={!!dialogoEliminarPlan} onOpenChange={() => setDialogoEliminarPlan(null)}>
        <AlertDialogContent className="z-[70]">
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2 text-red-600">
              <AlertTriangle className="h-5 w-5" />
              ¿Eliminar plan base?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Esta acción eliminará permanentemente el plan y todas sus configuraciones por país. No se puede deshacer.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDialogoEliminarPlan(null)}>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleEliminarPlan} className="bg-red-600 hover:bg-red-700 text-white">
              <Trash2 className="h-4 w-4 mr-2" />
              Eliminar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* ════════════════════════════════════════════════════
          VENTANA ARRASTRABLE: Nueva Configuracion por Pais
          ════════════════════════════════════════════════════ */}
      <DraggableWindow
        isOpen={dialogoConfig}
        onClose={() => setDialogoConfig(false)}
        title="Nueva Configuracion por Pais"
        initialPosition={{ x: typeof window !== 'undefined' ? window.innerWidth / 2 - 250 : 100, y: 150 }}
      >
        <div className="space-y-4">
          <div>
            <Label>Plan Base</Label>
            <Select value={nuevaConfig.plan_base_id} onValueChange={(v) => setNuevaConfig({...nuevaConfig, plan_base_id: v})}>
              <SelectTrigger className="w-full"><SelectValue placeholder="Seleccionar plan" /></SelectTrigger>
              <SelectContent position="popper" className="z-[70]">
                {planesPublicidad.map(p => (
                  <SelectItem key={p.id} value={p.id}>{p.nombre}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>Pais</Label>
            <Select value={nuevaConfig.pais_id} onValueChange={(v) => setNuevaConfig({...nuevaConfig, pais_id: v})}>
              <SelectTrigger className="w-full"><SelectValue placeholder="Seleccionar pais" /></SelectTrigger>
              <SelectContent position="popper" className="z-[70]">
                {paises.map(p => (
                  <SelectItem key={p.id} value={p.id}>{getBanderaPais(p.codigo as any)} {p.nombre}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>Precio Local Mensual</Label>
              <Input type="number" value={nuevaConfig.precio_local} onChange={(e) => setNuevaConfig({...nuevaConfig, precio_local: e.target.value})} placeholder="0" />
            </div>
            <div>
              <Label>Precio Anual</Label>
              <Input type="number" value={nuevaConfig.precio_anual} onChange={(e) => setNuevaConfig({...nuevaConfig, precio_anual: e.target.value})} placeholder="0" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>Comisión (%)</Label>
              <Input type="number" value={nuevaConfig.comision_aplicada} onChange={(e) => setNuevaConfig({...nuevaConfig, comision_aplicada: e.target.value})} placeholder="0" />
            </div>
            <div>
              <Label>Descuento (%)</Label>
              <Input type="number" value={nuevaConfig.descuento_porcentaje} onChange={(e) => setNuevaConfig({...nuevaConfig, descuento_porcentaje: e.target.value})} placeholder="0" />
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setDialogoConfig(false)}>Cancelar</Button>
            <Button onClick={handleCrearConfig} disabled={!nuevaConfig.plan_base_id || !nuevaConfig.pais_id} className="bg-amber-600 hover:bg-amber-700">
              <Plus className="h-4 w-4 mr-2" /> Crear Configuracion
            </Button>
          </div>
        </div>
      </DraggableWindow>

      {/* ════════════════════════════════════════════════════
          MODAL ELIMINAR CONFIGURACIÓN (AlertDialog estándar)
          ════════════════════════════════════════════════════ */}
      <AlertDialog open={!!dialogoEliminarConfig} onOpenChange={() => setDialogoEliminarConfig(null)}>
        <AlertDialogContent className="z-[70]">
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2 text-red-600">
              <AlertTriangle className="h-5 w-5" />
              ¿Eliminar configuración?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Esta acción eliminará la configuración de precios para este país. No se puede deshacer.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDialogoEliminarConfig(null)}>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleEliminarConfig} className="bg-red-600 hover:bg-red-700 text-white">
              <Trash2 className="h-4 w-4 mr-2" />
              Eliminar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
        </>
      )}
    </div>
  );
}
