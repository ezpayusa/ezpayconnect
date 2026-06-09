import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { ArrowLeft, RefreshCw, DollarSign, BarChart3, TrendingUp, Globe, Calendar, Stethoscope, MapPin, FlaskConical, Truck, Layers, CreditCard, Users, Pill, Store, Megaphone, Briefcase, AlertTriangle } from 'lucide-react';

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
  { id: 'clinica', label: 'Planes Clínica', icon: MapPin, color: 'bg-indigo-600', barColor: 'bg-indigo-500' },
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
  { id: 'todos', label: 'Todo el tiempo' },
];

// Función para formatear números con separador de miles
const formatNumber = (num: number, decimals: number = 2): string => {
  return num.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
};

export default function ReportesEzPayPageV2() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [tabActiva, setTabActiva] = useState('todos');
  const [periodo, setPeriodo] = useState('todos');
  const [reportePaises, setReportePaises] = useState<ReportePais[]>([]);
  const [reportePlanes, setReportePlanes] = useState<ReportePlan[]>([]);
  const [reporteMensual, setReporteMensual] = useState<ReporteMensual[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [debugInfo, setDebugInfo] = useState<string>('');
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
      case 'todos': return new Date(2000, 0, 1);
      default: return new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    }
  };

  const formatFechaSupabase = (fecha: Date): string => {
    const year = fecha.getFullYear();
    const month = String(fecha.getMonth() + 1).padStart(2, '0');
    const day = String(fecha.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  };

  const cargarDatos = async () => {
    setLoading(true);
    setErrorMsg(null);
    setDebugInfo('Cargando...');

    const fechaInicio = getFechaInicio();
    const fechaStr = formatFechaSupabase(fechaInicio);

    console.log('📊 Reportes V2 - Llamando edge function...');
    console.log('Periodo:', periodo, '| Tab:', tabActiva, '| Fecha:', fechaStr);

    try {
      const { data, error } = await supabase.functions.invoke('reportes-ezpay', {
        body: {
          periodo,
          tabActiva,
          fechaInicio: periodo !== 'todos' ? fechaStr : null
        }
      });

      if (error) {
        console.error('❌ Error edge function:', error);
        setErrorMsg('Error cargando datos: ' + error.message);
        setLoading(false);
        return;
      }

      console.log('✅ Respuesta edge function:', data);

      if (!data.success) {
        setErrorMsg(data.error || 'Error desconocido');
        setLoading(false);
        return;
      }

      const result = data.data;

      setReportePaises(result.paises || []);
      setReportePlanes(result.planes || []);
      setReporteMensual(result.mensual || []);
      setStats(result.stats || {
        totalIngresos: 0,
        totalVentas: 0,
        paisesActivos: 0,
        planesVendidos: 0,
        comisionesEstimadas: 0,
      });

      const totalTrans = (result.stats?.totalVentas || 0);
      const totalPaises = (result.paises?.length || 0);
      const totalIngresos = (result.stats?.totalIngresos || 0);

      setDebugInfo(`✅ ${totalTrans} transacciones | ${totalPaises} países | $${formatNumber(totalIngresos)}`);

    } catch (err: any) {
      console.error('❌ Error general:', err);
      setErrorMsg('Error inesperado: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard');
      return;
    }
    if (!adminLoading && isAdmin) {
      console.log('🚀 Iniciando carga de reportes...');
      cargarDatos();
    }
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
      case 'clinica': return <MapPin className="h-4 w-4" />;
      case 'lab': return <FlaskConical className="h-4 w-4" />;
      case 'visitador': return <Truck className="h-4 w-4" />;
      case 'farmaceutico': return <Pill className="h-4 w-4" />;
      case 'farmacia': return <Store className="h-4 w-4" />;
      case 'publicidad': return <Megaphone className="h-4 w-4" />;
      case 'otros': return <Briefcase className="h-4 w-4" />;
      default: return <Layers className="h-4 w-4" />;
    }
  };

  const getMonedaSymbol = (moneda: string) => {
    switch (moneda) {
      case 'GTQ': return 'Q';
      case 'HNL': return 'L';
      case 'CRC': return '₡';
      case 'USD': return '$';
      default: return '$';
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
        <div className="flex items-center gap-2">
          {debugInfo && (
            <span className="text-xs text-muted-foreground bg-gray-100 px-2 py-1 rounded">
              {debugInfo}
            </span>
          )}
          <Button variant="outline" onClick={cargarDatos}>
            <RefreshCw className="h-4 w-4 mr-2" /> Recargar
          </Button>
        </div>
      </div>

      {/* Error alert */}
      {errorMsg && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6 flex items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-red-600" />
          <div>
            <p className="font-medium text-red-800">Error al cargar datos</p>
            <p className="text-sm text-red-600">{errorMsg}</p>
          </div>
        </div>
      )}

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
            <p className="text-2xl font-bold">${formatNumber(stats.totalIngresos)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <CreditCard className="h-5 w-5 text-blue-600" />
              <p className="text-sm text-muted-foreground">Ventas</p>
            </div>
            <p className="text-2xl font-bold">{formatNumber(stats.totalVentas, 0)}</p>
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
            <p className="text-2xl font-bold">${formatNumber(stats.comisionesEstimadas)}</p>
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
                  <p className="text-sm mt-2">Periodo: {periodo}</p>
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
                              {getMonedaSymbol(pais.moneda)}{formatNumber(pais.ingresos)}
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
                            <span className="text-sm text-muted-foreground ml-1">(${formatNumber(plan.ingresos)})</span>
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
                            <span className="font-bold">${formatNumber(mes.total)}</span>
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
                          {getMonedaSymbol(pais.moneda)}{formatNumber(pais.ingresos)}
                        </td>
                        <td className="py-3 px-4 text-right text-muted-foreground">
                          {pais.transacciones > 0 ? formatNumber(pais.ingresos / pais.transacciones) : '0.00'}
                        </td>
                        <td className="py-3 px-4 text-right text-muted-foreground">
                          {formatNumber(pais.ingresos * 0.05)}
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
