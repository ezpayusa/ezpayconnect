import { useState } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppCitas } from '@/webapp/hooks/useWebAppCitas'
import AgendarCitaModal from '@/webapp/components/AgendarCitaModal'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { CalendarDays, Clock, Plus, Loader2 } from 'lucide-react'

export default function WebAppCitas() {
  const { perfil } = useWebAppAuth()
  const { citas, proximas, pasadas, canceladas, loading, error, refetch } = useWebAppCitas(perfil?.id)
  const [tab, setTab] = useState<'proximas' | 'pasadas' | 'canceladas'>('proximas')
  const [modalOpen, setModalOpen] = useState(false)

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'agendada': return 'bg-sky-50 text-sky-700 border-sky-200'
      case 'confirmada': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
      case 'en_curso': return 'bg-amber-50 text-amber-700 border-amber-200'
      case 'pendiente': return 'bg-yellow-50 text-yellow-700 border-yellow-200'
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
                        <Building className="h-3.5 w-3.5" />
                        {cita.clinica_nombre}
                      </p>
                    )}
                  </div>
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
    </div>
  )
}
