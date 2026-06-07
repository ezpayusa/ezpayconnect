import { 
  Users, 
  Building2, 
  DollarSign, 
  CreditCard, 
  TrendingUp, 
  TrendingDown,
  Activity,
  Globe
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';

interface AdminStats {
  total_medicos: number;
  total_clinicas: number;
  total_ingresos_mes: number;
  total_transacciones: number;
  medicos_nuevos_mes: number;
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

export default function AdminEzPayPage() {
  const [stats, setStats] = useState<AdminStats>({
    total_medicos: 0,
    total_clinicas: 0,
    total_ingresos_mes: 0,
    total_transacciones: 0,
    medicos_nuevos_mes: 0,
  });
  const [paises, setPaises] = useState<PaisConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const { paisId } = usePaisFiltro();

  useEffect(() => {
    fetchDashboardData();
  }, []);

  const fetchDashboardData = async () => {
    try {
      let medicosQuery = supabase
        .from('perfiles')
        .select('*', { count: 'exact', head: true })
        .eq('rol', 'medico')
      if (paisId) medicosQuery = medicosQuery.eq('pais_id', paisId)
      const { count: medicosCount } = await medicosQuery

      let clinicasQuery = supabase
        .from('perfiles')
        .select('*', { count: 'exact', head: true })
        .eq('rol', 'clinica')
      if (paisId) clinicasQuery = clinicasQuery.eq('pais_id', paisId)
      const { count: clinicasCount } = await clinicasQuery

      const { data: paisesData } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('activo', true);

      setStats({
        total_medicos: medicosCount || 0,
        total_clinicas: clinicasCount || 0,
        total_ingresos_mes: 0,
        total_transacciones: 0,
        medicos_nuevos_mes: 0,
      });

      setPaises(paisesData || []);
    } catch (error) {
      console.error('Error cargando dashboard:', error);
    } finally {
      setLoading(false);
    }
  };

  const statCards = [
    { 
      title: 'Médicos Activos', 
      value: stats.total_medicos, 
      icon: Users, 
      trend: '+12%',
      trendUp: true,
      color: 'bg-[#87CEEB]/10 text-[#1E5C8E]' 
    },
    { 
      title: 'Clínicas Registradas', 
      value: stats.total_clinicas, 
      icon: Building2, 
      trend: '+5%',
      trendUp: true,
      color: 'bg-emerald-50 text-emerald-600' 
    },
    { 
      title: 'Ingresos del Mes', 
      value: `Q${stats.total_ingresos_mes.toLocaleString()}`, 
      icon: DollarSign, 
      trend: '+8%',
      trendUp: true,
      color: 'bg-amber-50 text-amber-600' 
    },
    { 
      title: 'Transacciones', 
      value: stats.total_transacciones, 
      icon: CreditCard, 
      trend: '-2%',
      trendUp: false,
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
                <div className={`flex items-center gap-1 text-xs font-medium ${stat.trendUp ? 'text-emerald-500' : 'text-red-500'}`}>
                  {stat.trendUp ? <TrendingUp size={14} /> : <TrendingDown size={14} />}
                  {stat.trend}
                </div>
              </div>
              <div className="mt-4">
                <p className="text-2xl font-bold text-gray-800">{stat.value}</p>
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
                  <span className="text-2xl">{pais.codigo === 'GT' ? '🇬🇹' : pais.codigo === 'SV' ? '🇸🇻' : '🇭🇳'}</span>
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

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card className="border-0 shadow-md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-[#1E5C8E]">
              <Activity size={20} />
              Actividad Reciente
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {[1, 2, 3, 4, 5].map((_, i) => (
                <div key={i} className="flex items-center gap-3 p-3 rounded-lg hover:bg-gray-50 transition-colors">
                  <div className="w-2 h-2 rounded-full bg-[#87CEEB]"></div>
                  <div className="flex-1">
                    <p className="text-sm font-medium text-gray-800">Nuevo médico registrado</p>
                    <p className="text-xs text-gray-500">Dr. García - Guatemala</p>
                  </div>
                  <span className="text-xs text-gray-400">Hace 2h</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card className="border-0 shadow-md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-[#1E5C8E]">
              <TrendingUp size={20} />
              Crecimiento por País
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {paises.map((pais) => (
                <div key={pais.id}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="font-medium text-gray-700">{pais.nombre}</span>
                    <span className="text-gray-500">65%</span>
                  </div>
                  <div className="w-full bg-gray-100 rounded-full h-2">
                    <div 
                      className="bg-[#87CEEB] h-2 rounded-full transition-all duration-500"
                      style={{ width: `${Math.random() * 40 + 40}%` }}
                    ></div>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}