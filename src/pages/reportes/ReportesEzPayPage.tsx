import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { 
  ArrowLeft, 
  RefreshCw, 
  DollarSign, 
  BarChart3, 
  TrendingUp, 
  Globe,
  Calendar,
  Stethoscope,
  Home,
  FlaskConical,
  Truck,
  Layers,
  CreditCard,
  Users,
  MapPin,
  Pill,
  Store,
  Megaphone,
  Briefcase
} from 'lucide-react';

interface ReportePais {
  pais: string;
  codigo: string;
  transacciones: number;
  ingresos: number;
  moneda: string;
}

interface ReportePlan {
  plan: string;
  tipo: string;
  ventas: number;
  ingresos: number;
}

interface ReporteMensual {
  mes: string;
  anio: number;
  total: number;
  transacciones: number;
}

const tabs = [
  { id: 'todos', label: 'Todos los Planes', icon: Layers, color: 'bg-[#1E5C8E]', barColor: 'bg-[#1E5C8E]' },
  { id: 'medico', label: 'Plan Médico', icon: Stethoscope, color: 'bg-blue-600', barColor: 'bg-blue-500' },
  { id: 'clinica', label: 'Planes Clínica', icon: Home, color: 'bg-indigo-600', barColor: 'bg-indigo-500' },
  { id: 'lab', label: 'Planes Lab', icon: FlaskConical, color: 'bg-green-600', barColor: 'bg-green-500' },
  { id: 'visitador', label: 'Planes Visitador', icon: Truck, color: 'bg-orange-600', barColor: 'bg-orange-500' },
  { id: 'farmaceutico', label: 'Farmacéutico', icon: Pill, color: 'bg-red-600', barColor: 'bg-red-500' },
  { id: 'farmacia', label: 'Farmacia', icon: Store, color: 'bg-teal-600', barColor: 'bg-teal-500' },
  { id: 'publicidad', label: 'Publicidad', icon: Megaphone, color: 'bg-pink-600', barColor: 'bg-pink-500' },
  { id: 'otros', label: 'Empresas Afines', icon: Briefcase, color: 'bg-slate-600', barColor: 'bg-slate-500' },
];

const periodos = [
  { id: 'hoy', label: 'Hoy' },
  { id: 'semana', label: 'Esta semana' },
  { id: 'mes', label: 'Este mes' },
  { id: 'trimestre', label: 'Este trimestre' },
  { id: 'anio', label: 'Este año' },
];

