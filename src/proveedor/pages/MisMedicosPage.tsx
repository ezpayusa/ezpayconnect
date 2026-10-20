import { useState, useEffect } from 'react'
import { Navigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Loader2, Stethoscope } from 'lucide-react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { usePuedeEnrolar } from '@/visitador/hooks/usePuedeEnrolar'
import { useEnrolamiento } from '@/visitador/hooks/useEnrolamiento'
import { formatearFechaIso, type MedicoEnrolado } from '@/visitador/lib/enrolamiento'

// Gate de la página (solo UI; la barrera es listar_mis_medicos_enrolados: PV016 tipo, PV017 rol): laboratorio
// farmacéutico con el módulo 'enrolamiento' y permiso visitadores.gestionar (admin y supervisor). El resto vuelve al
// dashboard con el mismo <Navigate replace> que ProveedorReporteVisitasPage. Se espera a que carguen los dos hooks.
export default function MisMedicosPage() {
  const { loading, puede } = useProveedorAuth()
  const { puedeEnrolar, loading: loadingEnrolar } = usePuedeEnrolar()
  if (loading || loadingEnrolar) {
    return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }
  if (!puedeEnrolar || !puede('visitadores.gestionar')) {
    return <Navigate to="/proveedor/dashboard" replace />
  }
  return <MisMedicos />
}

const fechaCorta = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString('es-GT') : '—')

function MisMedicos() {
  const { listarMisMedicos } = useEnrolamiento()
  const [medicos, setMedicos] = useState<MedicoEnrolado[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    listarMisMedicos().then((r) => {
      if (!vivo) return
      setLoading(false)
      if (!r.ok) { toast.error(r.error.mensaje); setError(r.error.mensaje); return }
      setMedicos(r.data)
    })
    return () => { vivo = false }
  }, [listarMisMedicos])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
          <Stethoscope className="h-6 w-6 text-[#1E5C8E]" /> Mis médicos
        </h1>
        <p className="text-slate-500 mt-1">Médicos que enroló tu laboratorio y el estado de su prioridad</p>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : error ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500" data-testid="error-mis-medicos">{error}</CardContent>
        </Card>
      ) : medicos.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <Stethoscope className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>Todavía no tienes médicos enrolados.</p>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-0 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-slate-600">
                <tr>
                  <th className="px-4 py-3 font-medium">Nombre</th>
                  <th className="px-4 py-3 font-medium">Especialidad</th>
                  <th className="px-4 py-3 font-medium">Enrolado el</th>
                  <th className="px-4 py-3 font-medium">Prioridad</th>
                  <th className="px-4 py-3 font-medium">Visitas</th>
                  <th className="px-4 py-3 font-medium">Vence el</th>
                  <th className="px-4 py-3 font-medium">Días de ventaja</th>
                </tr>
              </thead>
              <tbody>
                {medicos.map((m) => (
                  <tr key={m.medico_id} className="border-t" data-testid="medico-enrolado">
                    <td className="px-4 py-3 font-medium text-slate-800">{m.nombre_completo}</td>
                    <td className="px-4 py-3 text-slate-600">{m.especialidad || '—'}</td>
                    <td className="px-4 py-3 text-slate-600">{fechaCorta(m.lab_enrolador_fecha)}</td>
                    <td className="px-4 py-3">
                      {m.prioridad_activa
                        ? <Badge className="bg-emerald-100 text-emerald-700" data-testid="badge-prioridad">Activa</Badge>
                        : <Badge className="bg-slate-100 text-slate-600" data-testid="badge-prioridad">Vencida</Badge>}
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {m.visitas_completadas != null && m.visitas_limite != null ? `${m.visitas_completadas} de ${m.visitas_limite}` : '—'}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{m.prioridad_vence_el ? formatearFechaIso(m.prioridad_vence_el) : '—'}</td>
                    <td className="px-4 py-3 text-slate-600">{m.dias_ventaja ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
