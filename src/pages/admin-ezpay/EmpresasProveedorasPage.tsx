import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import { crearNotificacionInApp } from '@/proveedor/lib/notificaciones';
import type { EmpresaProveedora, EmpresaEstado } from '@/proveedor/types/proveedor.types';
import { ArrowLeft, Search, RefreshCw, MapPin, CheckCircle2, XCircle, AlertTriangle, Clock, Eye, Mail, Phone, Store, FlaskConical, Pill, Handshake, Users, Package, Megaphone, DollarSign } from 'lucide-react';

interface EmpresaConConteos extends EmpresaProveedora {
  cuentas_count?: number;
  productos_count?: number;
  campanas_count?: number;
  pagos_count?: number;
}

const ESTADOS: { value: EmpresaEstado | 'todos'; label: string }[] = [
  { value: 'todos', label: 'Todos' },
  { value: 'pendiente', label: 'Pendiente' },
  { value: 'activa', label: 'Activa' },
  { value: 'suspendida', label: 'Suspendida' },
  { value: 'rechazada', label: 'Rechazada' },
];

const TIPO_ICONOS: Record<string, React.ReactNode> = {
  farmacia: <Store className="h-4 w-4" />,
  laboratorio_farmaceutico: <FlaskConical className="h-4 w-4" />,
  laboratorio_clinico: <FlaskConical className="h-4 w-4" />,
  empresa_afin: <Handshake className="h-4 w-4" />,
};

const TIPO_LABELS: Record<string, string> = {
  farmacia: 'Farmacia',
  laboratorio_farmaceutico: 'Laboratorio Farmacéutico',
  laboratorio_clinico: 'Laboratorio Clínico',
  empresa_afin: 'Empresa Afín',
};

function getEstadoBadge(estado: EmpresaEstado) {
  const map: Record<EmpresaEstado, { class: string; icon: React.ReactNode }> = {
    pendiente: { class: 'bg-yellow-100 text-yellow-700 border-yellow-200', icon: <Clock className="h-3 w-3" /> },
    activa: { class: 'bg-green-100 text-green-700 border-green-200', icon: <CheckCircle2 className="h-3 w-3" /> },
    suspendida: { class: 'bg-red-100 text-red-700 border-red-200', icon: <AlertTriangle className="h-3 w-3" /> },
    rechazada: { class: 'bg-gray-100 text-gray-700 border-gray-200', icon: <XCircle className="h-3 w-3" /> },
  };
  return map[estado] || map.pendiente;
}

