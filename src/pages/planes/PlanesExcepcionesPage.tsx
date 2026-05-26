import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { usePlanes } from '@/hooks/usePlanes';
import type { PlanExcepcion } from '@/types/planes';
import { formatearPrecio } from '@/lib/planes-utils';
import { ArrowLeft, Plus, Tag, Percent, DollarSign, Ban, Search } from 'lucide-react';

export default function PlanesExcepcionesPage() {
  const navigate = useNavigate();
  const { excepciones, planesConfig, loading, crearExcepcion, desactivarExcepcion, recargar } = usePlanes();
  const [search, setSearch] = useState('');
  const [filtroActivo, setFiltroActivo] = useState<'todos' | 'activo' | 'inactivo'>('activo');
  const [dialogoCrear, setDialogoCrear] = useState(false);
  const [nuevaExc, setNuevaExc] = useState({
    plan_config_id: '', entidad_id: '', tipo_entidad: 'medico',
    precio_especial: 0, comision_especial: 0,
    motivo: '', fecha_inicio: new Date().toISOString().split('T')[0], fecha_fin: ''
  });

  // Nota: La validación de admin se maneja en AdminRoute (App.tsx)
  // No es necesario duplicarla aquí

  const excepcionesFiltradas = excepciones.filter(e => {
    const matchSearch = !search || e.motivo?.toLowerCase().includes(search.toLowerCase());
    const matchActivo = filtroActivo === 'todos' || (filtroActivo === 'activo' ? e.activo : !e.activo);
    return matchSearch && matchActivo;
  });

  const stats = {
    total: excepciones.length,
    activas: excepciones.filter(e => e.activo).length,
    personales: excepciones.filter(e => e.entidad_id !== null).length,
    globales: excepciones.filter(e => e.entidad_id === null).length,
  };

  const handleCrear = async () => {
    await crearExcepcion({
      plan_config_id: nuevaExc.plan_config_id,
      entidad_id: nuevaExc.entidad_id || null,
      tipo_entidad: nuevaExc.entidad_id ? nuevaExc.tipo_entidad : null,
      precio_especial: nuevaExc.precio_especial,
      comision_especial: nuevaExc.comision_especial,
      motivo: nuevaExc.motivo,
      fecha_inicio: nuevaExc.fecha_inicio,
      fecha_fin: nuevaExc.fecha_fin || undefined,
    });
    setDialogoCrear(false);
    setNuevaExc({ plan_config_id: '', entidad_id: '', tipo_entidad: 'medico', precio_especial: 0, comision_especial: 0, motivo: '', fecha_inicio: new Date().toISOString().split('T')[0], fecha_fin: '' });
  };

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Excepciones y Promociones</h1>
            <p className="text-sm text-muted-foreground">Descuentos personalizados y promociones globales</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={recargar}>Recargar</Button>
          <Button className="bg-[#1E5C8E]" onClick={() => setDialogoCrear(true)}>
            <Plus className="h-4 w-4 mr-2" /> Nueva excepción
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Total</p><p className="text-2xl font-bold">{stats.total}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Activas</p><p className="text-2xl font-bold text-green-600">{stats.activas}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Personales</p><p className="text-2xl font-bold text-blue-600">{stats.personales}</p></CardContent></Card>
        <Card><CardContent className="pt-4"><p className="text-sm text-muted-foreground">Globales</p><p className="text-2xl font-bold text-purple-600">{stats.globales}</p></CardContent></Card>
      </div>

      <Card className="mb-6">
        <CardContent className="pt-4">
          <div className="flex flex-wrap gap-4 items-end">
            <div className="flex-1 min-w-[200px]">
              <Label className="text-xs mb-2 block">Buscar</Label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input placeholder="Motivo..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
            </div>
            <div className="w-[160px]">
              <Label className="text-xs mb-2 block">Estado</Label>
              <Select value={filtroActivo} onValueChange={(v) => setFiltroActivo(v as any)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todos</SelectItem>
                  <SelectItem value="activo">Activo</SelectItem>
                  <SelectItem value="inactivo">Inactivo</SelectItem>
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
                  <TableHead>Plan</TableHead>
                  <TableHead>Precio especial</TableHead>
                  <TableHead>Comisión</TableHead>
                  <TableHead>Entidad</TableHead>
                  <TableHead>Vigencia</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {excepcionesFiltradas.map((exc) => (
                  <TableRow key={exc.id} className={!exc.activo ? 'opacity-60' : ''}>
                    <TableCell>
                      <p className="font-medium">{exc.plan_configuracion?.plan_base?.nombre}</p>
                    </TableCell>
                    <TableCell>
                      <p className="font-medium">{formatearPrecio(exc.precio_especial, exc.plan_configuracion?.plan_base?.moneda || 'GTQ')}</p>
                    </TableCell>
                    <TableCell>
                      <p className="font-medium">{exc.comision_especial}%</p>
                    </TableCell>
                    <TableCell>
                      {exc.entidad_id ? (
                        <Badge variant="secondary">{exc.tipo_entidad}: {exc.entidad_id.slice(0, 8)}...</Badge>
                      ) : (
                        <Badge variant="secondary" className="bg-purple-100 text-purple-700">Global</Badge>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="text-sm">
                        <p>{new Date(exc.fecha_inicio).toLocaleDateString('es-GT')}</p>
                        {exc.fecha_fin && <p className="text-muted-foreground">hasta {new Date(exc.fecha_fin).toLocaleDateString('es-GT')}</p>}
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge variant={exc.activo ? 'default' : 'secondary'} className={exc.activo ? 'bg-green-100 text-green-700' : ''}>
                        {exc.activo ? 'Activo' : 'Inactivo'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {exc.activo && (
                        <Button variant="ghost" size="icon" className="text-red-500" onClick={() => desactivarExcepcion(exc.id)}>
                          <Ban className="h-4 w-4" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
                {excepcionesFiltradas.length === 0 && (
                  <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">No se encontraron excepciones</TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Dialog open={dialogoCrear} onOpenChange={setDialogoCrear}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Tag className="h-5 w-5 text-[#1E5C8E]" /> Nueva excepción</DialogTitle>
            <DialogDescription>Crea un descuento personalizado o promoción global</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Plan</Label>
              <Select value={nuevaExc.plan_config_id} onValueChange={(v) => setNuevaExc(p => ({ ...p, plan_config_id: v }))}>
                <SelectTrigger><SelectValue placeholder="Selecciona un plan" /></SelectTrigger>
                <SelectContent>
                  {planesConfig.map(pc => (
                    <SelectItem key={pc.id} value={pc.id}>{pc.plan_base?.nombre} - {pc.plan_base?.moneda}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>Precio especial</Label>
                <Input type="number" value={nuevaExc.precio_especial} onChange={(e) => setNuevaExc(p => ({ ...p, precio_especial: parseFloat(e.target.value) || 0 }))} />
              </div>
              <div><Label>Comisión especial (%)</Label>
                <Input type="number" value={nuevaExc.comision_especial} onChange={(e) => setNuevaExc(p => ({ ...p, comision_especial: parseFloat(e.target.value) || 0 }))} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>ID Entidad (opcional)</Label>
                <Input value={nuevaExc.entidad_id} onChange={(e) => setNuevaExc(p => ({ ...p, entidad_id: e.target.value }))} placeholder="UUID del médico" />
              </div>
              <div><Label>Tipo entidad</Label>
                <Select value={nuevaExc.tipo_entidad} onValueChange={(v) => setNuevaExc(p => ({ ...p, tipo_entidad: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="medico">Médico</SelectItem>
                    <SelectItem value="clinica">Clínica</SelectItem>
                    <SelectItem value="lab">Laboratorio</SelectItem>
                    <SelectItem value="visitador">Visitador</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>Fecha inicio</Label><Input type="date" value={nuevaExc.fecha_inicio} onChange={(e) => setNuevaExc(p => ({ ...p, fecha_inicio: e.target.value }))} /></div>
              <div><Label>Fecha fin (opcional)</Label><Input type="date" value={nuevaExc.fecha_fin} onChange={(e) => setNuevaExc(p => ({ ...p, fecha_fin: e.target.value }))} /></div>
            </div>
            <div><Label>Motivo</Label><Input value={nuevaExc.motivo} onChange={(e) => setNuevaExc(p => ({ ...p, motivo: e.target.value }))} placeholder="Ej: Promoción de lanzamiento..." /></div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoCrear(false)}>Cancelar</Button>
              <Button className="bg-[#1E5C8E]" onClick={handleCrear} disabled={!nuevaExc.plan_config_id || !nuevaExc.motivo}>
                <Plus className="h-4 w-4 mr-2" /> Crear
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}