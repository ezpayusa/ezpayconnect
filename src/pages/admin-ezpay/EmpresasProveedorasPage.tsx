import { useState, useEffect, useCallback, useRef } from 'react';
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
import {
  useEmpresasPais,
  type AccionEstadoEmpresa,
  type EmpresaDetalle,
  type EmpresaPais,
  type EstadoEmpresa,
} from '@/hooks/admin/useEmpresasPais';
import { toast } from 'sonner';
import { ArrowLeft, Search, RefreshCw, MapPin, CheckCircle2, XCircle, AlertTriangle, Clock, Eye, Mail, Phone, Store, FlaskConical, Handshake, Users, Package, Megaphone, DollarSign, RotateCcw } from 'lucide-react';

// Bandeja de empresas (migs 386-388). La lista sale de UNA llamada a listar_empresas_pais (todas las del país) para
// los dos roles (super_admin y admin_pais de ESE país); el filtro por estado y las tarjetas se calculan en el cliente.
// El modal "Ver detalle" pide obtener_empresa_pais al abrirse. Aprobar/rechazar van por resolver_empresa.
// Suspender/Reactivar/Reabrir van por cambiar_estado_empresa (mig 388), solo para el super_admin (D2): la RPC cambia
// el estado y avisa a la empresa en la misma llamada.

