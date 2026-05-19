// src/pages/admin-ezpay/ReportesPage.tsx
// Dia 16: Pagina de Reportes Avanzados — Version robusta
// EzPayConnect — Admin Dashboard

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import { 
  BarChart3, 
  Download, 
  Calendar, 
  Users, 
  Stethoscope, 
  FileText, 
  ChevronDown,
  Filter,
  RefreshCw,
  TrendingUp,
  AlertCircle
} from 'lucide-react'

const EDGE_FUNCTION_URL = 'https://fqnsmvkxsuujahhmpzuk.supabase.co/functions/v1'

interface ResumenMensual {
  mes: string
  total_citas: number
  citas_atendidas: number
  citas_canceladas: number
  citas_pendientes: number
  pacientes_nuevos: number
  recetas_emitidas: number
}

interface KPIs {
  total_pacientes: number
  total_medicos: number
  citas_hoy: number
  recetas_total: number
}

interface DetalleItem {
  id: string
  [key: string]: any
}

export default function ReportesPage() {
  const { perfil, isAdmin, loading: authLoading } = useAdminAuth()
  const [activeTab, setActiveTab] = useState<'resumen' | 'detalle'>('resumen')
  const [tipoReporte, setTipoReporte] = useState('citas')
  const [fechaDesde, setFechaDesde] = useState('')
  const [fechaHasta, setFechaHasta] = useState('')
  const [estado, setEstado] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const [resumenData, setResumenData] = useState<ResumenMensual[]>([])
  const [kpis, setKpis] = useState<KPIs | null>(null)
  const [detalleData, setDetalleData] = useState<DetalleItem[]>([])
  const [pagination, setPagination] = useState({ total: 0, limit: 50, offset: 0, has_more: false })

  useEffect(() => {
    if (activeTab === 'resumen' && !authLoading) {
      cargarResumen()
    }
  }, [activeTab, authLoading])

  const cargarResumen = async () => {
    setLoading(true)
    setError('')
    try {
      const { data: sessionData } = await supabase.auth.getSession()
      const token = sessionData.session?.access_token

      if (!token) {
        setError('No hay sesion activa. Por favor inicia sesion nuevamente.')
        setLoading(false)
        return
      }

      const response = await fetch(`${EDGE_FUNCTION_URL}/reportes-resumen?mes=current`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        const errorText = await response.text()
        throw new Error(`Error ${response.status}: ${errorText}`)
      }

      const result = await response.json()
      if (result.success) {
        setResumenData(result.data.resumen_mensual || [])
        setKpis(result.data.kpis)
      } else {
        setError(result.error || 'Error al cargar resumen')
      }
    } catch (err: any) {
      console.error('Error cargando resumen:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const cargarDetalle = async (offset = 0) => {
    setLoading(true)
    setError('')
    try {
      const { data: sessionData } = await supabase.auth.getSession()
      const token = sessionData.session?.access_token

      if (!token) {
        setError('No hay sesion activa.')
        setLoading(false)
        return
      }

      let url = `${EDGE_FUNCTION_URL}/reportes-detalle?tipo=${tipoReporte}&limit=50&offset=${offset}`
      if (fechaDesde) url += `&fecha_desde=${fechaDesde}`
      if (fechaHasta) url += `&fecha_hasta=${fechaHasta}`
      if (estado) url += `&estado=${estado}`

      const response = await fetch(url, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        const errorText = await response.text()
        throw new Error(`Error ${response.status}: ${errorText}`)
      }

      const result = await response.json()
      if (result.success) {
        setDetalleData(result.data || [])
        setPagination(result.pagination)
      } else {
        setError(result.error || 'Error al cargar detalle')
      }
    } catch (err: any) {
      console.error('Error cargando detalle:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const exportarCSV = async () => {
    setLoading(true)
    try {
      const { data: sessionData } = await supabase.auth.getSession()
      const token = sessionData.session?.access_token

      if (!token) {
        alert('❌ No hay sesion activa')
        setLoading(false)
        return
      }

      const response = await fetch(`${EDGE_FUNCTION_URL}/exportar-csv`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          tipo: activeTab === 'resumen' ? 'resumen' : tipoReporte,
          nombre_archivo: `ezpayconnect_${activeTab === 'resumen' ? 'resumen' : tipoReporte}_${new Date().toISOString().split('T')[0]}.csv`
        })
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ error: 'Error desconocido' }))
        throw new Error(errorData.error || 'Error al exportar')
      }

      const blob = await response.blob()
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `ezpayconnect_${activeTab === 'resumen' ? 'resumen' : tipoReporte}_${new Date().toISOString().split('T')[0]}.csv`
      document.body.appendChild(a)
      a.click()
      window.URL.revokeObjectURL(url)
      document.body.removeChild(a)

      alert('✅ CSV descargado exitosamente')
    } catch (err: any) {
      alert('❌ Error al exportar: ' + err.message)
    } finally {
      setLoading(false)
    }
  }

  const formatearMes = (mes: string) => {
    try {
      const fecha = new Date(mes)
      return fecha.toLocaleDateString('es-ES', { month: 'long', year: 'numeric' })
    } catch {
      return mes
    }
  }

  // Mostrar loading mientras auth carga
  if (authLoading) {
    return (
      <div className="min-h-screen bg-[#0a0e1a] flex items-center justify-center">
        <div className="text-white text-lg">Verificando permisos...</div>
      </div>
    )
  }

  // Si no es admin, mostrar mensaje
  if (!isAdmin) {
    return (
      <div className="min-h-screen bg-[#0a0e1a] flex items-center justify-center">
        <div className="bg-red-900/30 border border-red-500/50 rounded-lg p-8 text-center">
          <AlertCircle className="text-red-400 mx-auto mb-4" size={48} />
          <h2 className="text-xl font-bold text-red-300 mb-2">Acceso denegado</h2>
          <p className="text-gray-400">No tienes permisos de administrador para ver esta pagina.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#0a0e1a] text-white p-6">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-[#00f2ff] mb-2 flex items-center gap-3">
          <BarChart3 size={32} />
          Reportes Avanzados
        </h1>
        <p className="text-gray-400">Analisis y exportacion de datos del sistema</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-4 mb-6">
        <button
          onClick={() => setActiveTab('resumen')}
          className={`px-6 py-3 rounded-lg font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'resumen'
              ? 'bg-[#00f2ff] text-black'
              : 'bg-[#1a1f2e] text-gray-300 hover:bg-[#252b3d]'
          }`}
        >
          <TrendingUp size={20} />
          Resumen Mensual
        </button>
        <button
          onClick={() => setActiveTab('detalle')}
          className={`px-6 py-3 rounded-lg font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'detalle'
              ? 'bg-[#00f2ff] text-black'
              : 'bg-[#1a1f2e] text-gray-300 hover:bg-[#252b3d]'
          }`}
        >
          <Filter size={20} />
          Detalle Filtrable
        </button>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-900/30 border border-red-500/50 rounded-lg p-4 mb-6 flex items-center gap-3">
          <AlertCircle className="text-red-400" size={20} />
          <span className="text-red-300">{error}</span>
          <button 
            onClick={() => setError('')}
            className="ml-auto text-sm text-red-400 hover:text-red-300 underline"
          >
            Cerrar
          </button>
        </div>
      )}

      {/* === RESUMEN MENSUAL === */}
      {activeTab === 'resumen' && (
        <>
          {/* KPIs Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
            <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl p-6">
              <div className="flex items-center justify-between mb-4">
                <Users className="text-[#00f2ff]" size={28} />
                <span className="text-xs text-gray-400 bg-[#0a0e1a] px-2 py-1 rounded">Total</span>
              </div>
              <div className="text-3xl font-bold text-white">{kpis?.total_pacientes ?? '—'}</div>
              <div className="text-sm text-gray-400 mt-1">Pacientes registrados</div>
            </div>

            <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl p-6">
              <div className="flex items-center justify-between mb-4">
                <Stethoscope className="text-[#00f2ff]" size={28} />
                <span className="text-xs text-gray-400 bg-[#0a0e1a] px-2 py-1 rounded">Total</span>
              </div>
              <div className="text-3xl font-bold text-white">{kpis?.total_medicos ?? '—'}</div>
              <div className="text-sm text-gray-400 mt-1">Medicos activos</div>
            </div>

            <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl p-6">
              <div className="flex items-center justify-between mb-4">
                <Calendar className="text-[#00f2ff]" size={28} />
                <span className="text-xs text-gray-400 bg-[#0a0e1a] px-2 py-1 rounded">Hoy</span>
              </div>
              <div className="text-3xl font-bold text-white">{kpis?.citas_hoy ?? '—'}</div>
              <div className="text-sm text-gray-400 mt-1">Citas programadas</div>
            </div>

            <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl p-6">
              <div className="flex items-center justify-between mb-4">
                <FileText className="text-[#00f2ff]" size={28} />
                <span className="text-xs text-gray-400 bg-[#0a0e1a] px-2 py-1 rounded">Total</span>
              </div>
              <div className="text-3xl font-bold text-white">{kpis?.recetas_total ?? '—'}</div>
              <div className="text-sm text-gray-400 mt-1">Recetas emitidas</div>
            </div>
          </div>

          {/* Tabla Resumen */}
          <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl overflow-hidden">
            <div className="p-6 border-b border-[#00f2ff]/10 flex items-center justify-between">
              <h2 className="text-xl font-semibold text-[#00f2ff] flex items-center gap-2">
                <BarChart3 size={22} />
                Historial Mensual
              </h2>
              <div className="flex gap-2">
                <button
                  onClick={cargarResumen}
                  disabled={loading}
                  className="px-4 py-2 bg-[#252b3d] hover:bg-[#30384d] rounded-lg text-sm flex items-center gap-2 transition-colors disabled:opacity-50"
                >
                  <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
                  Actualizar
                </button>
                <button
                  onClick={exportarCSV}
                  disabled={loading}
                  className="px-4 py-2 bg-[#00f2ff] hover:bg-[#00d9e6] text-black rounded-lg text-sm font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
                >
                  <Download size={16} />
                  Exportar CSV
                </button>
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="bg-[#0f1320] text-gray-400 text-sm">
                    <th className="px-6 py-4 text-left font-medium">Mes</th>
                    <th className="px-6 py-4 text-center font-medium">Total Citas</th>
                    <th className="px-6 py-4 text-center font-medium text-green-400">Atendidas</th>
                    <th className="px-6 py-4 text-center font-medium text-red-400">Canceladas</th>
                    <th className="px-6 py-4 text-center font-medium text-yellow-400">Pendientes</th>
                    <th className="px-6 py-4 text-center font-medium">Pacientes Nuevos</th>
                    <th className="px-6 py-4 text-center font-medium">Recetas</th>
                  </tr>
                </thead>
                <tbody>
                  {resumenData.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="px-6 py-12 text-center text-gray-500">
                        {loading ? 'Cargando datos...' : error ? 'Error al cargar' : 'No hay datos disponibles'}
                      </td>
                    </tr>
                  ) : (
                    resumenData.map((row, idx) => (
                      <tr key={idx} className="border-t border-[#00f2ff]/5 hover:bg-[#0f1320]/50 transition-colors">
                        <td className="px-6 py-4 font-medium text-white">{formatearMes(row.mes)}</td>
                        <td className="px-6 py-4 text-center font-bold text-[#00f2ff]">{row.total_citas}</td>
                        <td className="px-6 py-4 text-center text-green-400">{row.citas_atendidas}</td>
                        <td className="px-6 py-4 text-center text-red-400">{row.citas_canceladas}</td>
                        <td className="px-6 py-4 text-center text-yellow-400">{row.citas_pendientes}</td>
                        <td className="px-6 py-4 text-center">{row.pacientes_nuevos}</td>
                        <td className="px-6 py-4 text-center">{row.recetas_emitidas}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {/* === DETALLE FILTRABLE === */}
      {activeTab === 'detalle' && (
        <>
          {/* Filtros */}
          <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl p-6 mb-6">
            <div className="flex items-center gap-2 mb-4 text-[#00f2ff]">
              <Filter size={20} />
              <h3 className="font-semibold">Filtros de busqueda</h3>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div>
                <label className="block text-sm text-gray-400 mb-2">Tipo de reporte</label>
                <div className="relative">
                  <select
                    value={tipoReporte}
                    onChange={(e) => setTipoReporte(e.target.value)}
                    className="w-full bg-[#0a0e1a] border border-[#00f2ff]/30 rounded-lg px-4 py-3 text-white appearance-none focus:outline-none focus:border-[#00f2ff]"
                  >
                    <option value="citas">Citas</option>
                    <option value="pacientes">Pacientes</option>
                    <option value="recetas">Recetas</option>
                  </select>
                  <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" size={18} />
                </div>
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-2">Fecha desde</label>
                <input
                  type="date"
                  value={fechaDesde}
                  onChange={(e) => setFechaDesde(e.target.value)}
                  className="w-full bg-[#0a0e1a] border border-[#00f2ff]/30 rounded-lg px-4 py-3 text-white focus:outline-none focus:border-[#00f2ff]"
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-2">Fecha hasta</label>
                <input
                  type="date"
                  value={fechaHasta}
                  onChange={(e) => setFechaHasta(e.target.value)}
                  className="w-full bg-[#0a0e1a] border border-[#00f2ff]/30 rounded-lg px-4 py-3 text-white focus:outline-none focus:border-[#00f2ff]"
                />
              </div>

              {tipoReporte === 'citas' && (
                <div>
                  <label className="block text-sm text-gray-400 mb-2">Estado</label>
                  <div className="relative">
                    <select
                      value={estado}
                      onChange={(e) => setEstado(e.target.value)}
                      className="w-full bg-[#0a0e1a] border border-[#00f2ff]/30 rounded-lg px-4 py-3 text-white appearance-none focus:outline-none focus:border-[#00f2ff]"
                    >
                      <option value="">Todos</option>
                      <option value="pendiente">Pendiente</option>
                      <option value="atendida">Atendida</option>
                      <option value="cancelada">Cancelada</option>
                    </select>
                    <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" size={18} />
                  </div>
                </div>
              )}
            </div>

            <div className="flex gap-3 mt-6">
              <button
                onClick={() => cargarDetalle(0)}
                disabled={loading}
                className="px-6 py-3 bg-[#00f2ff] hover:bg-[#00d9e6] text-black rounded-lg font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
              >
                <Filter size={18} />
                {loading ? 'Cargando...' : 'Aplicar filtros'}
              </button>
              <button
                onClick={exportarCSV}
                disabled={loading || detalleData.length === 0}
                className="px-6 py-3 bg-[#252b3d] hover:bg-[#30384d] rounded-lg font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
              >
                <Download size={18} />
                Exportar CSV
              </button>
            </div>
          </div>

          {/* Tabla Detalle */}
          <div className="bg-[#1a1f2e] border border-[#00f2ff]/20 rounded-xl overflow-hidden">
            <div className="p-4 border-b border-[#00f2ff]/10 text-sm text-gray-400 flex justify-between">
              <span>Mostrando {detalleData.length} de {pagination.total} registros</span>
              {pagination.has_more && (
                <button
                  onClick={() => cargarDetalle(pagination.offset + pagination.limit)}
                  className="text-[#00f2ff] hover:underline"
                >
                  Cargar mas...
                </button>
              )}
            </div>

            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="bg-[#0f1320] text-gray-400 text-sm">
                    {tipoReporte === 'citas' && (
                      <>
                        <th className="px-6 py-4 text-left">Fecha</th>
                        <th className="px-6 py-4 text-left">Paciente</th>
                        <th className="px-6 py-4 text-left">Medico</th>
                        <th className="px-6 py-4 text-center">Estado</th>
                        <th className="px-6 py-4 text-left">Motivo</th>
                      </>
                    )}
                    {tipoReporte === 'pacientes' && (
                      <>
                        <th className="px-6 py-4 text-left">Nombre</th>
                        <th className="px-6 py-4 text-left">Telefono</th>
                        <th className="px-6 py-4 text-center">Total Citas</th>
                        <th className="px-6 py-4 text-center">Ultima Cita</th>
                        <th className="px-6 py-4 text-center">Recetas</th>
                      </>
                    )}
                    {tipoReporte === 'recetas' && (
                      <>
                        <th className="px-6 py-4 text-left">Fecha</th>
                        <th className="px-6 py-4 text-left">Paciente</th>
                        <th className="px-6 py-4 text-left">Medico</th>
                        <th className="px-6 py-4 text-left">Diagnostico</th>
                        <th className="px-6 py-4 text-center">Estado</th>
                      </>
                    )}
                  </tr>
                </thead>
                <tbody>
                  {detalleData.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="px-6 py-12 text-center text-gray-500">
                        {loading ? 'Cargando...' : 'Aplica filtros para ver resultados'}
                      </td>
                    </tr>
                  ) : (
                    detalleData.map((row, idx) => (
                      <tr key={idx} className="border-t border-[#00f2ff]/5 hover:bg-[#0f1320]/50 transition-colors">
                        {tipoReporte === 'citas' && (
                          <>
                            <td className="px-6 py-4">{row.fecha} {row.hora}</td>
                            <td className="px-6 py-4">{row.paciente?.nombre || 'N/A'}</td>
                            <td className="px-6 py-4">{row.medico?.nombre || 'N/A'}</td>
                            <td className="px-6 py-4 text-center">
                              <span className={`px-2 py-1 rounded text-xs font-medium ${
                                row.estado === 'atendida' ? 'bg-green-500/20 text-green-400' :
                                row.estado === 'cancelada' ? 'bg-red-500/20 text-red-400' :
                                'bg-yellow-500/20 text-yellow-400'
                              }`}>
                                {row.estado}
                              </span>
                            </td>
                            <td className="px-6 py-4 text-gray-400">{row.motivo || '-'}</td>
                          </>
                        )}
                        {tipoReporte === 'pacientes' && (
                          <>
                            <td className="px-6 py-4 font-medium">{row.paciente_nombre}</td>
                            <td className="px-6 py-4">{row.telefono || 'N/A'}</td>
                            <td className="px-6 py-4 text-center">{row.total_citas}</td>
                            <td className="px-6 py-4 text-center">{row.ultima_cita || 'Nunca'}</td>
                            <td className="px-6 py-4 text-center">{row.total_recetas}</td>
                          </>
                        )}
                        {tipoReporte === 'recetas' && (
                          <>
                            <td className="px-6 py-4">{row.created_at?.split('T')[0]}</td>
                            <td className="px-6 py-4">{row.paciente?.nombre || 'N/A'}</td>
                            <td className="px-6 py-4">{row.medico?.nombre || 'N/A'}</td>
                            <td className="px-6 py-4 text-gray-400">{row.diagnostico || '-'}</td>
                            <td className="px-6 py-4 text-center">
                              <span className="px-2 py-1 rounded text-xs font-medium bg-blue-500/20 text-blue-400">
                                {row.estado || 'activa'}
                              </span>
                            </td>
                          </>
                        )}
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
