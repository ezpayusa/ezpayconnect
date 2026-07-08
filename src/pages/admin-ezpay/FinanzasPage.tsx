import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { 
  ArrowLeft, 
  RefreshCw, 
  DollarSign, 
  TrendingUp, 
  TrendingDown, 
  CreditCard, 
  Globe,
  Calendar
} from 'lucide-react';

interface Transaccion {
  id: string;
  plan_id: string;
  pais_id: string;
  monto: number;
  moneda: string;
  estado: string;
  metodo_pago: string;
  fecha_pago: string;
}

interface Stats {
  total_ingresos: number;
  total_transacciones: number;
  transacciones_completadas: number;
  transacciones_pendientes: number;
  comisiones_total: number;
}

export default function FinanzasPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [transacciones, setTransacciones] = useState<Transaccion[]>([]);
  const [planesMap, setPlanesMap] = useState<Record<string, string>>({});
  const [paisesMap, setPaisesMap] = useState<Record<string, { nombre: string; moneda: string }>>({});
  const [stats, setStats] = useState<Stats>({
    total_ingresos: 0,
    total_transacciones: 0,
    transacciones_completadas: 0,
    transacciones_pendientes: 0,
    comisiones_total: 0,
  });
  const [loading, setLoading] = useState(true);
  const [filtroEstado, setFiltroEstado] = useState('todos');
  const [filtroPais, setFiltroPais] = useState('todos');
  const [paises, setPaises] = useState<any[]>([]);

  const cargarDatos = useCallback(async () => {
    setLoading(true);

    // Cargar países
    const { data: paisesData } = await supabase.from('configuracion_pais').select('id, nombre, moneda, codigo').order('nombre');
    setPaises(paisesData || []);

    // Crear mapa de países
    const paisesMapTemp: Record<string, { nombre: string; moneda: string }> = {};
    (paisesData || []).forEach((p: any) => {
      paisesMapTemp[p.id] = { nombre: p.nombre, moneda: p.moneda };
    });
    setPaisesMap(paisesMapTemp);

    // Cargar planes base
    const { data: planesData } = await supabase.from('planes_base').select('id, nombre').eq('activo', true);
    const planesMapTemp: Record<string, string> = {};
    (planesData || []).forEach((p: any) => {
      planesMapTemp[p.id] = p.nombre;
    });
    setPlanesMap(planesMapTemp);

    // Cargar transacciones (sin joins, solo datos crudos)
    let query = supabase
      .from('transacciones')
      .select('*')
      .order('fecha_pago', { ascending: false });

    if (filtroEstado !== 'todos') {
      query = query.eq('estado', filtroEstado);
    }
    if (filtroPais !== 'todos') {
      query = query.eq('pais_id', filtroPais);
    }

    const { data: transData, error } = await query.limit(50);

    if (error) {
      console.error('Error:', error.message);
      alert('Error al cargar transacciones: ' + error.message);
    } else {
      setTransacciones(transData || []);

      // Calcular stats
      const completadas = (transData || []).filter((t: any) => t.estado === 'completado');
      const pendientes = (transData || []).filter((t: any) => t.estado === 'pendiente');
      const totalMonto = completadas.reduce((sum: number, t: any) => sum + (t.monto || 0), 0);

      setStats({
        total_ingresos: totalMonto,
        total_transacciones: (transData || []).length,
        transacciones_completadas: completadas.length,
        transacciones_pendientes: pendientes.length,
        comisiones_total: totalMonto * 0.05,
      });
    }
    setLoading(false);
  }, [filtroEstado, filtroPais]);

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard');
      return;
    }
    cargarDatos();
  }, [adminLoading, isAdmin, navigate, cargarDatos]);

  const getEstadoBadge = (estado: string) => {
    switch (estado) {
      case 'completado': return 'bg-green-100 text-green-700';
      case 'pendiente': return 'bg-yellow-100 text-yellow-700';
      case 'fallido': return 'bg-red-100 text-red-700';
      case 'reembolsado': return 'bg-gray-100 text-gray-700';
      default: return 'bg-blue-100 text-blue-700';
    }
  };

  const getMetodoIcon = (metodo: string) => {
    switch (metodo) {
      case 'tarjeta': return <CreditCard className="h-4 w-4" />;
      case 'transferencia': return <TrendingUp className="h-4 w-4" />;
      default: return <DollarSign className="h-4 w-4" />;
    }
  };

  if (adminLoading) return <div className="flex justify-center p-8">Verificando permisos...</div>;
  if (!isAdmin) return null;

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Finanzas</h1>
            <p className="text-sm text-muted-foreground">Gestión de ingresos, transacciones y comisiones</p>
          </div>
        </div>
        <Button variant="outline" onClick={cargarDatos}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Ingresos Totales</p>
            </div>
            <p className="text-2xl font-bold">${stats.total_ingresos.toFixed(2)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <CreditCard className="h-5 w-5 text-blue-600" />
              <p className="text-sm text-muted-foreground">Transacciones</p>
            </div>
            <p className="text-2xl font-bold">{stats.total_transacciones}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Completadas</p>
            </div>
            <p className="text-2xl font-bold">{stats.transacciones_completadas}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingDown className="h-5 w-5 text-yellow-600" />
              <p className="text-sm text-muted-foreground">Pendientes</p>
            </div>
            <p className="text-2xl font-bold">{stats.transacciones_pendientes}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Globe className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Comisiones</p>
            </div>
            <p className="text-2xl font-bold">${stats.comisiones_total.toFixed(2)}</p>
          </CardContent>
        </Card>
      </div>

      {/* Filtros */}
      <div className="flex gap-4 mb-6">
        <div className="w-48">
          <Select value={filtroEstado} onValueChange={setFiltroEstado}>
            <SelectTrigger>
              <SelectValue placeholder="Estado" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos los estados</SelectItem>
              <SelectItem value="completado">Completado</SelectItem>
              <SelectItem value="pendiente">Pendiente</SelectItem>
              <SelectItem value="fallido">Fallido</SelectItem>
              <SelectItem value="reembolsado">Reembolsado</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="w-48">
          <Select value={filtroPais} onValueChange={setFiltroPais}>
            <SelectTrigger>
              <SelectValue placeholder="País" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos los países</SelectItem>
              {paises.map((pais) => (
                <SelectItem key={pais.id} value={pais.id}>{pais.nombre}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      {/* Tabla de transacciones */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <Calendar className="h-5 w-5" />
            Historial de Transacciones
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-8">
              <RefreshCw className="h-8 w-8 animate-spin text-blue-600" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-3 px-4">Plan</th>
                    <th className="text-left py-3 px-4">País</th>
                    <th className="text-right py-3 px-4">Monto</th>
                    <th className="text-center py-3 px-4">Estado</th>
                    <th className="text-center py-3 px-4">Método</th>
                    <th className="text-left py-3 px-4">Fecha</th>
                  </tr>
                </thead>
                <tbody>
                  {transacciones.map((t) => {
                    const planNombre = planesMap[t.plan_id] || 'Plan desconocido';
                    const paisInfo = paisesMap[t.pais_id] || { nombre: 'País desconocido', moneda: 'USD' };
                    return (
                      <tr key={t.id} className="border-b hover:bg-gray-50">
                        <td className="py-3 px-4 font-medium">{planNombre}</td>
                        <td className="py-3 px-4">{paisInfo.nombre}</td>
                        <td className="py-3 px-4 text-right font-semibold">
                          {paisInfo.moneda === 'GTQ' ? 'Q' : paisInfo.moneda === 'HNL' ? 'L' : '$'}
                          {t.monto.toFixed(2)}
                        </td>
                        <td className="py-3 px-4 text-center">
                          <Badge className={getEstadoBadge(t.estado)}>
                            {t.estado}
                          </Badge>
                        </td>
                        <td className="py-3 px-4 text-center">
                          <div className="flex items-center justify-center gap-1">
                            {getMetodoIcon(t.metodo_pago)}
                            <span className="capitalize">{t.metodo_pago}</span>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-muted-foreground">
                          {t.fecha_pago ? new Date(t.fecha_pago).toLocaleDateString('es-ES') : '—'}
                        </td>
                      </tr>
                    );
                  })}
                  {transacciones.length === 0 && (
                    <tr>
                      <td colSpan={6} className="text-center py-8 text-muted-foreground">
                        No hay transacciones registradas
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}