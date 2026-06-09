import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useClinicaCitas } from '@/clinica/hooks/useClinicaCitas'
import CitaCard from '@/medico/components/CitaCard'
import CitasFilter from '@/medico/components/CitasFilter'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import {
  CalendarDays,
  Loader2,
  RefreshCw,
  UserPlus,
  Stethoscope,
  AlertCircle,
  Building2,
} from 'lucide-react'

export default function ClinicaCitasPage() {
  const navigate = useNavigate()
  const {
    citas,
    loading,
    filtroEstado,
    setFiltroEstado,
    medicosClinica,
    clinicas,
    clinicaId,
    clinicaNombre,
    cambiarClinica,
    fetchCitas,
    confirmarCita,
    rechazarCita,
    asignarMedico,
  } = useClinicaCitas()

  const [accionEnProgreso, setAccionEnProgreso] = useState<string | null>(null)
  const [asignandoCitaId, setAsignandoCitaId] = useState<number | null>(null)

  const handleConfirmar = async (cita: any) => {
    setAccionEnProgreso(`confirmar-${cita.id}`)
    await confirmarCita(cita)
    setAccionEnProgreso(null)
  }

  const handleRechazar = async (cita: any) => {
    if (!confirm('¿Estás seguro de rechazar esta cita?')) return
    setAccionEnProgreso(`rechazar-${cita.id}`)
    await rechazarCita(cita)
    setAccionEnProgreso(null)
  }

  const handleAsignarMedico = async (citaId: number, medicoId: string) => {
    const cita = citas.find(c => c.id === citaId)
    if (!cita) return
    setAccionEnProgreso(`asignar-${citaId}`)
    await asignarMedico(cita, medicoId)
    setAsignandoCitaId(null)
    setAccionEnProgreso(null)
  }

  const counts = (() => {
    const c: Record<string, number> = { todos: citas.length }
    citas.forEach((cita) => {
      c[cita.estado] = (c[cita.estado] || 0) + 1
    })
    return c
  })()

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <CalendarDays className="h-7 w-7 text-[#1E5C8E]" />
            Citas de la Clínica
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gestiona las citas de todos los médicos de la clínica.
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={fetchCitas}>
          <RefreshCw className="h-4 w-4 mr-1" />
          Recargar
        </Button>
      </div>

      {/* Selector de clínica */}
      {clinicas.length > 1 && (
        <Card className="border-blue-100 bg-blue-50/50">
          <CardContent className="p-4 flex items-center gap-3">
            <Building2 className="h-5 w-5 text-[#1E5C8E] shrink-0" />
            <div className="flex items-center gap-3 flex-wrap">
              <span className="text-sm font-medium text-[#1a2a3a]">Clínica:</span>
              <Select value={clinicaId || ''} onValueChange={cambiarClinica}>
                <SelectTrigger className="w-64 bg-white">
                  <SelectValue placeholder="Seleccionar clínica" />
                </SelectTrigger>
                <SelectContent>
                  {clinicas.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.nombre}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Nombre de la clínica actual (si solo hay 1 o como info adicional) */}
      {clinicas.length === 1 && clinicaNombre && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Building2 className="h-4 w-4" />
          <span>{clinicaNombre}</span>
        </div>
      )}

      {/* Filtros */}
      <CitasFilter filtro={filtroEstado} onChange={setFiltroEstado} counts={counts} />

      {/* Alerta de citas sin médico */}
      {citas.some(c => c.estado === 'solicitada' && !c.medico_id) && (
        <Card className="bg-amber-50 border-amber-200">
          <CardContent className="p-4 flex items-center gap-3">
            <AlertCircle className="h-5 w-5 text-amber-600 shrink-0" />
            <p className="text-sm text-amber-700">
              Hay citas <strong>sin médico asignado</strong>. Asigna un médico para que pueda confirmarlas.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Listado */}
      <div className="space-y-3">
        {citas.length === 0 ? (
          <div className="text-center py-16 bg-white rounded-xl border border-dashed">
            <CalendarDays className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">
              {filtroEstado === 'todos'
                ? `No hay citas en ${clinicaNombre || 'la clínica'}`
                : `No hay citas ${filtroEstado}`}
            </p>
          </div>
        ) : (
          citas.map((cita) => (
            <div key={cita.id} className="space-y-2">
              <CitaCard
                cita={cita}
                onConfirmar={handleConfirmar}
                onRechazar={handleRechazar}
                accionEnProgreso={accionEnProgreso}
              />

              {/* Asignar médico a citas sin médico */}
              {cita.estado === 'solicitada' && !cita.medico_id && (
                <Card className="border-l-4 border-l-amber-400 ml-4">
                  <CardContent className="p-3 flex items-center gap-3 flex-wrap">
                    <UserPlus className="h-4 w-4 text-amber-600" />
                    <span className="text-sm font-medium">Asignar médico:</span>
                    {asignandoCitaId === cita.id ? (
                      <div className="flex items-center gap-2">
                        <Select
                          onValueChange={(val) => handleAsignarMedico(cita.id, val)}
                        >
                          <SelectTrigger className="w-64">
                            <SelectValue placeholder="Seleccionar médico" />
                          </SelectTrigger>
                          <SelectContent>
                            {medicosClinica.map((m) => (
                              <SelectItem key={m.id} value={m.id}>
                                <div className="flex items-center gap-2">
                                  <Stethoscope className="h-3 w-3" />
                                  {m.nombre_completo}
                                  {m.especialidad && (
                                    <span className="text-muted-foreground">({m.especialidad})</span>
                                  )}
                                </div>
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => setAsignandoCitaId(null)}
                        >
                          Cancelar
                        </Button>
                      </div>
                    ) : (
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => setAsignandoCitaId(cita.id)}
                      >
                        <UserPlus className="h-3 w-3 mr-1" />
                        Asignar médico
                      </Button>
                    )}
                  </CardContent>
                </Card>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  )
}
