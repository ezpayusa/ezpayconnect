import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { CapacidadesTiersPais } from '@/pages/admin-ezpay/CapacidadesTiersPais';
import { ContratosComisionPais } from '@/pages/admin-ezpay/ContratosComisionPais';
import { EstadoCuentaComisionPais } from '@/pages/admin-ezpay/EstadoCuentaComisionPais';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { useEmpresasPais, type EmpresaPais, type EstadoEmpresa } from '@/hooks/useEmpresasPais';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import { ArrowLeft, Search, RefreshCw, MapPin, CheckCircle2, XCircle, AlertTriangle, Clock, Mail, Phone, Store, FlaskConical, Handshake } from 'lucide-react';

// Bandeja de empresas (mig 386). La lista sale de listar_empresas_pais para los dos roles (super_admin y admin_pais
// de ESE país); aprobar/rechazar van por resolver_empresa. Suspender/Reactivar siguen por UPDATE directo, solo para
// el super_admin (D2; los retira la 387).

type FiltroEstado = EstadoEmpresa | 'todas';

// D7: la bandeja abre en Pendientes.
const FILTROS: { value: FiltroEstado; label: string }[] = [
  { value: 'pendiente', label: 'Pendientes' },
  { value: 'activa', label: 'Activas' },
  { value: 'suspendida', label: 'Suspendidas' },
  { value: 'rechazada', label: 'Rechazadas' },
  { value: 'todas', label: 'Todas' },
];

const MOTIVO_MAX = 500;

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

function getEstadoBadge(estado: EstadoEmpresa) {
  const map: Record<EstadoEmpresa, { class: string; icon: React.ReactNode }> = {
    pendiente: { class: 'bg-yellow-100 text-yellow-700 border-yellow-200', icon: <Clock className="h-3 w-3" /> },
    activa: { class: 'bg-green-100 text-green-700 border-green-200', icon: <CheckCircle2 className="h-3 w-3" /> },
    suspendida: { class: 'bg-red-100 text-red-700 border-red-200', icon: <AlertTriangle className="h-3 w-3" /> },
    rechazada: { class: 'bg-gray-100 text-gray-700 border-gray-200', icon: <XCircle className="h-3 w-3" /> },
  };
  return map[estado] || map.pendiente;
}

const fecha = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString('es-ES') : '—');

