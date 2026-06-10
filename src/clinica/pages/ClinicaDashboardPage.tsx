import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import {
  Users,
  Stethoscope,
  CalendarDays,
  FileText,
  MapPin,
  TrendingUp,
} from 'lucide-react'

interface ClinicaStats {
  total_medicos: number
  total_staff: number
  total_pacientes: number
  total_citas: number
  total_recetas: number
}

export default function ClinicaDashboardPage() {
  const { clinica, loading: clinicaLoading, error: clinicaError } = useClinicaAuth()
  const [stats, setStats] = useState<ClinicaStats>({
    total_medicos: 0,
    total_staff: 0,
    total_pacientes: 0,
    total_citas: 0,
    total_recetas: 0,
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
        const { data: medicosRel } = await supabase
          .rpc('obtener_medicos_clinica', { p_clinica_id: clinica.id })

        const medicoIds = medicosRel?.map(m => m.medico_id) || []

        let medicosCount = 0
        if (medicoIds.length > 0) {
          const { data: countResult } = await supabase
            .rpc('contar_medicos_por_ids', { p_medico_ids: medicoIds })
          medicosCount = countResult || 0
        }

        const { count: citasCount } = await supabase
          .from('citas')
          .select('*', { count: 'exact', head: true })
          .in('medico_id', medicoIds.length > 0 ? medicoIds : ['no-existe'])

        const { count: recetasCount } = await supabase
          .from('recetas')
          .select('*', { count: 'exact', head: true })
          .in('medico_id', medicoIds.length > 0 ? medicoIds : ['no-existe'])

        setStats({
          total_medicos: medicosCount || 0,
          total_staff: medicoIds.length,
          total_pacientes: 0, // Se calcularía de pacientes asociados a médicos de la clínica
          total_citas: citasCount || 0,
          total_recetas: recetasCount || 0,
        })
      } catch (error) {
        console.error('Error cargando stats:', error)
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
    { title: 'Personal Total', value: stats.total_staff, icon: Users, color: 'bg-blue-50 text-blue-600' },
    { title: 'Citas', value: stats.total_citas, icon: CalendarDays, color: 'bg-amber-50 text-amber-600' },
    { title: 'Recetas', value: stats.total_recetas, icon: FileText, color: 'bg-cyan-50 text-cyan-600' },
  ]

  return (
    <div className="max-w-5xl mx-auto">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-[#1E5C8E]">{clinica?.nombre}</h1>
        <p className="text-sm text-gray-500">{clinica?.direccion}</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {statCards.map((card) => {
          const Icon = card.icon
          return (
            <Card key={card.title}>
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
