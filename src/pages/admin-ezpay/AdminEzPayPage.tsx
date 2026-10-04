import { 
  Users, 
  MapPin, 
  DollarSign, 
  CreditCard, 
  Globe
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { formatearMonto } from '@/lib/moneda';

// null = la consulta falló: la tarjeta muestra "—", nunca un 0 como dato.
interface AdminStats {
  total_medicos: number | null;
  total_clinicas: number | null;
  // monto verificado del mes por moneda (no se suman monedas distintas)
  ingresos_mes: { moneda: string; monto: number }[] | null;
  pagos_verificados_mes: number | null;
}

interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}

// Deriva el emoji de bandera desde el código ISO de 2 letras (regional indicator symbols).
// Sirve para los 19 países sin hardcodear cada uno. Fallback 🌐 si el código no es válido.
function codigoABandera(codigo?: string): string {
  if (!codigo || codigo.length < 2) return '🌐'
  const cc = codigo.trim().slice(0, 2).toUpperCase()
  if (!/^[A-Z]{2}$/.test(cc)) return '🌐'
  const base = 0x1f1e6 // 'A' regional indicator
  return String.fromCodePoint(
    base + (cc.charCodeAt(0) - 65),
    base + (cc.charCodeAt(1) - 65),
  )
}

export default function AdminEzPayPage() {
  const [stats, setStats] = useState<AdminStats>({
    total_medicos: null,
    total_clinicas: null,
    ingresos_mes: null,
    pagos_verificados_mes: null,
  });
  const [paises, setPaises] = useState<PaisConfig[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchDashboardData();
  }, []);

  // Vista GLOBAL (super_admin): sin filtro de país.
  const fetchDashboardData = async () => {
    try {
      const { count: clinicasCount, error: errClinicas } = await supabase
        .from('clinicas')
        .select('id', { count: 'exact', head: true })
      if (errClinicas) console.error('[dashboard-maestro] no se pudieron contar las clínicas:', errClinicas.code)

      const { count: medicosCount, error: errMedicos } = await supabase
        .from('medicos')
        .select('id', { count: 'exact', head: true })
        .eq('activo', true)
      if (errMedicos) console.error('[dashboard-maestro] no se pudieron contar los médicos:', errMedicos.code)

      // Mes actual: medianoche local del día 1 → medianoche local del día 1 del mes siguiente (timestamptz).
      const ahora = new Date()
      const inicioMes = new Date(ahora.getFullYear(), ahora.getMonth(), 1)
      const inicioMesSiguiente = new Date(ahora.getFullYear(), ahora.getMonth() + 1, 1)
      const { data: pagosData, count: pagosCount, error: errPagos } = await supabase
        .from('pagos_proveedor')
        .select('monto, moneda', { count: 'exact' })
        .eq('estado', 'verificado')
        .gte('fecha_verificacion', inicioMes.toISOString())
        .lt('fecha_verificacion', inicioMesSiguiente.toISOString())
      if (errPagos) console.error('[dashboard-maestro] no se pudieron cargar los pagos verificados:', errPagos.code)

      let ingresosMes: AdminStats['ingresos_mes'] = null
      if (!errPagos) {
        const porMoneda = new Map<string, number>()
        for (const p of (pagosData || []) as { monto: number | string | null; moneda: string | null }[]) {
          const moneda = (p.moneda || '').trim().toUpperCase()
          porMoneda.set(moneda, (porMoneda.get(moneda) || 0) + (Number(p.monto) || 0))
        }
        ingresosMes = [...porMoneda.entries()]
          .map(([moneda, monto]) => ({ moneda, monto }))
          .sort((a, b) => a.moneda.localeCompare(b.moneda))
      }

      const { data: paisesData, error: errPaises } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('activo', true);
      if (errPaises) console.error('[dashboard-maestro] no se pudieron cargar los países:', errPaises.code)

      setStats({
        total_clinicas: errClinicas ? null : clinicasCount ?? 0,
        total_medicos: errMedicos ? null : medicosCount ?? 0,
        ingresos_mes: ingresosMes,
        pagos_verificados_mes: errPagos ? null : pagosCount ?? 0,
      });

      setPaises(paisesData || []);
    } catch (error) {
      console.error('[dashboard-maestro] error cargando el dashboard:', (error as { code?: string } | null)?.code ?? 'sin code');
    } finally {
      setLoading(false);
    }
  };

  const valor = (n: number | null) => (n === null ? '—' : n)
  const ingresosTexto = stats.ingresos_mes === null
    ? '—'
    : stats.ingresos_mes.length === 0
      ? 'Sin ingresos este mes'
      : stats.ingresos_mes.map((i) => formatearMonto(i.monto, i.moneda)).join('\n')

  const statCards = [
    { 
      title: 'Médicos Activos', 
      value: valor(stats.total_medicos), 
      icon: Users, 
      color: 'bg-[#87CEEB]/10 text-[#1E5C8E]' 
    },
    { 
      title: 'Clínicas Registradas', 
      value: valor(stats.total_clinicas), 
      icon: MapPin, 
      color: 'bg-emerald-50 text-emerald-600' 
    },
    { 
      title: 'Ingresos del Mes', 
      value: ingresosTexto, 
      icon: DollarSign, 
      color: 'bg-amber-50 text-amber-600' 
    },
    { 
      title: 'Pagos verificados (mes)', 
      value: valor(stats.pagos_verificados_mes), 
      icon: CreditCard, 
      color: 'bg-purple-50 text-purple-600' 
    },
  ];

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#87CEEB]"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1E5C8E]">Dashboard Maestro</h1>
        <p className="text-gray-500 mt-1">Vista general de EZPayConnect</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {statCards.map((stat, index) => (
          <Card key={index} className="border-0 shadow-md hover:shadow-lg transition-shadow">
            <CardContent className="p-6">
              <div className="flex items-start justify-between">
                <div className={`p-3 rounded-xl ${stat.color}`}>
                  <stat.icon size={24} />
                </div>
              </div>
              <div className="mt-4">
                {/* whitespace-pre-line: los ingresos van una línea por moneda */}
                <p className="text-2xl font-bold text-gray-800 whitespace-pre-line">{stat.value}</p>
                <p className="text-sm text-gray-500 mt-1">{stat.title}</p>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card className="border-0 shadow-md">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-[#1E5C8E]">
            <Globe size={20} />
            Países Activos
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {paises.map((pais) => (
              <div 
                key={pais.id} 
                className="p-4 rounded-xl bg-gradient-to-br from-white to-gray-50 border border-gray-100 hover:border-[#87CEEB] transition-all cursor-pointer"
              >
                <div className="flex items-center justify-between mb-3">
                  <span className="text-2xl">{codigoABandera(pais.codigo)}</span>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${pais.comisiones_activas ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-600'}`}>
                    {pais.comisiones_activas ? 'Comisiones ON' : 'Sin comisiones'}
                  </span>
                </div>
                <h3 className="font-semibold text-gray-800">{pais.nombre}</h3>
                <p className="text-sm text-gray-500">Moneda: {pais.moneda}</p>
                {pais.comisiones_activas && (
                  <p className="text-sm text-[#1E5C8E] font-medium mt-1">
                    Comisión: {pais.porcentaje_comision_default}%
                  </p>
                )}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
