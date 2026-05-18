import { useState, useEffect } from 'react';
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
  BarChart3, 
  PieChart, 
  TrendingUp, 
  Globe,
  Calendar,
  DollarSign
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

export default function ReportesPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [reportePaises, setReportePaises] = useState<ReportePais[]>([]);
  const [reportePlanes, setReportePlanes] = useState<ReportePlan[]>([]);
  const [reporteMensual, setReporteMensual] = useState<ReporteMensual[]>([]);
  const [loading, setLoading] = useState(true);
  const [periodo, setPeriodo] = useState('ultimos_30');

  const cargarDatos = async () => {
    setLoading(true);

    // Calcular fecha de inicio según periodo
    let fechaInicio = new Date();
    switch (periodo) {
      case 'ultimos_7': fechaInicio.setDate(fechaInicio.getDate() - 7); break;
      case 'ultimos_30': fechaInicio.setDate(fechaInicio.getDate() - 30); break;
      case 'ultimos_90': fechaInicio.setDate(fechaInicio.getDate() - 90); break;
      case 'este_anio': fechaInicio = new Date(new Date().getFullYear(), 0, 1); break;
      default: fechaInicio.setDate(fechaInicio.getDate() - 30);
    }

    // Reporte por país
    const { data: paisesData } = await supabase
      .from('transacciones')
      .select(`
        pais_id,
        monto,
        estado,
        configuracion_pais!inner(nombre, codigo, moneda)
      `)
      .eq('estado', 'completado')
      .gte('fecha_pago', fechaInicio.toISOString());

    const paisesMap: Record<string, ReportePais> = {};
    (paisesData || []).forEach((t: any) => {
      const key = t.configuracion_pais.nombre;
      if (!paisesMap[key]) {
        paisesMap[key] = {
          pais: t.configuracion_pais.nombre,
          codigo: t.configuracion_pais.codigo,
          transacciones: 0,
          ingresos: 0,
          moneda: t.configuracion_pais.moneda,
        };
      }
      paisesMap[key].transacciones += 1;
      paisesMap[key].ingresos += t.monto;
    });
    setReportePaises(Object.values(paisesMap));

    // Reporte por plan
    const { data: planesData } = await supabase
      .from('transacciones')
      .select(`
        plan_id,
        monto,
        estado,
        planes_base!inner(nombre, tipo)
      `)
      .eq('estado', 'completado')
      .gte('fecha_pago', fechaInicio.toISOString());

    const planesMap: Record<string, ReportePlan> = {};
    (planesData || []).forEach((t: any) => {
      const key = t.planes_base.nombre;
      if (!planesMap[key]) {
        planesMap[key] = {
          plan: t.planes_base.nombre,
          tipo: t.planes_base.tipo,
          ventas: 0,
          ingresos: 0,
        };
      }
      planesMap[key].ventas += 1;
      planesMap[key].ingresos += t.monto;
    });
    setReportePlanes(Object.values(planesMap));

    // Reporte mensual (últimos 6 meses)
    const { data: mensualData } = await supabase
      .from('transacciones')
      .select('monto, fecha_pago, estado')
      .eq('estado', 'completado')
      .gte('fecha_pago', new Date(new Date().getFullYear(), new Date().getMonth() - 5, 1).toISOString());

    const mensualMap: Record<string, ReporteMensual> = {};
    (mensualData || []).forEach((t: any) => {
      const fecha = new Date(t.fecha_pago);
      const key = `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}`;
      const mesNombre = fecha.toLocaleDateString('es-ES', { month: 'short', year: 'numeric' });

      if (!mensualMap[key]) {
        mensualMap[key] = {
          mes: mesNombre,
          anio: fecha.getFullYear(),
          total: 0,
          transacciones: 0,
        };
      }
      mensualMap[key].total += t.monto;
      mensualMap[key].transacciones += 1;
    });
    setReporteMensual(Object.values(mensualMap).sort((a, b) => a.anio - b.anio || a.mes.localeCompare(b.mes)));

    setLoading(false);
  };

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard');
      return;
    }
    cargarDatos();
  }, [adminLoading, isAdmin, navigate, periodo]);

  const getTipoColor = (tipo: string) => {
    switch (tipo) {
      case 'medico': return 'bg-blue-100 text-blue-700';
      case 'clinica': return 'bg-indigo-100 text-indigo-700';
      case 'lab': return 'bg-green-100 text-green-700';
      case 'visitador': return 'bg-orange-100 text-orange-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  const getBandera = (codigo: string) => {
    const banderas: Record<string, string> = { GT: '🇬🇹', SV: '🇸🇻', HN: '🇭🇳', CR: '🇨🇷', PA: '🇵🇦', NI: '🇳🇮', MX: '🇲🇽' };
    return banderas[codigo] || '🌎';
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
            <h1 className="text-2xl font-bold">Reportes</h1>
            <p className="text-sm text-muted-foreground">Analytics y métricas de EZPayConnect</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Select value={periodo} onValueChange={setPeriodo}>
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="ultimos_7">Últimos 7 días</SelectItem>
              <SelectItem value="ultimos_30">Últimos 30 días</SelectItem>
              <SelectItem value="ultimos_90">Últimos 90 días</SelectItem>
              <SelectItem value="este_anio">Este año</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" onClick={cargarDatos}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
        </div>
      </div>

      {/* Stats rápidas */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <DollarSign className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Ingresos Totales</p>
            </div>
            <p className="text-2xl font-bold">
              ${reportePaises.reduce((sum, p) => sum + p.ingresos, 0).toFixed(2)}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <BarChart3 className="h-5 w-5 text-blue-600" />
              <p className="text-sm text-muted-foreground">Total Ventas</p>
            </div>
            <p className="text-2xl font-bold">
              {reportePaises.reduce((sum, p) => sum + p.transacciones, 0)}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Globe className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Países Activos</p>
            </div>
            <p className="text-2xl font-bold">{reportePaises.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <PieChart className="h-5 w-5 text-orange-600" />
              <p className="text-sm text-muted-foreground">Planes Vendidos</p>
            </div>
            <p className="text-2xl font-bold">{reportePlanes.length}</p>
          </CardContent>
        </Card>
      </div>

      {/* Gráfico de barras — Ingresos por país */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <Globe className="h-5 w-5" />
            Ingresos por País
          </CardTitle>
        </CardHeader>
        <CardContent>
          {reportePaises.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No hay datos para el periodo seleccionado</div>
          ) : (
            <div className="space-y-4">
              {reportePaises.map((pais) => {
                const maxIngresos = Math.max(...reportePaises.map(p => p.ingresos));
                const porcentaje = (pais.ingresos / maxIngresos) * 100;
                return (
                  <div key={pais.pais} className="space-y-1">
                    <div className="flex justify-between items-center">
                      <div className="flex items-center gap-2">
                        <span className="text-lg">{getBandera(pais.codigo)}</span>
                        <span className="font-medium">{pais.pais}</span>
                        <Badge variant="outline" className="text-xs">{pais.moneda}</Badge>
                      </div>
                      <div className="text-right">
                        <span className="font-bold">{pais.ingresos.toFixed(2)}</span>
                        <span className="text-sm text-muted-foreground ml-1">({pais.transacciones} ventas)</span>
                      </div>
                    </div>
                    <div className="w-full bg-gray-100 rounded-full h-3">
                      <div 
                        className="bg-[#1E5C8E] h-3 rounded-full transition-all duration-500"
                        style={{ width: `${porcentaje}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Gráfico de barras — Ventas por plan */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <PieChart className="h-5 w-5" />
            Ventas por Plan
          </CardTitle>
        </CardHeader>
        <CardContent>
          {reportePlanes.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No hay datos para el periodo seleccionado</div>
          ) : (
            <div className="space-y-4">
              {reportePlanes.map((plan) => {
                const maxVentas = Math.max(...reportePlanes.map(p => p.ventas));
                const porcentaje = (plan.ventas / maxVentas) * 100;
                return (
                  <div key={plan.plan} className="space-y-1">
                    <div className="flex justify-between items-center">
                      <div className="flex items-center gap-2">
                        <Badge className={getTipoColor(plan.tipo)}>{plan.tipo}</Badge>
                        <span className="font-medium">{plan.plan}</span>
                      </div>
                      <div className="text-right">
                        <span className="font-bold">{plan.ventas} ventas</span>
                        <span className="text-sm text-muted-foreground ml-1">(${plan.ingresos.toFixed(2)})</span>
                      </div>
                    </div>
                    <div className="w-full bg-gray-100 rounded-full h-3">
                      <div 
                        className="bg-green-500 h-3 rounded-full transition-all duration-500"
                        style={{ width: `${porcentaje}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Gráfico de línea — Ingresos mensuales */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <TrendingUp className="h-5 w-5" />
            Tendencia Mensual
          </CardTitle>
        </CardHeader>
        <CardContent>
          {reporteMensual.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No hay datos mensuales</div>
          ) : (
            <div className="space-y-4">
              {reporteMensual.map((mes) => {
                const maxTotal = Math.max(...reporteMensual.map(m => m.total));
                const porcentaje = (mes.total / maxTotal) * 100;
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
                      <div 
                        className="bg-amber-500 h-3 rounded-full transition-all duration-500"
                        style={{ width: `${porcentaje}%` }}
                      />
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
            <Calendar className="h-5 w-5" />
            Resumen Detallado por País
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
                  </tr>
                ))}
                {reportePaises.length === 0 && (
                  <tr>
                    <td colSpan={4} className="text-center py-8 text-muted-foreground">
                      No hay datos para el periodo seleccionado
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}