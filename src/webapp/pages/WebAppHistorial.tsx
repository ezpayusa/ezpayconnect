import { useState } from 'react'
import { openSignedUrl } from '@/lib/signedUrl'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppHistorial } from '@/webapp/hooks/useWebAppHistorial'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  CalendarDays, FileText, FlaskConical, Stethoscope, Clock,
  ChevronDown, ChevronUp, Pill, Download
} from 'lucide-react'
import type { HistorialItem } from '@/webapp/types/webapp.types'

export default function WebAppHistorial() {
  const { perfil } = useWebAppAuth()
  const { items, loading, error } = useWebAppHistorial(perfil?.id)
  const [expandedId, setExpandedId] = useState<number | null>(null)

  const getIcono = (tipo: string) => {
    switch (tipo) {
      case 'cita': return <CalendarDays className="h-5 w-5 text-white" />
      case 'receta': return <FileText className="h-5 w-5 text-white" />
      case 'examen': return <FlaskConical className="h-5 w-5 text-white" />
      default: return <Stethoscope className="h-5 w-5 text-white" />
    }
  }

  const getColor = (tipo: string) => {
    switch (tipo) {
      case 'cita': return 'bg-sky-500'
      case 'receta': return 'bg-emerald-500'
      case 'examen': return 'bg-amber-500'
      default: return 'bg-slate-500'
    }
  }

  const getEstadoBadge = (estado: string) => {
    switch (estado) {
      case 'completada':
      case 'completado':
        return <Badge className="bg-emerald-50 text-emerald-700 border-emerald-200">Completado</Badge>
      case 'activa':
        return <Badge className="bg-sky-50 text-sky-700 border-sky-200">Activa</Badge>
      case 'pendiente':
        return <Badge className="bg-amber-50 text-amber-700 border-amber-200">Pendiente</Badge>
      case 'cancelada':
        return <Badge className="bg-red-50 text-red-700 border-red-200">Cancelada</Badge>
      default:
        return <Badge variant="outline">{estado}</Badge>
    }
  }

  const formatearFecha = (fecha: string) => {
    return new Date(fecha).toLocaleDateString('es-GT', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
  }

  // Agrupar items por fecha
  const grouped = items.reduce((acc: Record<string, HistorialItem[]>, item) => {
    const key = item.fecha
    if (!acc[key]) acc[key] = []
    acc[key].push(item)
    return acc
  }, {})

  const fechasOrdenadas = Object.keys(grouped).sort((a, b) =>
    new Date(b).getTime() - new Date(a).getTime()
  )

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Historial Médico</h1>
        <p className="text-slate-500 mt-1">
          {items.length > 0
            ? `${items.length} eventos registrados`
            : 'Tu timeline de atención médica completa'}
        </p>
      </div>

      {loading && (
        <div className="flex items-center justify-center py-12">
          <Clock className="h-8 w-8 animate-spin text-sky-500" />
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700 text-sm">
          {error}
        </div>
      )}

      {!loading && !error && items.length === 0 && (
        <div className="text-center py-12 bg-white rounded-xl border border-slate-100">
          <Stethoscope className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No tienes eventos en tu historial aún</p>
          <p className="text-sm text-slate-400 mt-1">
            Las citas, recetas y exámenes aparecerán aquí automáticamente
          </p>
        </div>
      )}

      {!loading && !error && items.length > 0 && (
        <div className="space-y-8">
          {fechasOrdenadas.map((fecha) => (
            <div key={fecha}>
              {/* Fecha header */}
              <div className="flex items-center gap-3 mb-4">
                <div className="h-px flex-1 bg-slate-200" />
                <span className="text-sm font-medium text-slate-500 bg-slate-50 px-3 py-1 rounded-full">
                  {formatearFecha(fecha)}
                </span>
                <div className="h-px flex-1 bg-slate-200" />
              </div>

              {/* Items de esa fecha */}
              <div className="space-y-3">
                {grouped[fecha].map((item) => {
                  const isExpanded = expandedId === item.id
                  return (
                    <div
                      key={item.id}
                      className="bg-white rounded-xl border border-slate-100 hover:shadow-md transition-shadow"
                    >
                      <button
                        className="w-full text-left p-4"
                        onClick={() => setExpandedId(isExpanded ? null : item.id)}
                      >
                        <div className="flex items-start gap-4">
                          {/* Icono */}
                          <div className={`w-10 h-10 rounded-xl ${getColor(item.tipo)} flex items-center justify-center shrink-0`}>
                            {getIcono(item.tipo)}
                          </div>

                          {/* Contenido */}
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center justify-between gap-2">
                              <h3 className="font-semibold text-slate-800 truncate">
                                {item.titulo}
                              </h3>
                              {isExpanded ? (
                                <ChevronUp className="h-4 w-4 text-slate-400 shrink-0" />
                              ) : (
                                <ChevronDown className="h-4 w-4 text-slate-400 shrink-0" />
                              )}
                            </div>

                            <p className="text-sm text-slate-500 mt-0.5">{item.descripcion}</p>

                            <div className="flex items-center gap-2 mt-2 flex-wrap">
                              {item.medico_nombre && (
                                <span className="text-xs text-slate-400">
                                  {(() => { const n = item.medico_nombre || ''; return /^Dr\.?\s|^Dra\.?\s/i.test(n) ? n : `Dr. ${n}` })()}
                                </span>
                              )}
                              {item.detalles?.estado && getEstadoBadge(item.detalles.estado)}
                            </div>
                          </div>
                        </div>
                      </button>

                      {/* Detalles expandibles */}
                      {isExpanded && item.detalles && (
                        <div className="px-4 pb-4 pt-0">
                          <div className="ml-14 bg-slate-50 rounded-lg p-3 space-y-2">
                            {/* Detalles de receta */}
                            {item.tipo === 'receta' && item.detalles.items && (
                              <div className="space-y-2">
                                <p className="text-xs font-medium text-slate-600 flex items-center gap-1">
                                  <Pill className="h-3.5 w-3.5" /> Medicamentos
                                </p>
                                {(item.detalles.items as any[]).map((med: any) => (
                                  <div key={med.id} className="text-xs text-slate-600 bg-white rounded p-2">
                                    <span className="font-medium">{med.nombre_medicamento}</span>
                                    <span className="text-slate-400 ml-2">
                                      {med.dosis} · {med.frecuencia}
                                      {med.cantidad > 1 && ` · Cant: ${med.cantidad}`}
                                    </span>
                                  </div>
                                ))}
                              </div>
                            )}

                            {/* Detalles de examen */}
                            {item.tipo === 'examen' && (
                              <div className="space-y-1">
                                {item.detalles.resultados && (
                                  <p className="text-xs text-slate-600">
                                    <span className="font-medium">Resultados:</span> {item.detalles.resultados}
                                  </p>
                                )}
                                {item.detalles.archivo_url && (
                                  <button
                                    type="button"
                                    className="inline-flex items-center gap-1 text-xs text-sky-600 hover:underline"
                                    onClick={(e) => { e.stopPropagation(); openSignedUrl('resultados-examenes', item.detalles.archivo_url) }}
                                  >
                                    <Download className="h-3 w-3" />
                                    Ver archivo adjunto
                                  </button>
                                )}
                              </div>
                            )}

                            {/* Detalles de cita */}
                            {item.tipo === 'cita' && item.detalles.notas && (
                              <p className="text-xs text-slate-600">
                                <span className="font-medium">Notas:</span> {item.detalles.notas}
                              </p>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
