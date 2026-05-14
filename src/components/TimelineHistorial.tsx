import { useState } from 'react'
import { useHistorialCompleto } from '@/hooks/useHistorialCompleto'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { 
  Stethoscope, Calendar, FileText, Filter, RefreshCw,
  ChevronDown, ChevronUp, Clock, CheckCircle, XCircle, AlertCircle
} from 'lucide-react'

interface Props {
  pacienteId: number
}

const filtros = [
  { value: 'todos', label: 'Todos', color: 'bg-[#1a2a3a]' },
  { value: 'consulta', label: 'Consultas', color: 'bg-[#1E5C8E]' },
  { value: 'cita', label: 'Citas', color: 'bg-[#3A8ABF]' },
  { value: 'receta', label: 'Recetas', color: 'bg-[#f59e0b]' },
]

const getIcono = (tipo: string, color: string) => {
  const className = `h-5 w-5 text-white`
  switch (tipo) {
    case 'consulta': return <Stethoscope className={className} />
    case 'cita': return <Calendar className={className} />
    case 'receta': return <FileText className={className} />
    default: return <Stethoscope className={className} />
  }
}

const getEstadoIcono = (estado?: string) => {
  switch (estado) {
    case 'completada': return <CheckCircle className="h-4 w-4 text-green-500" />
    case 'cancelada': return <XCircle className="h-4 w-4 text-red-500" />
    case 'agendada': return <Clock className="h-4 w-4 text-blue-500" />
    default: return <AlertCircle className="h-4 w-4 text-gray-400" />
  }
}

export default function TimelineHistorial({ pacienteId }: Props) {
  const { eventosFiltrados, loading, filtro, setFiltro, stats, recargar } = useHistorialCompleto(pacienteId)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  const formatFecha = (fecha: string) => {
    const date = new Date(fecha)
    return {
      dia: date.getDate(),
      mes: date.toLocaleDateString('es-GT', { month: 'short' }).toUpperCase(),
      año: date.getFullYear(),
      completa: date.toLocaleDateString('es-GT', { 
        weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' 
      })
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Stats cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: 'Total Eventos', value: stats.total, color: 'bg-[#1a2a3a]' },
          { label: 'Consultas', value: stats.consultas, color: 'bg-[#1E5C8E]' },
          { label: 'Citas', value: stats.citas, color: 'bg-[#3A8ABF]' },
          { label: 'Recetas', value: stats.recetas, color: 'bg-[#f59e0b]' },
        ].map((stat, i) => (
          <Card key={i} className={`${stat.color} text-white`}>
            <CardContent className="p-4 text-center">
              <p className="text-2xl font-bold">{stat.value}</p>
              <p className="text-xs opacity-90">{stat.label}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Filtros */}
      <div className="flex flex-wrap items-center gap-2">
        <Filter className="h-4 w-4 text-[#8a9aaa]" />
        {filtros.map(f => (
          <button
            key={f.value}
            onClick={() => setFiltro(f.value)}
            className={`px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
              filtro === f.value
                ? `${f.color} text-white shadow-sm`
                : 'bg-[#e8f0f8] text-[#8a9aaa] hover:text-[#1a2a3a]'
            }`}
          >
            {f.label}
          </button>
        ))}
        <Button variant="ghost" size="sm" onClick={recargar} className="ml-auto">
          <RefreshCw className="h-4 w-4 mr-1" /> Actualizar
        </Button>
      </div>

      {/* Timeline */}
      {eventosFiltrados.length === 0 ? (
        <Card className="bg-[#f8fafc]">
          <CardContent className="p-12 text-center">
            <Stethoscope className="h-12 w-12 mx-auto mb-4 text-[#8a9aaa]" />
            <p className="text-[#8a9aaa]">No hay eventos en el historial</p>
          </CardContent>
        </Card>
      ) : (
        <div className="relative">
          {/* Línea vertical del timeline */}
          <div className="absolute left-6 top-0 bottom-0 w-0.5 bg-[#e8f0f8]" />

          <div className="space-y-4">
            {eventosFiltrados.map((evento, index) => {
              const fecha = formatFecha(evento.fecha)
              const isExpanded = expandedId === evento.id

              return (
                <div key={evento.id} className="relative flex gap-4">
                  {/* Punto del timeline */}
                  <div 
                    className="relative z-10 w-12 h-12 rounded-full flex items-center justify-center shadow-md"
                    style={{ backgroundColor: evento.color }}
                  >
                    {getIcono(evento.tipo, evento.color)}
                  </div>

                  {/* Contenido */}
                  <Card className={`flex-1 hover:shadow-md transition-shadow ${isExpanded ? 'ring-2 ring-[#1E5C8E]' : ''}`}>
                    <CardContent className="p-4">
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          {/* Fecha y tipo */}
                          <div className="flex items-center gap-2 mb-2">
                            <Badge 
                              variant="outline" 
                              className="text-xs"
                              style={{ borderColor: evento.color, color: evento.color }}
                            >
                              {evento.tipo.toUpperCase()}
                            </Badge>
                            {evento.estado && (
                              <div className="flex items-center gap-1">
                                {getEstadoIcono(evento.estado)}
                                <span className="text-xs text-[#8a9aaa]">{evento.estado}</span>
                              </div>
                            )}
                          </div>

                          {/* Título */}
                          <h3 className="font-medium text-[#1a2a3a] mb-1">{evento.titulo}</h3>

                          {/* Descripción */}
                          <p className="text-sm text-[#8a9aaa]">{evento.descripcion}</p>

                          {/* Fecha */}
                          <p className="text-xs text-[#8a9aaa] mt-2">
                            {fecha.completa}
                          </p>

                          {/* Contenido expandido */}
                          {isExpanded && evento.metadata && (
                            <div className="mt-4 pt-4 border-t space-y-3">
                              {evento.metadata.tratamiento && (
                                <div>
                                  <p className="text-xs font-medium text-[#1E5C8E]">Tratamiento:</p>
                                  <p className="text-sm">{evento.metadata.tratamiento}</p>
                                </div>
                              )}
                              {evento.metadata.examenes && (
                                <div>
                                  <p className="text-xs font-medium text-[#1E5C8E]">Exámenes:</p>
                                  <p className="text-sm">{evento.metadata.examenes}</p>
                                </div>
                              )}
                              {evento.metadata.notas && (
                                <div className="p-3 bg-[#e8f0f8] rounded-lg">
                                  <p className="text-xs font-medium text-[#1E5C8E]">Notas:</p>
                                  <p className="text-sm">{evento.metadata.notas}</p>
                                </div>
                              )}
                              {evento.metadata.items && evento.metadata.items.length > 0 && (
                                <div>
                                  <p className="text-xs font-medium text-[#1E5C8E]">Medicamentos:</p>
                                  <ul className="text-sm space-y-1">
                                    {evento.metadata.items.map((item: any, i: number) => (
                                      <li key={i}>
                                        • {item.nombre_medicamento} - {item.dosis} ({item.frecuencia})
                                      </li>
                                    ))}
                                  </ul>
                                </div>
                              )}
                            </div>
                          )}
                        </div>

                        {/* Botón expandir */}
                        <button
                          onClick={() => setExpandedId(isExpanded ? null : evento.id)}
                          className="ml-2 p-1 hover:bg-[#e8f0f8] rounded transition-colors"
                        >
                          {isExpanded ? (
                            <ChevronUp className="h-5 w-5 text-[#8a9aaa]" />
                          ) : (
                            <ChevronDown className="h-5 w-5 text-[#8a9aaa]" />
                          )}
                        </button>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
