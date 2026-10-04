import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import BannerPublicidadProfesional from '@/components/BannerPublicidadProfesional'
import {
  Users,
  Stethoscope,
  CalendarDays,
  FileText,
  MapPin,
  TrendingUp,
} from 'lucide-react'

// null = la consulta falló: la tarjeta muestra "—", nunca un 0 como dato.
interface ClinicaStats {
  total_medicos: number | null
  total_staff: number | null
  total_pacientes: number | null
  total_citas: number | null
  total_recetas: number | null
}

// Error de una consulta del dashboard: mensaje fijo + code (sin datos de la fila).
function logError(que: string, error: { code?: string } | null) {
  if (error) console.error(`[dashboard-clinica] no se pudo cargar ${que}:`, error.code ?? 'sin code')
}

const PAGINA = 1000

export default function ClinicaDashboardPage() {
  const { clinica, loading: clinicaLoading, error: clinicaError } = useClinicaAuth()
  const [stats, setStats] = useState<ClinicaStats>({
    total_medicos: null,
    total_staff: null,
    total_pacientes: null,
    total_citas: null,
    total_recetas: null,
  })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // Esperar a que useClinicaAuth resuelva
    if (clinicaLoading) return
    // Resuelto pero sin clínica: detener el spinner y mostrar mensaje
    if (!clinica) {
      setLoading(false)
      return
    }

    const cargarStats = async () => {
      setLoading(true)
      try {
        // Obtener médicos de esta clínica via RPC
        const { data: medicosRel, error: errMedicosRel } = await supabase
          .rpc('obtener_medicos_clinica', { p_clinica_id: clinica.id })
        logError('los médicos de la clínica', errMedicosRel)

        const medicoIds = medicosRel?.map(m => m.medico_id) || []

        let medicosCount: number | null = errMedicosRel ? null : 0
        if (!errMedicosRel && medicoIds.length > 0) {
          const { data: countResult, error: errContar } = await supabase
            .rpc('contar_medicos_por_ids', { p_medico_ids: medicoIds })
          logError('el conteo de médicos', errContar)
          medicosCount = errContar ? null : Number(countResult ?? 0)
        }

        // Citas de la clínica (por clinica_id)
        const { count: citasCount, error: errCitas } = await supabase
          .from('citas')
          .select('id', { count: 'exact', head: true })
          .eq('clinica_id', clinica.id)
        logError('las citas', errCitas)

        // Pacientes distintos con al menos una cita en la clínica (paginado: PostgREST corta en 1000 filas)
        const pacientesIds = new Set<number>()
        let errPacientes: { code?: string } | null = null
        for (let desde = 0; ; desde += PAGINA) {
          const { data, error } = await supabase
            .from('citas')
            .select('paciente_id')
            .eq('clinica_id', clinica.id)
            .order('id', { ascending: true })
            .range(desde, desde + PAGINA - 1)
          if (error) { errPacientes = error; break }
          for (const c of data || []) if (c.paciente_id != null) pacientesIds.add(c.paciente_id)
          if (!data || data.length < PAGINA) break
        }
        logError('los pacientes', errPacientes)

        // recetas no tiene clinica_id: se cuentan las de los médicos de la clínica (criterio anterior)
        let recetasCount: number | null = errMedicosRel ? null : 0
        if (!errMedicosRel && medicoIds.length > 0) {
          const { count, error: errRecetas } = await supabase
            .from('recetas')
            .select('id', { count: 'exact', head: true })
            .in('medico_id', medicoIds)
          logError('las recetas', errRecetas)
          recetasCount = errRecetas ? null : count ?? 0
        }

        setStats({
          total_medicos: medicosCount,
          total_staff: errMedicosRel ? null : medicoIds.length,
          total_pacientes: errPacientes ? null : pacientesIds.size,
          total_citas: errCitas ? null : citasCount ?? 0,
          total_recetas: recetasCount,
        })
      } catch (error) {
        console.error('[dashboard-clinica] error cargando las estadísticas:', (error as { code?: string } | null)?.code ?? 'sin code')
      } finally {
        setLoading(false)
      }
    }

    cargarStats()
  }, [clinica, clinicaLoading])

  if (clinicaLoading || loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!clinica) {
    return (
      <div className="max-w-5xl mx-auto p-6">
        <Card>
          <CardContent className="p-8 text-center text-gray-600">
            <MapPin className="h-10 w-10 mx-auto mb-3 text-gray-300" />
            <p className="font-medium">{clinicaError || 'No se encontró una clínica asociada a este usuario.'}</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  const statCards = [
    { title: 'Médicos', value: stats.total_medicos, icon: Stethoscope, color: 'bg-[#87CEEB]/10 text-[#1E5C8E]' },
    { title: 'Pacientes', value: stats.total_pacientes, icon: Users, color: 'bg-violet-50 text-violet-600' },
    { title: 'Citas', value: stats.total_citas, icon: CalendarDays, color: 'bg-amber-50 text-amber-600' },
    { title: 'Recetas', value: stats.total_recetas, icon: FileText, color: 'bg-cyan-50 text-cyan-600' },
  ]

  return (
    <div className="max-w-5xl mx-auto">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-[#1E5C8E]">{clinica?.nombre}</h1>
        <p className="text-sm text-gray-500">{clinica?.direccion}</p>
      </div>

      {/* Banner publicitario (sección dedicada — país filtrado por RLS, separado del catálogo) */}
      <BannerPublicidadProfesional tipoPerfil="clinica" contexto="dashboard" />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {statCards.map((card) => {
          const Icon = card.icon
          return (
            <Card key={card.title}>
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-500">{card.title}</p>
                    <p className="text-2xl font-bold mt-1">{card.value === null ? '—' : card.value}</p>
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

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Información de la Clínica</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <p><strong>Nombre:</strong> {clinica?.nombre}</p>
          <p><strong>Dirección:</strong> {clinica?.direccion || 'No especificada'}</p>
          <p><strong>Teléfono:</strong> {clinica?.telefono || 'No especificado'}</p>
          <p><strong>Email:</strong> {clinica?.email || 'No especificado'}</p>
          <p><strong>Estado:</strong> {clinica?.activa ? 'Activa' : 'Inactiva'}</p>
        </CardContent>
      </Card>
    </div>
  )
}
