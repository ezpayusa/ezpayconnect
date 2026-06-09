import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import { usePaisActivo } from '@/hooks/usePaisActivo'
import { supabase } from '@/lib/supabase'
import {
  Users,
  Building,
  Globe,
  Stethoscope,
  ArrowLeft,
  Pill,
  Megaphone,
  Handshake,
  TrendingUp,
  FileText,
  BrainCircuit,
  CreditCard,
  Eye,
  MousePointerClick,
} from 'lucide-react'

interface PaisStats {
  total_medicos: number
  total_clinicas: number
  total_pacientes: number
  total_citas: number
  total_recetas: number
  total_consultas_ia: number
  total_campanas: number
  total_proveedores: number
  total_facturas: number
}

interface CampanaMetrics {
  impresiones: number
  clicks: number
  ctr: number
}

export default function PaisDashboardPage() {
  const navigate = useNavigate()
  const { paisId } = useParams<{ paisId: string }>()
  const { isAdmin, loading: adminLoading } = useAdminAuth()
  const { paisActivo, setPaisActivo, clearPaisActivo } = usePaisActivo()
  const [campanaMetrics, setCampanaMetrics] = useState<CampanaMetrics>({
    impresiones: 0,
    clicks: 0,
    ctr: 0,
  })
  const [stats, setStats] = useState<PaisStats>({
    total_medicos: 0,
    total_clinicas: 0,
    total_pacientes: 0,
    total_citas: 0,
    total_recetas: 0,
    total_consultas_ia: 0,
    total_campanas: 0,
    total_proveedores: 0,
    total_facturas: 0,
  })
  const [paisInfo, setPaisInfo] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard')
    }
  }, [adminLoading, isAdmin, navigate])

  // Cargar info del país y guardar en contexto
  useEffect(() => {
    if (!paisId) return

    const cargarPais = async () => {
      const { data } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('id', paisId)
        .single()

      if (data) {
        setPaisInfo(data)
        setPaisActivo(data)
      } else {
        navigate('/admin-ezpay/paises')
      }
    }

    cargarPais()
  }, [paisId, navigate, setPaisActivo])

  // Cargar stats filtradas por país
  useEffect(() => {
    if (!paisId) return

    const cargarStats = async () => {
      setLoading(true)
      try {
        const { data: medicosCount } = await supabase
          .rpc('contar_medicos_por_pais', { p_pais_id: paisId })

        const { count: clinicasCount } = await supabase
          .from('clinicas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: pacientesCount } = await supabase
          .from('pacientes')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: citasCount } = await supabase
          .from('citas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: campanasCount } = await supabase
          .from('campanas_publicitarias')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: proveedoresCount } = await supabase
          .from('empresas_proveedoras')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: recetasCount } = await supabase
          .from('recetas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        const { count: facturasCount } = await supabase
          .from('facturas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)

        // Consultas IA: por ahora usamos notificaciones o un contador futuro
        // Placeholder: contaremos consultas_profesional como proxy
        const { count: consultasCount } = await supabase
          .from('consultas_profesional')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
          .catch(() => ({ count: 0 }))

        // Métricas de campañas
        const { data: metricasData } = await supabase
          .from('campana_metricas')
          .select('clickeado')
          .eq('pais_id', paisId)
          .catch(() => ({ data: [] }))

        const impresiones = (metricasData || []).filter((m: any) => !m.clickeado).length
        const clicks = (metricasData || []).filter((m: any) => m.clickeado).length
        const ctr = impresiones > 0 ? Math.round((clicks / impresiones) * 100 * 100) / 100 : 0

        setCampanaMetrics({ impresiones, clicks, ctr })

        setStats({
          total_medicos: medicosCount || 0,
          total_clinicas: clinicasCount || 0,
          total_pacientes: pacientesCount || 0,
          total_citas: citasCount || 0,
          total_recetas: recetasCount || 0,
          total_consultas_ia: consultasCount || 0,
          total_campanas: campanasCount || 0,
          total_proveedores: proveedoresCount || 0,
          total_facturas: facturasCount || 0,
        })
      } catch (error) {
        console.error('Error cargando stats:', error)
      } finally {
        setLoading(false)
      }
    }

    cargarStats()
  }, [paisId])

  const handleVolverPaises = () => {
    clearPaisActivo()
    navigate('/admin-ezpay/paises')
  }

  if (adminLoading || loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!isAdmin) return null

  const statCards = [
    {
      title: 'Clínicas',
      value: stats.total_clinicas,
      icon: Building,
      color: 'bg-emerald-50 text-emerald-600',
      path: `/admin-ezpay/pais/${paisId}/invitaciones-clinicas`,
    },
    {
      title: 'Médicos Activos',
      value: stats.total_medicos,
      icon: Stethoscope,
      color: 'bg-[#87CEEB]/10 text-[#1E5C8E]',
    },
    {
      title: 'Pacientes',
      value: stats.total_pacientes,
      icon: Users,
      color: 'bg-blue-50 text-blue-600',
    },
    {
      title: 'Citas Agendadas',
      value: stats.total_citas,
      icon: TrendingUp,
      color: 'bg-amber-50 text-amber-600',
    },
    {
      title: 'Recetas Generadas',
      value: stats.total_recetas,
      icon: FileText,
      color: 'bg-cyan-50 text-cyan-600',
    },
    {
      title: 'Consultas IA',
      value: stats.total_consultas_ia,
      icon: BrainCircuit,
      color: 'bg-violet-50 text-violet-600',
    },
    {
      title: 'Facturas Emitidas',
      value: stats.total_facturas,
      icon: CreditCard,
      color: 'bg-orange-50 text-orange-600',
    },
    {
      title: 'Campañas',
      value: stats.total_campanas,
      icon: Megaphone,
      color: 'bg-purple-50 text-purple-600',
    },
    {
      title: 'Proveedores',
      value: stats.total_proveedores,
      icon: Handshake,
      color: 'bg-rose-50 text-rose-600',
    },
  ]

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <div className="flex items-center gap-3 mb-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={handleVolverPaises}
              className="text-[#1E5C8E]"
            >
              <ArrowLeft className="w-4 h-4 mr-1" />
              Países
            </Button>
          </div>
          <h1 className="text-2xl font-bold text-[#1E5C8E]">
            {paisInfo?.nombre || 'País'}
          </h1>
          <p className="text-sm text-gray-500">
            Código: {paisInfo?.codigo} | Moneda: {paisInfo?.moneda}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Globe className="w-5 h-5 text-[#1E5C8E]" />
          <span className="text-sm font-medium text-[#1E5C8E]">
            Administrando: {paisInfo?.nombre}
          </span>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        {statCards.map((card) => {
          const Icon = card.icon
          return (
            <Card
              key={card.title}
              className="cursor-pointer hover:shadow-md transition-shadow"
              onClick={() => navigate(card.path)}
            >
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-500">{card.title}</p>
                    <p className="text-2xl font-bold mt-1">{card.value}</p>
                  </div>
                  <div className={`p-3 rounded-lg ${card.color}`}>
                    <Icon className="w-6 h-6" />
                  </div>
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>

      {/* Métricas de Campañas */}
      <Card className="mb-8">
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <Megaphone className="w-5 h-5 text-purple-600" />
            Campañas Publicitarias
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 rounded-lg">
                <Eye className="w-5 h-5 text-blue-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Impresiones</p>
                <p className="text-xl font-bold">{campanaMetrics.impresiones.toLocaleString()}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-emerald-100 rounded-lg">
                <MousePointerClick className="w-5 h-5 text-emerald-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Clicks</p>
                <p className="text-xl font-bold">{campanaMetrics.clicks.toLocaleString()}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-amber-100 rounded-lg">
                <TrendingUp className="w-5 h-5 text-amber-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">CTR</p>
                <p className="text-xl font-bold">{campanaMetrics.ctr}%</p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Acciones rápidas */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Acciones Rápidas</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-3">
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/pais/${paisId}/clinicas`)}
          >
            <Building className="w-4 h-4 mr-2" />
            Ver Clínicas
          </Button>
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/pais/${paisId}/invitaciones-clinicas`)}
          >
            <Building className="w-4 h-4 mr-2" />
            Invitar Clínica
          </Button>
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/campanas-publicitarias`)}
          >
            <Megaphone className="w-4 h-4 mr-2" />
            Campañas
          </Button>
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/solicitudes-campana`)}
          >
            <Pill className="w-4 h-4 mr-2" />
            Solicitudes
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