// Textos del modal de confirmación de cambiar_estado_empresa.
const ACCION_ESTADO: Record<AccionEstadoEmpresa, { titulo: string; verbo: string; aviso: string; exito: string }> = {
  suspender: {
    titulo: 'Suspender Empresa',
    verbo: 'suspender',
    aviso: 'Hasta que la reactives, la empresa solo podrá ver su perfil y sus pagos.',
    exito: 'Empresa suspendida.',
  },
  reactivar: {
    titulo: 'Reactivar Empresa',
    verbo: 'reactivar',
    aviso: 'La empresa vuelve a tener acceso completo al portal.',
    exito: 'Empresa reactivada.',
  },
  reabrir: {
    titulo: 'Reabrir Empresa',
    verbo: 'reabrir',
    aviso: 'La empresa vuelve a pendiente y se borra el motivo del rechazo.',
    exito: 'Empresa reabierta: quedó pendiente de revisión.',
  },
};

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
  const { listar, obtenerEmpresaPais, aprobar, rechazar, cambiarEstadoEmpresa } = useEmpresasPais();
  // Todas las empresas del país (una sola llamada); los chips y la búsqueda filtran sobre esta lista.
  const [empresas, setEmpresas] = useState<EmpresaPais[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState('');
  const [filtroEstado, setFiltroEstado] = useState<FiltroEstado>('pendiente');
  // Suspender / Reactivar / Reabrir (solo super_admin, cambiar_estado_empresa).
  const [dialogoAccion, setDialogoAccion] = useState<{
    empresa: EmpresaPais;
    accion: AccionEstadoEmpresa;
  } | null>(null);
  // Aprobar / Rechazar (resolver_empresa).
  const [aAprobar, setAAprobar] = useState<EmpresaPais | null>(null);
  const [aRechazar, setARechazar] = useState<EmpresaPais | null>(null);
  const [motivo, setMotivo] = useState('');
  const [procesando, setProcesando] = useState(false);
  // Ver detalle (obtener_empresa_pais): la fila de la lista abre el modal; el detalle llega de la RPC.
  const [filaDetalle, setFilaDetalle] = useState<EmpresaPais | null>(null);
  const [detalle, setDetalle] = useState<EmpresaDetalle | null>(null);
  const [detalleCargando, setDetalleCargando] = useState(false);
  const [detalleError, setDetalleError] = useState<string | null>(null);
  // Descarta la respuesta de un detalle que ya no está abierto (se cerró o se abrió otro antes de que llegara).
  const detallePedido = useRef(0);
  const { paisId } = usePaisFiltro();

  const cargarEmpresas = useCallback(async () => {
    if (!paisId) {
      setEmpresas([]);
      return;
    }
    setLoading(true);
    const r = await listar(paisId, null);
    if (r.ok) {
      setEmpresas(r.data);
    } else {
      setEmpresas([]);
      toast.error(r.error.mensaje);
    }
    setLoading(false);
  }, [paisId, listar]);

  const abrirDetalle = async (empresa: EmpresaPais) => {
    const pedido = ++detallePedido.current;
    setFilaDetalle(empresa);
    setDetalle(null);
    setDetalleError(null);
    setDetalleCargando(true);
    const r = await obtenerEmpresaPais(empresa.id);
    if (pedido !== detallePedido.current) return;
    setDetalleCargando(false);
    if (r.ok) {
      setDetalle(r.data);
      return;
    }
    setDetalleError(r.error.mensaje);
    if (r.error.recargar === 'empresas') cargarEmpresas();
  };

  const cerrarDetalle = () => {
    detallePedido.current++;
    setFilaDetalle(null);
    setDetalle(null);
    setDetalleError(null);
    setDetalleCargando(false);
  };

  useEffect(() => {
    if (!adminLoading && isAdmin) {
      cargarEmpresas();
    }
  }, [adminLoading, isAdmin, cargarEmpresas]);

  // Suspender / Reactivar / Reabrir (mig 388, solo super_admin; D2). La RPC cambia el estado y avisa a la empresa en la
  // misma llamada. EP006 (la empresa ya no está en el estado que permite la acción) y EP002 recargan la lista.
  const confirmarCambioEstado = async () => {
    if (!dialogoAccion) return;
    const { empresa, accion } = dialogoAccion;
    setProcesando(true);
    const r = await cambiarEstadoEmpresa(empresa.id, accion);
    setProcesando(false);
    if (!r.ok) {
      toast.error(r.error.mensaje);
      if (r.error.recargar === 'empresas') {
        setDialogoAccion(null);
        cargarEmpresas();
      }
      return;
    }
    const exito = ACCION_ESTADO[accion].exito;
    toast.success(
      r.data.notificado
        ? `${exito} Le avisamos a la empresa.`
        : `${exito} No se pudo enviar el aviso a la empresa.`
    );
    setDialogoAccion(null);
    cargarEmpresas();
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

  // Búsqueda por nombre, email y teléfono: listar_empresas_pais no devuelve RUC/NIT ni ciudad (y no se pide el
  // detalle por fila para buscar).
  const q = search.toLowerCase();
  const empresasFiltradas = empresas.filter(
    (e) =>
      (filtroEstado === 'todas' || e.estado === filtroEstado) &&
      (!q ||
        e.nombre_empresa?.toLowerCase().includes(q) ||
        e.email_contacto?.toLowerCase().includes(q) ||
        e.telefono?.toLowerCase().includes(q))
  );

  // Tarjetas: sobre TODAS las empresas del país, no sobre el filtro.
  const total = empresas.length;
  const activas = empresas.filter((e) => e.estado === 'activa').length;
  const pendientes = empresas.filter((e) => e.estado === 'pendiente').length;
  const suspendidas = empresas.filter((e) => e.estado === 'suspendida' || e.estado === 'rechazada').length;

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
      {/* Tarjetas: totales del país (lista completa, sin filtro) */}
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

      {/* Filtros: chips de estado + búsqueda, los dos en el cliente sobre la lista completa */}
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
                          <Button
                            variant="ghost"
                            size="icon"
                            onClick={() => abrirDetalle(empresa)}
                            title="Ver detalle"
                            aria-label={`Ver detalle de ${empresa.nombre_empresa}`}
                          >
                            <Eye className="h-4 w-4" />
                          </Button>
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
                          {/* D2: Suspender/Reactivar/Reabrir solo para el super_admin: suspender en activa,
                              reactivar en suspendida, reabrir en rechazada (mig 388). */}
                          {isSuperAdmin && empresa.estado === 'activa' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                              onClick={() => setDialogoAccion({ empresa, accion: 'suspender' })}
                            >
                              <AlertTriangle className="h-4 w-4 mr-1" /> Suspender
                            </Button>
                          )}
                          {isSuperAdmin && empresa.estado === 'suspendida' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700 hover:bg-green-50"
                              onClick={() => setDialogoAccion({ empresa, accion: 'reactivar' })}
                            >
                              <CheckCircle2 className="h-4 w-4 mr-1" /> Reactivar
                            </Button>
                          )}
                          {isSuperAdmin && empresa.estado === 'rechazada' && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-[#1E5C8E] hover:text-[#17496f] hover:bg-blue-50"
                              onClick={() => setDialogoAccion({ empresa, accion: 'reabrir' })}
                            >
                              <RotateCcw className="h-4 w-4 mr-1" /> Reabrir
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

      {/* Ver detalle (obtener_empresa_pais al abrir). Mismo layout que antes de la 386. */}
      <Dialog open={!!filaDetalle} onOpenChange={(open) => { if (!open) cerrarDetalle(); }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-[#1E5C8E]" />
              Detalle de Empresa
            </DialogTitle>
            <DialogDescription className="sr-only">
              Datos, conteos y acciones de {filaDetalle?.nombre_empresa}
            </DialogDescription>
          </DialogHeader>
          {detalleCargando && (
            <div className="flex items-center justify-center gap-2 py-8 text-muted-foreground">
              <RefreshCw className="h-4 w-4 animate-spin" /> Cargando detalle...
            </div>
          )}
          {!detalleCargando && detalleError && (
            <div className="space-y-4 py-2">
              <p role="alert" className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
                {detalleError}
              </p>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={cerrarDetalle}>
                  Cerrar
                </Button>
                {filaDetalle && (
                  <Button variant="outline" onClick={() => abrirDetalle(filaDetalle)}>
                    <RefreshCw className="h-4 w-4 mr-2" /> Reintentar
                  </Button>
                )}
              </div>
            </div>
          )}
          {!detalleCargando && detalle && filaDetalle && (
            <div className="space-y-4">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 rounded-xl bg-[#1E5C8E]/10 flex items-center justify-center">
                  {detalle.logo_url ? (
                    <img src={detalle.logo_url} alt="" className="w-14 h-14 rounded-lg object-cover" />
                  ) : (
                    <MapPin className="h-7 w-7 text-[#1E5C8E]" />
                  )}
                </div>
                <div>
                  <h3 className="text-lg font-bold">{detalle.nombre_empresa}</h3>
                  <div className="flex items-center gap-2 mt-1">
                    <Badge variant="outline" className={getEstadoBadge(detalle.estado).class}>
                      {detalle.estado.charAt(0).toUpperCase() + detalle.estado.slice(1)}
                    </Badge>
                    <span className="text-sm text-muted-foreground flex items-center gap-1">
                      {TIPO_ICONOS[detalle.tipo]}
                      {TIPO_LABELS[detalle.tipo] || detalle.tipo}
                    </span>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Users className="h-4 w-4 mx-auto mb-1 text-[#1E5C8E]" />
                  <p className="text-lg font-bold">{detalle.cuentas_count}</p>
                  <p className="text-xs text-muted-foreground">Usuarios</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Package className="h-4 w-4 mx-auto mb-1 text-emerald-600" />
                  <p className="text-lg font-bold">{detalle.productos_count}</p>
                  <p className="text-xs text-muted-foreground">Productos</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <Megaphone className="h-4 w-4 mx-auto mb-1 text-amber-600" />
                  <p className="text-lg font-bold">{detalle.campanas_count}</p>
                  <p className="text-xs text-muted-foreground">Campañas</p>
                </div>
                <div className="bg-slate-50 p-3 rounded-lg text-center">
                  <DollarSign className="h-4 w-4 mx-auto mb-1 text-purple-600" />
                  <p className="text-lg font-bold">{detalle.pagos_count}</p>
                  <p className="text-xs text-muted-foreground">Pagos</p>
                </div>
              </div>

              <div className="space-y-2 text-sm">
                {detalle.ruc_nit && (
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">RUC/NIT</span>
                    <span className="font-medium text-right">{detalle.ruc_nit}</span>
                  </div>
                )}
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground">Email</span>
                  <span className="font-medium text-right break-all">{detalle.email_contacto || '—'}</span>
                </div>
                {detalle.telefono && (
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Teléfono</span>
                    <span className="font-medium text-right">{detalle.telefono}</span>
                  </div>
                )}
                {detalle.ciudad && (
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Ciudad</span>
                    <span className="font-medium text-right">{detalle.ciudad}</span>
                  </div>
                )}
                {detalle.direccion && (
                  <div className="flex justify-between gap-4">
                    <span className="text-muted-foreground">Dirección</span>
                    <span className="font-medium text-right">{detalle.direccion}</span>
                  </div>
                )}
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground">Creada</span>
                  <span className="font-medium text-right">{fecha(detalle.created_at)}</span>
                </div>
                {/* Rechazada: motivo y fecha de revisión vienen de listar_empresas_pais (obtener no los trae). */}
                {detalle.estado === 'rechazada' && (
                  <>
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Motivo del rechazo</span>
                      <span className="font-medium text-right text-red-700 whitespace-pre-wrap break-words">
                        {filaDetalle.motivo_rechazo || '—'}
                      </span>
                    </div>
                    <div className="flex justify-between gap-4">
                      <span className="text-muted-foreground">Revisada</span>
                      <span className="font-medium text-right">{fecha(filaDetalle.revisado_at)}</span>
                    </div>
                  </>
                )}
              </div>

              {/* Mismas reglas que la fila: Aprobar/Rechazar solo en pendiente (los dos roles); Suspender/Reactivar/
                  Reabrir solo el super_admin y solo en activa/suspendida/rechazada (D2, mig 388). */}
              <div className="flex gap-2 pt-2">
                {detalle.estado === 'pendiente' && (
                  <>
                    <Button
                      className="flex-1 bg-green-600 hover:bg-green-700"
                      onClick={() => {
                        const empresa = filaDetalle;
                        cerrarDetalle();
                        setAAprobar(empresa);
                      }}
                    >
                      <CheckCircle2 className="h-4 w-4 mr-2" /> Aprobar Empresa
                    </Button>
                    <Button
                      variant="destructive"
                      className="flex-1"
                      onClick={() => {
                        const empresa = filaDetalle;
                        cerrarDetalle();
                        abrirRechazo(empresa);
                      }}
                    >
                      <XCircle className="h-4 w-4 mr-2" /> Rechazar Empresa
                    </Button>
                  </>
                )}
                {isSuperAdmin && detalle.estado === 'activa' && (
                  <Button
                    variant="destructive"
                    className="flex-1"
                    onClick={() => {
                      const empresa = filaDetalle;
                      cerrarDetalle();
                      setDialogoAccion({ empresa, accion: 'suspender' });
                    }}
                  >
                    <AlertTriangle className="h-4 w-4 mr-2" /> Suspender Empresa
                  </Button>
                )}
                {isSuperAdmin && detalle.estado === 'suspendida' && (
                  <Button
                    className="flex-1 bg-green-600 hover:bg-green-700"
                    onClick={() => {
                      const empresa = filaDetalle;
                      cerrarDetalle();
                      setDialogoAccion({ empresa, accion: 'reactivar' });
                    }}
                  >
                    <CheckCircle2 className="h-4 w-4 mr-2" /> Reactivar Empresa
                  </Button>
                )}
                {isSuperAdmin && detalle.estado === 'rechazada' && (
                  <Button
                    className="flex-1 bg-[#1E5C8E] hover:bg-[#17496f]"
                    onClick={() => {
                      const empresa = filaDetalle;
                      cerrarDetalle();
                      setDialogoAccion({ empresa, accion: 'reabrir' });
                    }}
                  >
                    <RotateCcw className="h-4 w-4 mr-2" /> Reabrir Empresa
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

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

      {/* Modal Confirmar Suspender / Reactivar / Reabrir (solo super_admin, cambiar_estado_empresa) */}
      <Dialog open={!!dialogoAccion} onOpenChange={(open) => { if (!open && !procesando) setDialogoAccion(null); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-center">
              {dialogoAccion ? ACCION_ESTADO[dialogoAccion.accion].titulo : ''}
            </DialogTitle>
            <DialogDescription className="text-center">
              {dialogoAccion ? ACCION_ESTADO[dialogoAccion.accion].aviso : ''}
            </DialogDescription>
          </DialogHeader>
          <div className="text-center py-2">
            <p className="text-muted-foreground mb-4">
              ¿Quieres <strong>{dialogoAccion ? ACCION_ESTADO[dialogoAccion.accion].verbo : ''}</strong> a{' '}
              <strong>{dialogoAccion?.empresa.nombre_empresa}</strong>? La empresa recibirá un aviso.
            </p>
            <div className="flex justify-center gap-2">
              <Button variant="outline" disabled={procesando} onClick={() => setDialogoAccion(null)}>
                Cancelar
              </Button>
              <Button
                variant={dialogoAccion?.accion === 'suspender' ? 'destructive' : 'default'}
                disabled={procesando}
                className={
                  dialogoAccion?.accion === 'reactivar'
                    ? 'bg-green-600 hover:bg-green-700'
                    : dialogoAccion?.accion === 'reabrir'
                      ? 'bg-[#1E5C8E] hover:bg-[#17496f]'
                      : ''
                }
                onClick={confirmarCambioEstado}
              >
                {procesando ? (
                  <RefreshCw className="h-4 w-4 animate-spin mr-2" />
                ) : dialogoAccion?.accion === 'reactivar' ? (
                  <CheckCircle2 className="h-4 w-4 mr-2" />
                ) : dialogoAccion?.accion === 'reabrir' ? (
                  <RotateCcw className="h-4 w-4 mr-2" />
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
