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
import { useAuth } from '@/hooks/useAuth';
import type { PlanAsignacion, EstadoPlan } from '@/types/planes';
import { formatearPrecio, getEstadoConfig, diasRestantes } from '@/lib/planes-utils';
import { ArrowLeft, Search, RefreshCw, Ban, RotateCcw, Eye, Download } from 'lucide-react';

export default function PlanesAsignacionesPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { asignaciones, planesConfig, loading, cancelarAsignacion, renovarAsignacion, recargar } = usePlanes();
  const [search, setSearch] = useState('');
  const [filtroEstado, setFiltroEstado] = useState<EstadoPlan | 'todos'>('todos');
  const [asignacionSel, setAsignacionSel] = useState<PlanAsignacion | null>(null);
  const [dialogoDetalle, setDialogoDetalle] = useState(false);
  const [dialogoCancelar, setDialogoCancelar] = useState(false);
  const [motivoCancelacion, setMotivoCancelacion] = useState('');

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

  const asignacionesFiltradas = asignaciones.filter(a => {
    const matchSearch = !search || a.medico?.nombre?.toLowerCase().includes(search.toLowerCase());
    const matchEstado = filtroEstado === 'todos' || a.estado === filtroEstado;
    return matchSearch && matchEstado;
  });

  const stats = {
    total: asignaciones.length,
    activos: asignaciones.filter(a => a.estado === 'activo').length,
    porVencer: asignaciones.filter(a => a.estado === 'activo' && a.fecha_fin && diasRestantes(a.fecha_fin) <= 7).length,
  };

  const handleRenovar = async (id: string) => {
    await renovarAsignacion(id);
  };

  const handleCancelarConfirmar = async () => {
    if (asignacionSel && motivoCancelacion) {
      await cancelarAsignacion(asignacionSel.id, motivoCancelacion);
      setDialogoCancelar(false);
      setMotivoCancelacion('');
      setAsignacionSel(null);
    }
  };

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Suscripciones</h1>
            <p className="text-sm text-muted-foreground">Gestiona suscripciones de médicos</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={recargar}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          <Button variant="outline"><Download className="h-4 w-4 mr-2" /> Exportar</Button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card><CardContent className="pt-4">
          <p className="text-sm text-muted-foreground">Total</p><p className="text-2xl font-bold">{stats.total}</p>
        </CardContent></Card>
        <Card><CardContent className="pt-4">
          <p className="text-sm text-muted-foreground">Activas</p><p className="text-2xl font-bold text-green-600">{stats.activos}</p>
        </CardContent></Card>
        <Card><CardContent className="pt-4">
          <p className="text-sm text-muted-foreground">Por vencer</p><p className="text-2xl font-bold text-red-600">{stats.porVencer}</p>
        </CardContent></Card>
      </div>

      <Card className="mb-6">
        <CardContent className="pt-4">
          <div className="flex flex-wrap gap-4 items-end">
            <div className="flex-1 min-w-[200px]">
              <Label className="text-xs mb-2 block">Buscar</Label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input placeholder="Médico..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
            </div>
            <div className="w-[160px]">
              <Label className="text-xs mb-2 block">Estado</Label>
              <Select value={filtroEstado} onValueChange={(v) => setFiltroEstado(v as any)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todos</SelectItem>
                  <SelectItem value="activo">Activo</SelectItem>
                  <SelectItem value="pendiente">Pendiente</SelectItem>
                  <SelectItem value="cancelado">Cancelado</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Médico</TableHead>
                  <TableHead>Plan</TableHead>
                  <TableHead>Precio</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead>Vencimiento</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {asignacionesFiltradas.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell>
                      <p className="font-medium">{a.medico?.nombre || 'N/A'}</p>
                      <p className="text-xs text-muted-foreground">{a.medico?.email}</p>
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline">{a.plan_configuracion?.plan_base?.nombre}</Badge>
                    </TableCell>
                    <TableCell>
                      <p className="font-medium">{formatearPrecio(a.precio_aplicado, a.moneda)}</p>
                    </TableCell>
                    <TableCell>
                      <Badge className={getEstadoConfig(a.estado).bg + ' ' + getEstadoConfig(a.estado).color}>
                        {getEstadoConfig(a.estado).label}
                      </Badge>
                      {a.fecha_fin && a.estado === 'activo' && diasRestantes(a.fecha_fin) <= 7 && (
                        <Badge variant="outline" className="ml-2 border-red-300 text-red-600 text-xs">
                          {diasRestantes(a.fecha_fin)} días
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell>
                      {a.fecha_fin ? new Date(a.fecha_fin).toLocaleDateString('es-GT') : 'Sin vencimiento'}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => { setAsignacionSel(a); setDialogoDetalle(true); }}>
                          <Eye className="h-4 w-4" />
                        </Button>
                        {a.estado === 'activo' && (
                          <Button variant="ghost" size="icon" onClick={() => handleRenovar(a.id)}>
                            <RotateCcw className="h-4 w-4" />
                          </Button>
                        )}
                        {a.estado === 'activo' && (
                          <Button variant="ghost" size="icon" className="text-red-500" onClick={() => { setAsignacionSel(a); setDialogoCancelar(true); }}>
                            <Ban className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
                {asignacionesFiltradas.length === 0 && (
                  <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">
                    No se encontraron suscripciones
                  </TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Dialog open={dialogoDetalle} onOpenChange={setDialogoDetalle}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Detalle de suscripción</DialogTitle></DialogHeader>
          {asignacionSel && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div><Label className="text-xs text-muted-foreground">Médico</Label>
                  <p className="font-medium">{asignacionSel.medico?.nombre}</p></div>
                <div><Label className="text-xs text-muted-foreground">Plan</Label>
                  <p className="font-medium">{asignacionSel.plan_configuracion?.plan_base?.nombre}</p></div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label className="text-xs text-muted-foreground">Precio</Label>
                  <p className="font-medium">{formatearPrecio(asignacionSel.precio_aplicado, asignacionSel.moneda)}</p></div>
                <div><Label className="text-xs text-muted-foreground">Ciclo</Label>
                  <p className="font-medium capitalize">{asignacionSel.tipo_ciclo}</p></div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><Label className="text-xs text-muted-foreground">Inicio</Label>
                  <p className="font-medium">{new Date(asignacionSel.fecha_inicio).toLocaleDateString('es-GT')}</p></div>
                <div><Label className="text-xs text-muted-foreground">Vencimiento</Label>
                  <p className="font-medium">{asignacionSel.fecha_fin ? new Date(asignacionSel.fecha_fin).toLocaleDateString('es-GT') : 'Sin vencimiento'}</p></div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={dialogoCancelar} onOpenChange={setDialogoCancelar}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-red-600 flex items-center gap-2">
              <Ban className="h-5 w-5" /> Cancelar suscripción
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <Label htmlFor="motivo">Motivo de cancelación *</Label>
            <Input id="motivo" placeholder="Ej: Solicitud del médico..." value={motivoCancelacion} onChange={(e) => setMotivoCancelacion(e.target.value)} />
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoCancelar(false)}>Cancelar</Button>
              <Button variant="destructive" onClick={handleCancelarConfirmar} disabled={!motivoCancelacion}>
                <Ban className="h-4 w-4 mr-2" /> Confirmar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}