export default function ReportesEzPayPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [tabActiva, setTabActiva] = useState('todos');
  const [periodo, setPeriodo] = useState('mes');
  const [reportePaises, setReportePaises] = useState<ReportePais[]>([]);
  const [reportePlanes, setReportePlanes] = useState<ReportePlan[]>([]);
  const [reporteMensual, setReporteMensual] = useState<ReporteMensual[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    totalIngresos: 0,
    totalVentas: 0,
    paisesActivos: 0,
    planesVendidos: 0,
    comisionesEstimadas: 0,
  });

  const getFechaInicio = () => {
    const hoy = new Date();
    switch (periodo) {
      case 'hoy': return new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
      case 'semana': { const d = new Date(hoy); d.setDate(d.getDate() - 7); return d; }
      case 'mes': return new Date(hoy.getFullYear(), hoy.getMonth(), 1);
      case 'trimestre': return new Date(hoy.getFullYear(), Math.floor(hoy.getMonth() / 3) * 3, 1);
      case 'anio': return new Date(hoy.getFullYear(), 0, 1);
      default: return new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    }
  };

  const cargarDatos = async () => {
    setLoading(true);
    const fechaInicio = getFechaInicio();

    // Cargar países
    const { data: paisesData } = await supabase.from('configuracion_pais').select('id, nombre, codigo, moneda').order('nombre');
    const paisesMap: Record<string, { nombre: string; codigo: string; moneda: string }> = {};
    (paisesData || []).forEach((p: any) => { paisesMap[p.id] = { nombre: p.nombre, codigo: p.codigo, moneda: p.moneda }; });

    // Cargar planes base
    const { data: planesData } = await supabase.from('planes_base').select('id, nombre, tipo').eq('activo', true);
    const planesMap: Record<string, { nombre: string; tipo: string }> = {};
    (planesData || []).forEach((p: any) => { planesMap[p.id] = { nombre: p.nombre, tipo: p.tipo }; });

    // Filtrar planes por tipo si no es "todos"
    let planIdsFiltrados: string[] | null = null;
    if (tabActiva !== 'todos') {
      planIdsFiltrados = (planesData || []).filter((p: any) => p.tipo === tabActiva).map((p: any) => p.id);
      if (planIdsFiltrados.length === 0) {
        setReportePaises([]);
        setReportePlanes([]);
        setReporteMensual([]);
        setStats({ totalIngresos: 0, totalVentas: 0, paisesActivos: 0, planesVendidos: 0, comisionesEstimadas: 0 });
        setLoading(false);
        return;
      }
    }

    // Cargar transacciones
    let query = supabase
      .from('transacciones')
      .select('*')
      .eq('estado', 'completado')
      .gte('fecha_pago', fechaInicio.toISOString());

    if (planIdsFiltrados) {
      query = query.in('plan_id', planIdsFiltrados);
    }

    const { data: transData, error } = await query;

    if (error) {
      console.error('Error:', error.message);
      alert('Error al cargar transacciones: ' + error.message);
      setLoading(false);
      return;
    }

    // Procesar por país
    const paisesReporte: Record<string, ReportePais> = {};
    // Procesar por plan
    const planesReporte: Record<string, ReportePlan> = {};
    // Procesar mensual
    const mensualMap: Record<string, ReporteMensual> = {};

    (transData || []).forEach((t: any) => {
      const planInfo = planesMap[t.plan_id];
      const paisInfo = paisesMap[t.pais_id];

      if (!planInfo || !paisInfo) return;

      // Por país
      const paisKey = paisInfo.nombre;
      if (!paisesReporte[paisKey]) {
        paisesReporte[paisKey] = {
          pais: paisInfo.nombre,
          codigo: paisInfo.codigo,
          transacciones: 0,
          ingresos: 0,
          moneda: paisInfo.moneda,
        };
      }
      paisesReporte[paisKey].transacciones += 1;
      paisesReporte[paisKey].ingresos += t.monto || 0;

      // Por plan
      const planKey = planInfo.nombre;
      if (!planesReporte[planKey]) {
        planesReporte[planKey] = {
          plan: planInfo.nombre,
          tipo: planInfo.tipo,
          ventas: 0,
          ingresos: 0,
        };
      }
      planesReporte[planKey].ventas += 1;
      planesReporte[planKey].ingresos += t.monto || 0;

      // Mensual
      const fecha = new Date(t.fecha_pago);
      const mesKey = `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}`;
      const mesNombre = fecha.toLocaleDateString('es-ES', { month: 'short', year: 'numeric' });

      if (!mensualMap[mesKey]) {
        mensualMap[mesKey] = {
          mes: mesNombre,
          anio: fecha.getFullYear(),
          total: 0,
          transacciones: 0,
        };
      }
      mensualMap[mesKey].total += t.monto || 0;
      mensualMap[mesKey].transacciones += 1;
    });

    const paisesArray = Object.values(paisesReporte);
    const planesArray = Object.values(planesReporte);
    const mensualArray = Object.values(mensualMap).sort((a, b) => {
      if (a.anio !== b.anio) return a.anio - b.anio;
      return a.mes.localeCompare(b.mes);
    });

    const totalIngresos = paisesArray.reduce((sum, p) => sum + p.ingresos, 0);

    setReportePaises(paisesArray);
    setReportePlanes(planesArray);
    setReporteMensual(mensualArray);
    setStats({
      totalIngresos,
      totalVentas: paisesArray.reduce((sum, p) => sum + p.transacciones, 0),
      paisesActivos: paisesArray.length,
      planesVendidos: planesArray.length,
      comisionesEstimadas: totalIngresos * 0.05,
    });

    setLoading(false);
  };

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard');
      return;
    }
    cargarDatos();
  }, [adminLoading, isAdmin, navigate, tabActiva, periodo]);

  const getBandera = (codigo: string) => {
    const banderas: Record<string, string> = { GT: '🇬🇹', SV: '🇸🇻', HN: '🇭🇳', CR: '🇨🇷', PA: '🇵🇦', NI: '🇳🇮', MX: '🇲🇽' };
    return banderas[codigo] || '🌎';
  };

  const getTipoColor = (tipo: string) => {
    switch (tipo) {
      case 'medico': return 'bg-blue-100 text-blue-700';
      case 'clinica': return 'bg-indigo-100 text-indigo-700';
      case 'lab': return 'bg-green-100 text-green-700';
      case 'visitador': return 'bg-orange-100 text-orange-700';
      case 'farmaceutico': return 'bg-red-100 text-red-700';
      case 'farmacia': return 'bg-teal-100 text-teal-700';
      case 'publicidad': return 'bg-pink-100 text-pink-700';
      case 'otros': return 'bg-slate-100 text-slate-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  const getTipoIcon = (tipo: string) => {
    switch (tipo) {
      case 'medico': return <Stethoscope className="h-4 w-4" />;
      case 'clinica': return <Home className="h-4 w-4" />;
      case 'lab': return <FlaskConical className="h-4 w-4" />;
      case 'visitador': return <Truck className="h-4 w-4" />;
      case 'farmaceutico': return <Pill className="h-4 w-4" />;
      case 'farmacia': return <Store className="h-4 w-4" />;
      case 'publicidad': return <Megaphone className="h-4 w-4" />;
      case 'otros': return <Briefcase className="h-4 w-4" />;
      default: return <Layers className="h-4 w-4" />;
    }
  };

  const tabInfo = tabs.find(t => t.id === tabActiva) || tabs[0];

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
            <h1 className="text-2xl font-bold">Reportes EZPayConnect</h1>
            <p className="text-sm text-muted-foreground">Métricas de planes, suscripciones e ingresos</p>
          </div>
        </div>
        <Button variant="outline" onClick={cargarDatos}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
      </div>

      {/* Tabs de tipo de plan */}
      <div className="flex flex-wrap gap-2 mb-4">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          return (
            <Button
              key={tab.id}
              variant={tabActiva === tab.id ? 'default' : 'outline'}
              size="sm"
              onClick={() => setTabActiva(tab.id)}
              className={tabActiva === tab.id ? `${tab.color} text-white hover:opacity-90` : ''}
            >
              <Icon className="h-4 w-4 mr-2" />
              {tab.label}
            </Button>
          );
        })}
      </div>

      {/* Selector de periodo */}
      <div className="flex items-center gap-3 mb-6">
        <span className="text-sm text-muted-foreground">Período:</span>
        <div className="flex gap-1 bg-gray-100 p-1 rounded-lg">
          {periodos.map((p) => (
            <Button
              key={p.id}
              variant={periodo === p.id ? 'default' : 'ghost'}
              size="sm"
              onClick={() => setPeriodo(p.id)}
              className={periodo === p.id ? 'bg-[#1E5C8E] text-white' : 'text-gray-600 hover:text-gray-900'}
            >
              {p.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Ingresos</p>
            </div>
            <p className="text-2xl font-bold">${stats.totalIngresos.toFixed(2)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <CreditCard className="h-5 w-5 text-blue-600" />
              <p className="text-sm text-muted-foreground">Ventas</p>
            </div>
            <p className="text-2xl font-bold">{stats.totalVentas}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <MapPin className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Países</p>
            </div>
            <p className="text-2xl font-bold">{stats.paisesActivos}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Users className="h-5 w-5 text-orange-600" />
              <p className="text-sm text-muted-foreground">Planes</p>
            </div>
            <p className="text-2xl font-bold">{stats.planesVendidos}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="h-5 w-5 text-teal-600" />
              <p className="text-sm text-muted-foreground">Comisiones</p>
            </div>
            <p className="text-2xl font-bold">${stats.comisionesEstimadas.toFixed(2)}</p>
          </CardContent>
        </Card>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <RefreshCw className="h-8 w-8 animate-spin text-[#1E5C8E]" />
        </div>
      ) : (
        <>
          {/* Gráfico — Ingresos por país */}
          <Card className="mb-6">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Globe className="h-5 w-5" />
                Ingresos por País — {tabInfo.label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {reportePaises.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  No hay datos de transacciones para {tabInfo.label} en este período
                </div>
              ) : (
                <div className="space-y-4">
                  {reportePaises.map((pais) => {
                    const maxIngresos = Math.max(...reportePaises.map(p => p.ingresos));
                    const porcentaje = maxIngresos > 0 ? (pais.ingresos / maxIngresos) * 100 : 0;
                    return (
                      <div key={pais.pais} className="space-y-1">
                        <div className="flex justify-between items-center">
                          <div className="flex items-center gap-2">
                            <span className="text-lg">{getBandera(pais.codigo)}</span>
                            <span className="font-medium">{pais.pais}</span>
                            <Badge variant="outline" className="text-xs">{pais.moneda}</Badge>
                          </div>
                          <div className="text-right">
                            <span className="font-bold">
                              {pais.moneda === 'GTQ' ? 'Q' : pais.moneda === 'HNL' ? 'L' : pais.moneda === 'CRC' ? '₡' : '$'}
                              {pais.ingresos.toFixed(2)}
                            </span>
                            <span className="text-sm text-muted-foreground ml-1">({pais.transacciones} ventas)</span>
                          </div>
                        </div>
                        <div className="w-full bg-gray-100 rounded-full h-3">
                          <div className={`h-3 rounded-full transition-all duration-500 ${tabInfo.barColor}`} style={{ width: `${porcentaje}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Gráfico — Ventas por plan */}
          <Card className="mb-6">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <BarChart3 className="h-5 w-5" />
                Ventas por Plan — {tabInfo.label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {reportePlanes.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  No hay ventas de planes para {tabInfo.label} en este período
                </div>
              ) : (
                <div className="space-y-4">
                  {reportePlanes.map((plan) => {
                    const maxVentas = Math.max(...reportePlanes.map(p => p.ventas));
                    const porcentaje = maxVentas > 0 ? (plan.ventas / maxVentas) * 100 : 0;
                    return (
                      <div key={plan.plan} className="space-y-1">
                        <div className="flex justify-between items-center">
                          <div className="flex items-center gap-2">
                            <Badge className={getTipoColor(plan.tipo)}>
                              <span className="flex items-center gap-1">
                                {getTipoIcon(plan.tipo)}
                                {plan.tipo}
                              </span>
                            </Badge>
                            <span className="font-medium">{plan.plan}</span>
                          </div>
                          <div className="text-right">
                            <span className="font-bold">{plan.ventas} ventas</span>
                            <span className="text-sm text-muted-foreground ml-1">(${plan.ingresos.toFixed(2)})</span>
                          </div>
                        </div>
                        <div className="w-full bg-gray-100 rounded-full h-3">
                          <div className="bg-emerald-500 h-3 rounded-full transition-all duration-500" style={{ width: `${porcentaje}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Tendencia mensual */}
          <Card className="mb-6">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Calendar className="h-5 w-5" />
                Tendencia Mensual — {tabInfo.label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {reporteMensual.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  No hay datos mensuales para {tabInfo.label}
                </div>
              ) : (
                <div className="space-y-4">
                  {reporteMensual.map((mes) => {
                    const maxTotal = Math.max(...reporteMensual.map(m => m.total));
                    const porcentaje = maxTotal > 0 ? (mes.total / maxTotal) * 100 : 0;
                    return (
                      <div key={mes.mes} className="space-y-1">
                        <div className="flex justify-between items-center">
                          <span className="font-medium">{mes.mes}</span>
                          <div className="text-right">
                            <span className="font-bold">${mes.total.toFixed(2)}</span>
                            <span className="text-sm text-muted-foreground ml-1">({mes.transacciones} trans.)</span>
                          </div>
                        </div>
                        <div className="w-full bg-gray-100 rounded-full h-3">
                          <div className="bg-amber-500 h-3 rounded-full transition-all duration-500" style={{ width: `${porcentaje}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Tabla resumen */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Globe className="h-5 w-5" />
                Resumen Detallado por País — {tabInfo.label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left py-3 px-4">País</th>
                      <th className="text-center py-3 px-4">Transacciones</th>
                      <th className="text-right py-3 px-4">Ingresos</th>
                      <th className="text-right py-3 px-4">Promedio</th>
                      <th className="text-right py-3 px-4">Comisión Est.</th>
                    </tr>
                  </thead>
                  <tbody>
                    {reportePaises.map((pais) => (
                      <tr key={pais.pais} className="border-b hover:bg-gray-50">
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <span className="text-lg">{getBandera(pais.codigo)}</span>
                            <span className="font-medium">{pais.pais}</span>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center">{pais.transacciones}</td>
                        <td className="py-3 px-4 text-right font-semibold">
                          {pais.moneda === 'GTQ' ? 'Q' : pais.moneda === 'HNL' ? 'L' : pais.moneda === 'CRC' ? '₡' : '$'}
                          {pais.ingresos.toFixed(2)}
                        </td>
                        <td className="py-3 px-4 text-right text-muted-foreground">
                          {pais.transacciones > 0 ? (pais.ingresos / pais.transacciones).toFixed(2) : '0.00'}
                        </td>
                        <td className="py-3 px-4 text-right text-muted-foreground">
                          {(pais.ingresos * 0.05).toFixed(2)}
                        </td>
                      </tr>
                    ))}
                    {reportePaises.length === 0 && (
                      <tr>
                        <td colSpan={5} className="text-center py-8 text-muted-foreground">
                          No hay datos para {tabInfo.label} en este período
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}