export default function EmpresasProveedorasPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [empresas, setEmpresas] = useState<EmpresaConConteos[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filtroEstado, setFiltroEstado] = useState<EmpresaEstado | 'todos'>('todos');
  const [empresaDetalle, setEmpresaDetalle] = useState<EmpresaConConteos | null>(null);
  const [dialogoAccion, setDialogoAccion] = useState<{
    empresa: EmpresaConConteos;
    nuevoEstado: EmpresaEstado;
  } | null>(null);
  const [procesando, setProcesando] = useState(false);
  const { paisId } = usePaisFiltro();

  const cargarEmpresas = async () => {
    setLoading(true);
    let query = supabase
      .from('empresas_proveedoras')
      .select(
        `*,
        cuentas_count:cuentas_proveedor(count),
        productos_count:productos_empresa(count),
        campanas_count:solicitudes_campana(count),
        pagos_count:pagos_proveedor(count)`
      )
    if (paisId) query = query.eq('pais_id', paisId)
    const { data, error } = await query.order('created_at', { ascending: false });

    if (error) {
      console.error('Error cargando empresas:', error);
      toast.error('Error al cargar empresas');
    } else {
      const formateadas = (data || []).map((e: any) => ({
        ...e,
        cuentas_count: e.cuentas_count?.[0]?.count ?? 0,
        productos_count: e.productos_count?.[0]?.count ?? 0,
        campanas_count: e.campanas_count?.[0]?.count ?? 0,
        pagos_count: e.pagos_count?.[0]?.count ?? 0,
      })) as EmpresaConConteos[];
      setEmpresas(formateadas);
    }
    setLoading(false);
  };

  useEffect(() => {
    if (!adminLoading && isAdmin) {
      cargarEmpresas();
    }
  }, [adminLoading, isAdmin]);

  const cambiarEstado = async (empresaId: string, nuevoEstado: EmpresaEstado) => {
    setProcesando(true);
    const { error } = await supabase
      .from('empresas_proveedoras')
      .update({ estado: nuevoEstado, updated_at: new Date().toISOString() })
      .eq('id', empresaId);

    if (error) {
      toast.error('Error al actualizar estado: ' + error.message);
    } else {
      toast.success(`Empresa ${nuevoEstado === 'activa' ? 'aprobada' : nuevoEstado === 'suspendida' ? 'suspendida' : 'actualizada'} correctamente`);

      // Notificar a los usuarios de la empresa
      try {
        const { data: usuarios } = await supabase.rpc('obtener_usuarios_empresa', { p_empresa_id: empresaId });
        const aprobada = nuevoEstado === 'activa';
        for (const u of (usuarios || []) as { user_id: string }[]) {
          await crearNotificacionInApp({
            usuario_id: u.user_id,
            tipo: 'empresa',
            titulo: aprobada ? 'Empresa aprobada' : 'Estado de tu empresa actualizado',
            mensaje: aprobada
              ? 'Tu empresa fue aprobada. Ya puedes operar en EzPayConnect.'
              : `El estado de tu empresa cambió a: ${nuevoEstado}.`,
            accion_url: '/proveedor/dashboard',
            metadata: { empresa_id: empresaId },
          });
        }
      } catch (e) {
        console.error('Error notificando a la empresa:', e);
      }

      setDialogoAccion(null);
      setEmpresaDetalle((prev) => (prev ? { ...prev, estado: nuevoEstado } : null));
      cargarEmpresas();
    }
    setProcesando(false);
  };

  const empresasFiltradas = empresas.filter((e) => {
    const matchSearch =
      !search ||
      e.nombre_empresa?.toLowerCase().includes(search.toLowerCase()) ||
      e.email_contacto?.toLowerCase().includes(search.toLowerCase()) ||
      e.ruc_nit?.toLowerCase().includes(search.toLowerCase()) ||
      e.ciudad?.toLowerCase().includes(search.toLowerCase());
    const matchEstado = filtroEstado === 'todos' || e.estado === filtroEstado;
    return matchSearch && matchEstado;
  });

  const total = empresas.length;
  const activas = empresas.filter((e) => e.estado === 'activa').length;
  const pendientes = empresas.filter((e) => e.estado === 'pendiente').length;
  const suspendidas = empresas.filter((e) => e.estado === 'suspendida' || e.estado === 'rechazada').length;

  if (adminLoading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h2 className="text-xl font-bold mb-2">Acceso restringido</h2>
            <p className="text-sm text-muted-foreground mb-4">Necesitas rol de administrador.</p>
            <Button onClick={() => navigate('/dashboard')}>Volver</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Empresas Proveedoras</h1>
            <p className="text-sm text-muted-foreground">Gestiona y aprueba empresas registradas en el portal</p>
          </div>
        </div>
        <Button variant="outline" onClick={cargarEmpresas}>
          <RefreshCw className="h-4 w-4 mr-2" /> Recargar
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <MapPin className="h-5 w-5 text-[#1E5C8E]" />
              <p className="text-sm text-muted-foreground">Total Empresas</p>
            </div>
            <p className="text-2xl font-bold">{total}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <CheckCircle2 className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Activas</p>
            </div>
            <p className="text-2xl font-bold">{activas}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="h-5 w-5 text-yellow-600" />
              <p className="text-sm text-muted-foreground">Pendientes</p>
            </div>
            <p className="text-2xl font-bold">{pendientes}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <AlertTriangle className="h-5 w-5 text-red-500" />
              <p className="text-sm text-muted-foreground">Suspendidas / Rechazadas</p>
            </div>
            <p className="text-2xl font-bold">{suspendidas}</p>
          </CardContent>
        </Card>
      </div>

      {/* Filtros */}
      <div className="flex flex-col sm:flex-row gap-4 mb-6">
        <div className="flex-1">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Buscar por nombre, email, RUC/NIT o ciudad..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9"
            />
          </div>
        </div>
        <Select value={filtroEstado} onValueChange={(v) => setFiltroEstado(v as EmpresaEstado | 'todos')}>
          <SelectTrigger className="w-[200px]">
            <SelectValue placeholder="Filtrar por estado" />
          </SelectTrigger>
          <SelectContent>
            {ESTADOS.map((s) => (
              <SelectItem key={s.value} value={s.value}>
                {s.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Tabla */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Listado de Empresas</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Empresa</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Contacto</TableHead>
                  <TableHead>Ubicación</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead>Registro</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {empresasFiltradas.map((empresa) => {
                  const estadoBadge = getEstadoBadge(empresa.estado);
                  return (
                    <TableRow key={empresa.id}>
                      <TableCell>
                        <div className="flex items-center gap-3">
                          <div className="w-9 h-9 rounded-lg bg-[#1E5C8E]/10 flex items-center justify-center text-[#1E5C8E]">
                            {empresa.logo_url ? (
                              <img src={empresa.logo_url} alt="" className="w-8 h-8 rounded object-cover" />
                            ) : (
                              <MapPin className="h-4 w-4" />
                            )}
                          </div>
                          <div>
                            <p className="font-medium">{empresa.nombre_empresa}</p>
                            {empresa.ruc_nit && <p className="text-xs text-muted-foreground">RUC/NIT: {empresa.ruc_nit}</p>}
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-1.5 text-sm">
                          {TIPO_ICONOS[empresa.tipo] || <Store className="h-4 w-4" />}
                          <span>{TIPO_LABELS[empresa.tipo] || empresa.tipo}</span>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          <div className="flex items-center gap-1 text-muted-foreground">
                            <Mail className="h-3 w-3" />
                            <span className="text-xs">{empresa.email_contacto}</span>
                          </div>
                          {empresa.telefono && (
                            <div className="flex items-center gap-1 text-muted-foreground mt-0.5">
                              <Phone className="h-3 w-3" />
                              <span className="text-xs">{empresa.telefono}</span>
                            </div>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm text-muted-foreground">
                          {empresa.ciudad ? (
                            <div className="flex items-center gap-1">
                              <MapPin className="h-3 w-3" />
                              <span>{empresa.ciudad}</span>
                            </div>
                          ) : (
                            <span className="text-xs italic">Sin ciudad</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className={estadoBadge.class}>
                          <span className="flex items-center gap-1">
                            {estadoBadge.icon}
                            {empresa.estado.charAt(0).toUpperCase() + empresa.estado.slice(1)}
                          </span>
                        </Badge>
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {new Date(empresa.created_at).toLocaleDateString('es-ES')}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={() => setEmpresaDetalle(empresa)} title="Ver detalle">
                            <Eye className="h-4 w-4" />
                          </Button>
                          {empresa.estado === 'pendiente' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700 hover:bg-green-50"
                              onClick={() => setDialogoAccion({ empresa, nuevoEstado: 'activa' })}
                            >
                              <CheckCircle2 className="h-4 w-4 mr-1" /> Aprobar
                            </Button>
                          )}
                          {empresa.estado === 'activa' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                              onClick={() => setDialogoAccion({ empresa, nuevoEstado: 'suspendida' })}
                            >
                              <AlertTriangle className="h-4 w-4 mr-1" /> Suspender
                            </Button>
                          )}
                          {(empresa.estado === 'suspendida' || empresa.estado === 'rechazada') && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700 hover:bg-green-50"
                              onClick={() => setDialogoAccion({ empresa, nuevoEstado: 'activa' })}
                            >
                              <CheckCircle2 className="h-4 w-4 mr-1" /> Reactivar
                            </Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
                {empresasFiltradas.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                      {loading ? 'Cargando empresas...' : 'No se encontraron empresas'}
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Modal Detalle */}
      <Dialog open={!!empresaDetalle} onOpenChange={() => setEmpresaDetalle(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-[#1E5C8E]" />
              Detalle de Empresa
            </DialogTitle>
          </DialogHeader>
          {empresaDetalle && (
            <div className="space-y-4">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 rounded-xl bg-[#1E5C8E]/10 flex items-center justify-center">
                  {empresaDetalle.logo_url ? (
                    <img src={empresaDetalle.logo_url} alt="" className="w-14 h-14 rounded-lg object-cover" />
                  ) : (
                    <MapPin className="h-7 w-7 text-[#1E5C8E]" />
                  )}
                </div>
                <div>
                  <h3 className="text-lg font-bold">{empresaDetalle.nombre_empresa}</h3>
                  <div className="flex items-center gap-2 mt-1">
                    <Badge variant="outline" className={getEstadoBadge(empresaDetalle.estado).class}>
                      {empresaDetalle.estado.charAt(0).toUpperCase() + empresaDetalle.estado.slice(1)}
                    </Badge>
                    <span className="text-sm text-muted-foreground flex items-center gap-1">
                      {TIPO_ICONOS[empresaDetalle.tipo]}
                      {TIPO_LABELS[empresaDetalle.tipo] || empresaDetalle.tipo}
                    </span>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Users className="h-4 w-4 mx-auto mb-1 text-[#1E5C8E]" />
                  <p className="text-lg font-bold">{empresaDetalle.cuentas_count ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Usuarios</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Package className="h-4 w-4 mx-auto mb-1 text-emerald-600" />
                  <p className="text-lg font-bold">{empresaDetalle.productos_count ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Productos</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Megaphone className="h-4 w-4 mx-auto mb-1 text-amber-600" />
                  <p className="text-lg font-bold">{empresaDetalle.campanas_count ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Campañas</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <DollarSign className="h-4 w-4 mx-auto mb-1 text-purple-600" />
                  <p className="text-lg font-bold">{empresaDetalle.pagos_count ?? 0}</p>
                  <p className="text-xs text-muted-foreground">Pagos</p>
                </div>
              </div>

              <div className="space-y-2 text-sm">
                {empresaDetalle.ruc_nit && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">RUC/NIT</span>
                    <span className="font-medium">{empresaDetalle.ruc_nit}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Email</span>
                  <span className="font-medium">{empresaDetalle.email_contacto}</span>
                </div>
                {empresaDetalle.telefono && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Teléfono</span>
                    <span className="font-medium">{empresaDetalle.telefono}</span>
                  </div>
                )}
                {empresaDetalle.ciudad && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Ciudad</span>
                    <span className="font-medium">{empresaDetalle.ciudad}</span>
                  </div>
                )}
                {empresaDetalle.direccion && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Dirección</span>
                    <span className="font-medium">{empresaDetalle.direccion}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Registrada</span>
                  <span className="font-medium">{new Date(empresaDetalle.created_at).toLocaleDateString('es-ES')}</span>
                </div>
              </div>

              <div className="flex gap-2 pt-2">
                {empresaDetalle.estado === 'pendiente' && (
                  <Button
                    className="flex-1 bg-green-600 hover:bg-green-700"
                    onClick={() => {
                      setDialogoAccion({ empresa: empresaDetalle, nuevoEstado: 'activa' });
                      setEmpresaDetalle(null);
                    }}
                  >
                    <CheckCircle2 className="h-4 w-4 mr-2" /> Aprobar Empresa
                  </Button>
                )}
                {empresaDetalle.estado === 'activa' && (
                  <Button
                    variant="destructive"
                    className="flex-1"
                    onClick={() => {
                      setDialogoAccion({ empresa: empresaDetalle, nuevoEstado: 'suspendida' });
                      setEmpresaDetalle(null);
                    }}
                  >
                    <AlertTriangle className="h-4 w-4 mr-2" /> Suspender Empresa
                  </Button>
                )}
                {(empresaDetalle.estado === 'suspendida' || empresaDetalle.estado === 'rechazada') && (
                  <Button
                    className="flex-1 bg-green-600 hover:bg-green-700"
                    onClick={() => {
                      setDialogoAccion({ empresa: empresaDetalle, nuevoEstado: 'activa' });
                      setEmpresaDetalle(null);
                    }}
                  >
                    <CheckCircle2 className="h-4 w-4 mr-2" /> Reactivar Empresa
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Modal Confirmar Acción */}
      <Dialog open={!!dialogoAccion} onOpenChange={() => setDialogoAccion(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-center">
              {dialogoAccion?.nuevoEstado === 'activa'
                ? dialogoAccion.empresa.estado === 'pendiente'
                  ? 'Aprobar Empresa'
                  : 'Reactivar Empresa'
                : 'Suspender Empresa'}
            </DialogTitle>
          </DialogHeader>
          <div className="text-center py-2">
            <p className="text-muted-foreground mb-4">
              ¿Estás seguro de que deseas{' '}
              <strong>
                {dialogoAccion?.nuevoEstado === 'activa'
                  ? dialogoAccion?.empresa.estado === 'pendiente'
                    ? 'aprobar'
                    : 'reactivar'
                  : 'suspender'}
              </strong>{' '}
              a <strong>{dialogoAccion?.empresa.nombre_empresa}</strong>?
            </p>
            <div className="flex justify-center gap-2">
              <Button variant="outline" onClick={() => setDialogoAccion(null)}>
                Cancelar
              </Button>
              <Button
                variant={dialogoAccion?.nuevoEstado === 'activa' ? 'default' : 'destructive'}
                disabled={procesando}
                className={dialogoAccion?.nuevoEstado === 'activa' ? 'bg-green-600 hover:bg-green-700' : ''}
                onClick={() =>
                  dialogoAccion && cambiarEstado(dialogoAccion.empresa.id, dialogoAccion.nuevoEstado)
                }
              >
                {procesando ? (
                  <RefreshCw className="h-4 w-4 animate-spin mr-2" />
                ) : dialogoAccion?.nuevoEstado === 'activa' ? (
                  <CheckCircle2 className="h-4 w-4 mr-2" />
                ) : (
                  <AlertTriangle className="h-4 w-4 mr-2" />
                )}
                Confirmar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
