import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import { usePaisActivo } from '@/hooks/usePaisActivo'
import { supabase } from '@/lib/supabase'
import { hoyISO } from '@/lib/fecha'
import {
  Users,
  MapPin,
  Globe,
  Stethoscope,
  ArrowLeft,
  Pill,
  Megaphone,
  Handshake,
  TrendingUp,
  FileText,
  CreditCard,
  Eye,
  MousePointerClick,
  CheckCircle2,
} from 'lucide-react'

// null = la consulta falló: la tarjeta muestra "—", nunca un 0 como dato.
interface PaisStats {
  total_medicos: number | null
  total_clinicas: number | null
  total_pacientes: number | null
  total_citas: number | null
  total_recetas: number | null
  total_campanas: number | null
  total_proveedores: number | null
  total_facturas: number | null
  total_confirmaciones: number | null
}

interface CampanaMetrics {
  impresiones: number | null
  clicks: number | null
  ctr: number | null
}

// Error de una consulta del dashboard: mensaje fijo + code (sin datos de la fila).
function logError(que: string, error: { code?: string } | null) {
  if (error) console.error(`[dashboard-pais] no se pudo cargar ${que}:`, error.code ?? 'sin code')
}

const mostrar = (n: number | null) => (n === null ? '—' : n.toLocaleString())

