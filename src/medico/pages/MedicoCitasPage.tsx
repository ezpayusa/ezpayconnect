import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMedicoCitas } from '@/medico/hooks/useMedicoCitas'
import CitaCard from '@/medico/components/CitaCard'
import CitasFilter from '@/medico/components/CitasFilter'
import { Button } from '@/components/ui/button'
import { CalendarDays, Plus, Loader2, RefreshCw } from 'lucide-react'

export default function MedicoCitasPage() {
  const navigate = useNavigate()
  const {
    citas,
    loading,
    filtroEstado,
    setFiltroEstado,
    fetchCitas,
    confirmarCita,
    rechazarCita,
    marcarEnSala,
  } = useMedicoCitas()

  const [accionEnProgreso, setAccionEnProgreso] = useState<string | null>(null)

  const handleConfirmar = async (cita: any) => {
    setAccionEnProgreso(`confirmar-${cita.id}`)
    await confirmarCita(cita)
    setAccionEnProgreso(null)
  }

  const handleRechazar = async (cita: any) => {
    if (!confirm('¿Estás seguro de rechazar esta cita? Se notificará al paciente.')) return
    setAccionEnProgreso(`rechazar-${cita.id}`)
    await rechazarCita(cita)
    setAccionEnProgreso(null)
  }

  const handleEnSala = async (cita: any) => {
    setAccionEnProgreso(`ensala-${cita.id}`)
    await marcarEnSala(cita)
    setAccionEnProgreso(null)
    navigate(`/medico/consulta/${cita.id}`)
  }

  const counts = useMemo(() => {
    const c: Record<string, number> = { todos: citas.length }
    citas.forEach((cita) => {
      c[cita.estado] = (c[cita.estado] || 0) + 1
    })
    return c
  }, [citas])

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
            Mis Citas
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gestiona tus citas médicas. Confirma, rechaza o atiende consultas.
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={fetchCitas}>
            <RefreshCw className="h-4 w-4 mr-1" />
            Recargar
          </Button>
        </div>
      </div>

      {/* Filtros */}
      <CitasFilter filtro={filtroEstado} onChange={setFiltroEstado} counts={counts} />

      {/* Listado */}
      <div className="space-y-3">
        {citas.length === 0 ? (
          <div className="text-center py-16 bg-white rounded-xl border border-dashed">
            <CalendarDays className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">
              {filtroEstado === 'todos'
                ? 'No tienes citas registradas'
                : `No hay citas ${filtroEstado}`}
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              Las citas solicitadas por pacientes aparecerán aquí.
            </p>
          </div>
        ) : (
          citas.map((cita) => (
            <CitaCard
              key={cita.id}
              cita={cita}
              onConfirmar={handleConfirmar}
              onRechazar={handleRechazar}
              onEnSala={handleEnSala}
              accionEnProgreso={accionEnProgreso}
            />
          ))
        )}
      </div>
    </div>
  )
}
