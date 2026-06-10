import { useState } from 'react'
import { toast } from 'sonner'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppCitas } from '@/webapp/hooks/useWebAppCitas'
import type { CitaPaciente } from '@/webapp/types/webapp.types'
import AgendarCitaModal from '@/webapp/components/AgendarCitaModal'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { CalendarDays, Clock, Plus, Loader2, MapPin, X } from 'lucide-react'

const ESTADOS_CANCELABLES = ['solicitada', 'agendada', 'confirmada']

export default function WebAppCitas() {
  const { perfil } = useWebAppAuth()
  const { proximas, pasadas, canceladas, loading, error, refetch, cancelarCita } = useWebAppCitas(perfil?.id)
  const [tab, setTab] = useState<'proximas' | 'pasadas' | 'canceladas'>('proximas')
  const [modalOpen, setModalOpen] = useState(false)

  // Estado del modal de cancelación
  const [citaACancelar, setCitaACancelar] = useState<CitaPaciente | null>(null)
  const [motivoCancel, setMotivoCancel] = useState('')
  const [cancelando, setCancelando] = useState(false)

  const handleConfirmarCancelacion = async () => {
    if (!citaACancelar) return
    if (!motivoCancel.trim()) {
      toast.error('Por favor escribe el motivo de la cancelación')
      return
    }
    setCancelando(true)
    const res = await cancelarCita(citaACancelar.id, motivoCancel.trim(), perfil?.nombre)
    setCancelando(false)
    if (res.ok) {
      toast.success('Cita cancelada. La clínica fue notificada.')
      setCitaACancelar(null)
      setMotivoCancel('')
    } else {
      toast.error('Error al cancelar: ' + (res.error || 'inténtalo de nuevo'))
    }
  }

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'agendada': return 'bg-sky-50 text-sky-700 border-sky-200'
      case 'confirmada': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
      case 'en_curso': return 'bg-amber-50 text-amber-700 border-amber-200'
      case 'solicitada': return 'bg-yellow-50 text-yellow-700 border-yellow-200'
      case 'completada': return 'bg-blue-50 text-blue-700 border-blue-200'
      case 'cancelada': return 'bg-red-50 text-red-700 border-red-200'
      default: return 'bg-slate-50 text-slate-700'
    }
  }

  const tabData = {
    proximas,
    pasadas,
    canceladas,
  }

  const currentList = tabData[tab]

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Mis Citas</h1>
          <p className="text-slate-500 mt-1">Gestiona tus consultas médicas</p>
        </div>
        <Button
          className="bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600"
          onClick={() => setModalOpen(true)}
        >
          <Plus className="h-4 w-4 mr-1" /> Agendar
        </Button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 bg-white p-1 rounded-xl border border-slate-200 w-fit">
        {(['proximas', 'pasadas', 'canceladas'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              tab === t ? 'bg-sky-50 text-sky-600' : 'text-slate-500 hover:text-slate-700'
            }`}
          >
            {t.charAt(0).toUpperCase() + t.slice(1)}
            {tabData[t].length > 0 && (
              <span className="ml-1.5 text-xs bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded-full">
                {tabData[t].length}
              </span>
            )}
          </button>
        ))}
      </div>

      {loading && (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-sky-500" />
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700 text-sm">
          {error}
        </div>
      )}

      {!loading && !error && currentList.length === 0 && (
        <div className="text-center py-12">
          <CalendarDays className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No tienes citas {tab}</p>
          <Button
            variant="outline"
            className="mt-4 border-sky-200 text-sky-600 hover:bg-sky-50"
            onClick={() => setModalOpen(true)}
          >
            <Plus className="h-4 w-4 mr-1" /> Agendar primera cita
          </Button>
        </div>
      )}

      {!loading && !error && currentList.length > 0 && (
        <div className="space-y-3">
          {currentList.map((cita) => (
            <Card key={cita.id} className="bg-white border-slate-100 hover:shadow-md transition-shadow">
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold text-slate-800">
                        {cita.motivo || 'Consulta médica'}
                      </h3>
                      <Badge variant="outline" className={getEstadoColor(cita.estado)}>
                        {cita.estado}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-4 text-sm text-slate-500">
                      <div className="flex items-center gap-1">
                        <CalendarDays className="h-4 w-4" />
                        <span>
                          {new Date(cita.fecha).toLocaleDateString('es-GT', {
                            weekday: 'short', month: 'short', day: 'numeric'
                          })}
                        </span>
                      </div>
                      <div className="flex items-center gap-1">
                        <Clock className="h-4 w-4" />
                        <span>{cita.hora_inicio?.slice(0, 5)}</span>
                      </div>
                    </div>
                    <p className="text-sm text-slate-500">
                      {cita.medico_nombre?.startsWith('Médico por')
                        ? cita.medico_nombre
                        : (() => { const n = cita.medico_nombre || ''; return /^Dr\.?\s|^Dra\.?\s/i.test(n) ? n : `Dr. ${n}` })()}
                    </p>
                    {cita.clinica_nombre && (
                      <p className="text-sm text-slate-500 flex items-center gap-1">
                        <MapPin className="h-3.5 w-3.5" />
                        {cita.clinica_nombre}
                      </p>
                    )}
                    {cita.estado === 'cancelada' && cita.motivo_cancelacion && (
                      <p className="text-sm text-red-600 mt-1">
                        <span className="font-medium">Motivo de cancelación:</span> {cita.motivo_cancelacion}
                      </p>
                    )}
                  </div>

                  {ESTADOS_CANCELABLES.includes(cita.estado) && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="text-red-600 border-red-200 hover:bg-red-50 shrink-0"
                      onClick={() => { setCitaACancelar(cita); setMotivoCancel('') }}
                    >
                      Cancelar
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <AgendarCitaModal
        pacienteId={perfil?.id}
        pacienteNombre={perfil?.nombre}
        paisIdProp={perfil?.pais_id}
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        onSuccess={() => refetch()}
      />

      {/* Modal de cancelación con motivo */}
      {citaACancelar && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-md overflow-hidden">
            <div className="flex items-center justify-between p-4 border-b border-slate-100">
              <h3 className="font-semibold text-slate-800">Cancelar cita</h3>
              <button
                onClick={() => { if (!cancelando) { setCitaACancelar(null); setMotivoCancel('') } }}
                className="text-slate-400 hover:text-slate-600"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="p-4 space-y-3">
              <p className="text-sm text-slate-600">
                Vas a cancelar tu cita
                {citaACancelar.fecha && (
                  <> del <strong>{new Date(citaACancelar.fecha).toLocaleDateString('es-GT', { weekday: 'long', month: 'long', day: 'numeric' })}</strong></>
                )}
                {citaACancelar.hora_inicio && <> a las <strong>{citaACancelar.hora_inicio.slice(0, 5)}</strong></>}.
                La clínica será notificada con tu explicación.
              </p>
              <label className="block text-sm font-medium text-slate-700">
                Motivo de la cancelación <span className="text-red-500">*</span>
              </label>
              <textarea
                value={motivoCancel}
                onChange={(e) => setMotivoCancel(e.target.value)}
                rows={4}
                maxLength={500}
                placeholder="Explica por qué cancelas la cita…"
                className="w-full rounded-lg border border-slate-200 p-3 text-sm focus:outline-none focus:ring-2 focus:ring-sky-300 resize-none"
                autoFocus
              />
            </div>
            <div className="flex items-center justify-end gap-2 p-4 border-t border-slate-100">
              <Button
                variant="outline"
                onClick={() => { setCitaACancelar(null); setMotivoCancel('') }}
                disabled={cancelando}
              >
                Volver
              </Button>
              <Button
                className="bg-red-600 hover:bg-red-700"
                onClick={handleConfirmarCancelacion}
                disabled={cancelando || !motivoCancel.trim()}
              >
                {cancelando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null}
                Confirmar cancelación
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