export default function PaisDashboardPage() {
  const navigate = useNavigate()
  const { paisId } = useParams<{ paisId: string }>()
  const { isAdmin, loading: adminLoading } = useAdminAuth()
  const { paisActivo, setPaisActivo, clearPaisActivo } = usePaisActivo()
  const [campanaMetrics, setCampanaMetrics] = useState<CampanaMetrics>({
    impresiones: null,
    clicks: null,
    ctr: null,
  })
  const [desgloseCampanas, setDesgloseCampanas] = useState<any[]>([])
  const [stats, setStats] = useState<PaisStats>({
    total_medicos: null,
    total_clinicas: null,
    total_pacientes: null,
    total_citas: null,
    total_recetas: null,
    total_campanas: null,
    total_proveedores: null,
    total_facturas: null,
    total_confirmaciones: null,
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
      const { data, error } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('id', paisId)
        .single()
      logError('el país', error)

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
        const { data: medicosCount, error: errMedicos } = await supabase
          .rpc('contar_medicos_por_pais', { p_pais_id: paisId })
        logError('los médicos', errMedicos)

        const { count: clinicasCount, error: errClinicas } = await supabase
          .from('clinicas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('las clínicas', errClinicas)

        const { count: pacientesCount, error: errPacientes } = await supabase
          .from('pacientes')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('los pacientes', errPacientes)

        const { count: citasCount, error: errCitas } = await supabase
          .from('citas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('las citas', errCitas)

        const { count: campanasCount, error: errCampanas } = await supabase
          .from('campanas_publicitarias')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('las campañas', errCampanas)

        // RPC con gate de país (mig 363): el admin_pais no ve empresas_proveedoras por RLS.
        const { data: proveedoresCount, error: errProveedores } = await supabase
          .rpc('contar_proveedores_por_pais', { p_pais_id: paisId })
        logError('los proveedores', errProveedores)

        const { count: recetasCount, error: errRecetas } = await supabase
          .from('recetas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('las recetas', errRecetas)

        const { count: facturasCount, error: errFacturas } = await supabase
          .from('facturas')
          .select('*', { count: 'exact', head: true })
          .eq('pais_id', paisId)
        logError('las facturas', errFacturas)

        // Métricas de campañas (RPC país SECURITY DEFINER; gate super_admin / admin_pais-de-este-país).
        const { data: metricasData, error: errMetricas } = await supabase.rpc('metricas_campana_pais', { p_pais_id: paisId })
        logError('las métricas de campañas', errMetricas)

        if (errMetricas) {
          setCampanaMetrics({ impresiones: null, clicks: null, ctr: null })
          setDesgloseCampanas([])
        } else {
          const impresiones = (metricasData || []).reduce((a: number, r: any) => a + (Number(r.impresiones) || 0), 0)
          const clicks = (metricasData || []).reduce((a: number, r: any) => a + (Number(r.clicks) || 0), 0)
          const ctr = impresiones > 0 ? Math.round((clicks / impresiones) * 100 * 100) / 100 : 0
          setCampanaMetrics({ impresiones, clicks, ctr })
          setDesgloseCampanas((metricasData || []) as any[])
        }

        // Confirmaciones de recepción de receta (acumulado histórico → hoy), país-scoped.
        const hoyStr = hoyISO() // p_hasta es DATE: día LOCAL
        const { data: confData, error: errConf } = await supabase
          .rpc('reporte_confirmaciones_pais', {
            p_desde: '2020-01-01',
            p_hasta: hoyStr,
            p_pais_id: paisId,
          })
        logError('las confirmaciones', errConf)
        // la RPC devuelve filas por país; para este dashboard (un país fijo) sumamos el conteo (0 filas → 0)
        const confirmacionesCount = (confData ?? []).reduce(
          (acc: number, r: any) => acc + Number(r.confirmaciones ?? 0), 0
        )

        setStats({
          total_medicos: errMedicos ? null : Number(medicosCount ?? 0),
          total_clinicas: errClinicas ? null : clinicasCount ?? 0,
          total_pacientes: errPacientes ? null : pacientesCount ?? 0,
          total_citas: errCitas ? null : citasCount ?? 0,
          total_recetas: errRecetas ? null : recetasCount ?? 0,
          total_campanas: errCampanas ? null : campanasCount ?? 0,
          total_proveedores: errProveedores ? null : Number(proveedoresCount ?? 0),
          total_facturas: errFacturas ? null : facturasCount ?? 0,
          total_confirmaciones: errConf ? null : confirmacionesCount,
        })
      } catch (error) {
        console.error('[dashboard-pais] error cargando las estadísticas:', (error as { code?: string } | null)?.code ?? 'sin code')
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

  const statCards: { title: string; value: number | null; icon: typeof MapPin; color: string; path?: string }[] = [
    {
      title: 'Clínicas',
      value: stats.total_clinicas,
      icon: MapPin,
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
      title: 'Citas',
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
      title: 'Confirmaciones',
      value: stats.total_confirmaciones,
      icon: CheckCircle2,
      color: 'bg-teal-50 text-teal-600',
    },
    {
      title: 'Facturas',
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
              // solo navegan las tarjetas con path
              className={card.path ? 'cursor-pointer hover:shadow-md transition-shadow' : undefined}
              onClick={card.path ? () => navigate(card.path!) : undefined}
            >
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-500">{card.title}</p>
                    <p className="text-2xl font-bold mt-1">{mostrar(card.value)}</p>
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
                <p className="text-xl font-bold">{mostrar(campanaMetrics.impresiones)}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-emerald-100 rounded-lg">
                <MousePointerClick className="w-5 h-5 text-emerald-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Clicks</p>
                <p className="text-xl font-bold">{mostrar(campanaMetrics.clicks)}</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-amber-100 rounded-lg">
                <TrendingUp className="w-5 h-5 text-amber-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">CTR</p>
                <p className="text-xl font-bold">{campanaMetrics.ctr === null ? '—' : `${campanaMetrics.ctr}%`}</p>
              </div>
            </div>
          </div>

          {/* Desglose por empresa (para mostrar a clientes) */}
          {(() => {
            const grupos = new Map<string, { nombre: string; tipo: string | null; campanas: any[]; imp: number; clk: number; usu: number }>()
            for (const c of desgloseCampanas) {
              const key = c.empresa_id || '__ezpay__'
              if (!grupos.has(key)) {
                grupos.set(key, {
                  nombre: c.empresa_nombre || 'EzPay / anuncios propios',
                  tipo: c.empresa_id ? (c.empresa_tipo || null) : null,
                  campanas: [], imp: 0, clk: 0, usu: 0,
                })
              }
              const g = grupos.get(key)!
              g.campanas.push(c)
              g.imp += Number(c.impresiones) || 0
              g.clk += Number(c.clicks) || 0
              g.usu += Number(c.usuarios_unicos) || 0
            }
            const secciones = [...grupos.values()].sort((a, b) => b.imp - a.imp)
            if (secciones.length === 0) {
              return <p className="text-sm text-gray-400 mt-6">Sin campañas en este país.</p>
            }
            return (
              <div className="mt-6 space-y-4">
                <p className="text-sm font-semibold text-gray-700">Desglose por empresa</p>
                {secciones.map((g, i) => (
                  <div key={i} className="border rounded-lg overflow-hidden">
                    <div className="flex items-center justify-between bg-gray-50 px-4 py-2 border-b">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-gray-800">{g.nombre}</span>
                        {g.tipo && <span className="text-xs px-2 py-0.5 rounded-full bg-blue-100 text-blue-700">{g.tipo}</span>}
                      </div>
                      <div className="text-xs text-gray-600">
                        {g.imp.toLocaleString()} impr · {g.clk.toLocaleString()} clics · {g.usu.toLocaleString()} usuarios
                      </div>
                    </div>
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="text-left text-gray-500 border-b">
                          <th className="px-4 py-2 font-medium">Campaña</th>
                          <th className="px-3 py-2 font-medium text-right">Impresiones</th>
                          <th className="px-3 py-2 font-medium text-right">Clics</th>
                          <th className="px-3 py-2 font-medium text-right">Usuarios únicos</th>
                        </tr>
                      </thead>
                      <tbody>
                        {g.campanas.map((c: any) => (
                          <tr key={c.campana_id} className="border-b last:border-0">
                            <td className="px-4 py-2 text-gray-800">{c.titulo}</td>
                            <td className="px-3 py-2 text-right">{(Number(c.impresiones) || 0).toLocaleString()}</td>
                            <td className="px-3 py-2 text-right">{(Number(c.clicks) || 0).toLocaleString()}</td>
                            <td className="px-3 py-2 text-right">{(Number(c.usuarios_unicos) || 0).toLocaleString()}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ))}
              </div>
            )
          })()}
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
            <MapPin className="w-4 h-4 mr-2" />
            Ver Clínicas
          </Button>
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/pais/${paisId}/invitaciones-clinicas`)}
          >
            <MapPin className="w-4 h-4 mr-2" />
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
          {/* Fichas de asesor (D12). Nace CON link: prospectos y material siguen sin entrada de
              navegación y eso es el pendiente #8, no se arregla acá. */}
          <Button
            variant="outline"
            onClick={() => navigate(`/admin-ezpay/pais/${paisId}/asesores`)}
          >
            <MapPin className="w-4 h-4 mr-2" />
            Fichas de asesor
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