export default function EmpresasProveedorasPage() {
  const navigate = useNavigate();
  const { isAdmin, isSuperAdmin, loading: adminLoading } = useAdminAuth();
  const { listar, aprobar, rechazar } = useEmpresasPais();
  const [empresas, setEmpresas] = useState<EmpresaPais[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState('');
  const [filtroEstado, setFiltroEstado] = useState<FiltroEstado>('pendiente');
  // Suspender / Reactivar (solo super_admin, UPDATE directo como antes de la 386).
  const [dialogoAccion, setDialogoAccion] = useState<{
    empresa: EmpresaPais;
    nuevoEstado: 'activa' | 'suspendida';
  } | null>(null);
  // Aprobar / Rechazar (resolver_empresa).
  const [aAprobar, setAAprobar] = useState<EmpresaPais | null>(null);
  const [aRechazar, setARechazar] = useState<EmpresaPais | null>(null);
  const [motivo, setMotivo] = useState('');
  const [procesando, setProcesando] = useState(false);
  const { paisId } = usePaisFiltro();

  const cargarEmpresas = useCallback(async () => {
    if (!paisId) {
      setEmpresas([]);
      return;
    }
    setLoading(true);
    const r = await listar(paisId, filtroEstado === 'todas' ? null : filtroEstado);
    if (r.ok) {
      setEmpresas(r.data);
    } else {
      setEmpresas([]);
      toast.error(r.error.mensaje);
    }
    setLoading(false);
  }, [paisId, filtroEstado, listar]);

  useEffect(() => {
    if (!adminLoading && isAdmin) {
      cargarEmpresas();
    }
  }, [adminLoading, isAdmin, cargarEmpresas]);

  // Suspender / Reactivar: SIN CAMBIOS respecto de antes de la 386 (los retira la 387).
  const cambiarEstado = async (empresaId: string, nuevoEstado: EstadoEmpresa) => {
    setProcesando(true);
    const { error } = await supabase
      .from('empresas_proveedoras')
      .update({ estado: nuevoEstado, updated_at: new Date().toISOString() })
      .eq('id', empresaId);

    if (error) {
      toast.error('Error al actualizar estado: ' + error.message);
    } else {
      toast.success(`Empresa ${nuevoEstado === 'activa' ? 'aprobada' : nuevoEstado === 'suspendida' ? 'suspendida' : 'actualizada'} correctamente`);

      // Notificar a los usuarios de la empresa (RPC gateado: deriva destinatarios + contenido del ref; estado leído de la BD)
      try {
        await supabase.rpc('notificar_empresa_estado', { p_empresa_id: empresaId });
      } catch (e) {
        console.error('Error notificando a la empresa:', e);
      }

      setDialogoAccion(null);
      cargarEmpresas();
    }
    setProcesando(false);
  };

  const confirmarAprobar = async () => {
    if (!aAprobar) return;
    setProcesando(true);
    const r = await aprobar(aAprobar.id);
    setProcesando(false);
    if (!r.ok) {
      toast.error(r.error.mensaje);
      if (r.error.recargar === 'empresas') {
        setAAprobar(null);
        cargarEmpresas();
      }
      return;
    }
    toast.success(
      r.data.notificado
        ? 'Empresa aprobada. Le avisamos a la empresa.'
        : 'Empresa aprobada. No se pudo enviar el aviso a la empresa.'
    );
    setAAprobar(null);
    cargarEmpresas();
  };

  const abrirRechazo = (empresa: EmpresaPais) => {
    setMotivo('');
    setARechazar(empresa);
  };

  const confirmarRechazar = async () => {
    const limpio = motivo.trim();
    // Doble candado: el botón ya está deshabilitado con el motivo vacío.
    if (!aRechazar || limpio === '' || limpio.length > MOTIVO_MAX) return;
    setProcesando(true);
    const r = await rechazar(aRechazar.id, limpio);
    setProcesando(false);
    if (!r.ok) {
      toast.error(r.error.mensaje);
      if (r.error.recargar === 'empresas') {
        setARechazar(null);
        cargarEmpresas();
      }
      return;
    }
    toast.success(
      r.data.notificado
        ? 'Empresa rechazada. Le avisamos a la empresa.'
        : 'Empresa rechazada. No se pudo enviar el aviso a la empresa.'
    );
    setARechazar(null);
    setMotivo('');
    cargarEmpresas();
  };

  const q = search.toLowerCase();
  const empresasFiltradas = empresas.filter(
    (e) =>
      !q ||
      e.nombre_empresa?.toLowerCase().includes(q) ||
      e.email_contacto?.toLowerCase().includes(q) ||
      e.telefono?.toLowerCase().includes(q)
  );

  const motivoLimpio = motivo.trim();

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
            <p className="text-sm text-muted-foreground">Revisa y aprueba las empresas registradas en tu país</p>
          </div>
        </div>
        <Button variant="outline" onClick={cargarEmpresas} disabled={!paisId || loading}>
          <RefreshCw className="h-4 w-4 mr-2" /> Recargar
        </Button>
      </div>

      <Tabs defaultValue="empresas">
        <TabsList className="mb-4">
          <TabsTrigger value="empresas">Empresas</TabsTrigger>
          <TabsTrigger value="capacidades">Capacidades y Tiers</TabsTrigger>
          <TabsTrigger value="comision">Contratos de Comisión</TabsTrigger>
          <TabsTrigger value="estado-cuenta">Estado de Cuenta</TabsTrigger>
        </TabsList>
        <TabsContent value="empresas">

      {!paisId ? (
        <Card>
          <CardContent className="pt-6 text-center text-muted-foreground">
            <MapPin className="h-6 w-6 mx-auto mb-2 text-[#1E5C8E]" />
            <p className="font-medium">Elige un país</p>
            <p className="text-sm">Selecciona un país en el panel para ver sus empresas.</p>
          </CardContent>
        </Card>
      ) : (
        <>
      {/* Filtros: chips de estado (van a la RPC) + búsqueda local */}
      <div className="flex flex-col gap-4 mb-6">
        <div className="flex flex-wrap gap-2" role="group" aria-label="Filtrar por estado">
          {FILTROS.map((f) => (
            <Button
              key={f.value}
              size="sm"
              variant={filtroEstado === f.value ? 'default' : 'outline'}
              aria-pressed={filtroEstado === f.value}
              onClick={() => setFiltroEstado(f.value)}
            >
              {f.label}
            </Button>
          ))}
        </div>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por nombre, email o teléfono..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
      </div>

      {/* Tabla */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">
            Listado de Empresas {!loading && <span className="text-sm font-normal text-muted-foreground">({empresasFiltradas.length})</span>}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Empresa</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead>Contacto</TableHead>
                  <TableHead>Creada</TableHead>
                  <TableHead>Revisión</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {!loading && empresasFiltradas.map((empresa) => {
                  const estadoBadge = getEstadoBadge(empresa.estado);
                  return (
                    <TableRow key={empresa.id}>
                      <TableCell>
                        <p className="font-medium">{empresa.nombre_empresa}</p>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-1.5 text-sm">
                          {TIPO_ICONOS[empresa.tipo] || <Store className="h-4 w-4" />}
                          <span>{TIPO_LABELS[empresa.tipo] || empresa.tipo}</span>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-col items-start gap-1">
                          <Badge variant="outline" className={estadoBadge.class}>
                            <span className="flex items-center gap-1">
                              {estadoBadge.icon}
                              {empresa.estado.charAt(0).toUpperCase() + empresa.estado.slice(1)}
                            </span>
                          </Badge>
                          {/* D5: solo dato; no otorga nada */}
                          {!empresa.tiene_plan_activo && (
                            <Badge variant="outline" className="bg-slate-50 text-slate-600 border-slate-200">
                              Sin plan activo
                            </Badge>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          {empresa.email_contacto && (
                            <div className="flex items-center gap-1 text-muted-foreground">
                              <Mail className="h-3 w-3" />
                              <span className="text-xs">{empresa.email_contacto}</span>
                            </div>
                          )}
                          {empresa.telefono && (
                            <div className="flex items-center gap-1 text-muted-foreground mt-0.5">
                              <Phone className="h-3 w-3" />
                              <span className="text-xs">{empresa.telefono}</span>
                            </div>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">{fecha(empresa.created_at)}</TableCell>
                      <TableCell className="text-sm max-w-xs">
                        {empresa.estado === 'rechazada' ? (
                          <div>
                            {empresa.motivo_rechazo && (
                              <p className="text-red-700 whitespace-pre-wrap break-words">
                                <span className="font-medium">Motivo:</span> {empresa.motivo_rechazo}
                              </p>
                            )}
                            <p className="text-xs text-muted-foreground">Revisada: {fecha(empresa.revisado_at)}</p>
                          </div>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1">
                          {empresa.estado === 'pendiente' && (
                            <>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="text-green-600 hover:text-green-700 hover:bg-green-50"
                                onClick={() => setAAprobar(empresa)}
                              >
                                <CheckCircle2 className="h-4 w-4 mr-1" /> Aprobar
                              </Button>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="text-red-600 hover:text-red-700 hover:bg-red-50"
                                onClick={() => abrirRechazo(empresa)}
                              >
                                <XCircle className="h-4 w-4 mr-1" /> Rechazar
                              </Button>
                            </>
                          )}
                          {/* D2: Suspender/Reactivar solo para el super_admin y solo en activa/suspendida (los retira la 387). */}
                          {isSuperAdmin && empresa.estado === 'activa' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                              onClick={() => setDialogoAccion({ empresa, nuevoEstado: 'suspendida' })}
                            >
                              <AlertTriangle className="h-4 w-4 mr-1" /> Suspender
                            </Button>
                          )}
                          {isSuperAdmin && empresa.estado === 'suspendida' && (
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
                {(loading || empresasFiltradas.length === 0) && (
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
        </>
      )}

      {/* Aprobar (resolver_empresa): confirmación simple */}
      <Dialog open={!!aAprobar} onOpenChange={(open) => { if (!open && !procesando) setAAprobar(null); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-center">Aprobar Empresa</DialogTitle>
          </DialogHeader>
          <div className="text-center py-2">
            <p className="text-muted-foreground mb-4">
              ¿Quieres <strong>aprobar</strong> a <strong>{aAprobar?.nombre_empresa}</strong>? La empresa recibirá un aviso.
            </p>
            <div className="flex justify-center gap-2">
              <Button variant="outline" disabled={procesando} onClick={() => setAAprobar(null)}>
                Cancelar
              </Button>
              <Button className="bg-green-600 hover:bg-green-700" disabled={procesando} onClick={confirmarAprobar}>
                {procesando ? <RefreshCw className="h-4 w-4 animate-spin mr-2" /> : <CheckCircle2 className="h-4 w-4 mr-2" />}
                Aprobar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Rechazar (resolver_empresa): motivo OBLIGATORIO, hasta 500. Botón deshabilitado + return temprano. */}
      <Dialog open={!!aRechazar} onOpenChange={(open) => { if (!open && !procesando) setARechazar(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Rechazar Empresa</DialogTitle>
            <DialogDescription>
              Vas a rechazar a <span className="font-medium">{aRechazar?.nombre_empresa}</span>. La empresa recibirá un
              aviso; el motivo queda registrado en la bandeja.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <label htmlFor="motivo-rechazo-empresa" className="text-sm font-medium">
              Motivo del rechazo <span className="text-red-500">*</span>
            </label>
            <Textarea
              id="motivo-rechazo-empresa"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              maxLength={MOTIVO_MAX}
              rows={4}
              placeholder="Escribe por qué se rechaza la empresa"
            />
            <p className="text-xs text-muted-foreground text-right">
              {motivo.length}/{MOTIVO_MAX}
            </p>
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" disabled={procesando} onClick={() => setARechazar(null)}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              disabled={procesando || motivoLimpio === '' || motivoLimpio.length > MOTIVO_MAX}
              onClick={confirmarRechazar}
            >
              {procesando ? <RefreshCw className="h-4 w-4 animate-spin mr-2" /> : <XCircle className="h-4 w-4 mr-2" />}
              Rechazar
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Modal Confirmar Suspender / Reactivar (solo super_admin) */}
      <Dialog open={!!dialogoAccion} onOpenChange={() => setDialogoAccion(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-center">
              {dialogoAccion?.nuevoEstado === 'activa' ? 'Reactivar Empresa' : 'Suspender Empresa'}
            </DialogTitle>
          </DialogHeader>
          <div className="text-center py-2">
            <p className="text-muted-foreground mb-4">
              ¿Estás seguro de que deseas{' '}
              <strong>{dialogoAccion?.nuevoEstado === 'activa' ? 'reactivar' : 'suspender'}</strong>{' '}
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

        </TabsContent>
        <TabsContent value="capacidades">
          <CapacidadesTiersPais paisId={paisId} esSuper={isSuperAdmin} />
        </TabsContent>
        <TabsContent value="comision">
          <ContratosComisionPais paisId={paisId} esSuper={isSuperAdmin} />
        </TabsContent>
        <TabsContent value="estado-cuenta">
          <EstadoCuentaComisionPais paisId={paisId} esSuper={isSuperAdmin} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
