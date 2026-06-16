import { useState } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppRecetas } from '@/webapp/hooks/useWebAppRecetas'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { FileText, Pill, ChevronDown, ChevronUp, Loader2 } from 'lucide-react'

export default function WebAppRecetas() {
  const { perfil } = useWebAppAuth()
  const { recetas, loading, error } = useWebAppRecetas(perfil?.id)
  const [expandedId, setExpandedId] = useState<number | null>(null)

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'activa': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
      case 'completada': return 'bg-blue-50 text-blue-700 border-blue-200'
      case 'vencida': return 'bg-amber-50 text-amber-700 border-amber-200'
      case 'cancelada': return 'bg-red-50 text-red-700 border-red-200'
      default: return 'bg-slate-50 text-slate-700'
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mis Recetas</h1>
        <p className="text-slate-500 mt-1">Tus recetas médicas digitales</p>
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

      {!loading && !error && recetas.length === 0 && (
        <div className="text-center py-12">
          <FileText className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No tienes recetas registradas</p>
        </div>
      )}

      {!loading && !error && recetas.length > 0 && (
        <div className="space-y-4">
          {recetas.map((r) => (
            <Card key={r.id} className="bg-white border-slate-100 hover:shadow-md transition-shadow">
              <CardContent className="p-4">
                <button
                  className="w-full text-left"
                  onClick={() => setExpandedId(expandedId === r.id ? null : r.id)}
                >
                  <div className="flex items-start justify-between">
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <h3 className="font-semibold text-slate-800">
                          Receta #{r.id}
                        </h3>
                        <Badge variant="outline" className={getEstadoColor(r.estado)}>
                          {r.estado}
                        </Badge>
                      </div>
                      <p className="text-sm text-slate-500">
                        {(() => { const n = r.medico_nombre || ''; return /^Dr\.?\s|^Dra\.?\s/i.test(n) ? n : `Dr. ${n}` })()}
                      </p>
                      <p className="text-xs text-slate-400">
                        {new Date(r.created_at).toLocaleDateString('es-GT', {
                          year: 'numeric', month: 'long', day: 'numeric'
                        })}
                      </p>
                    </div>
                    {expandedId === r.id ? (
                      <ChevronUp className="h-5 w-5 text-slate-400" />
                    ) : (
                      <ChevronDown className="h-5 w-5 text-slate-400" />
                    )}
                  </div>
                </button>

                {expandedId === r.id && (
                  <div className="mt-4 pt-4 border-t border-slate-100 space-y-3">
                    {r.instrucciones_generales && (
                      <p className="text-sm text-slate-600 bg-slate-50 p-3 rounded-lg">
                        <span className="font-medium">Instrucciones:</span> {r.instrucciones_generales}
                      </p>
                    )}

                    <div className="space-y-2">
                      <h4 className="text-sm font-medium text-slate-700 flex items-center gap-1">
                        <Pill className="h-4 w-4" /> Medicamentos
                      </h4>
                      {r.items.map((item) => (
                        <div
                          key={item.id}
                          className="bg-slate-50 rounded-lg p-3 text-sm"
                        >
                          <p className="font-medium text-slate-800">{item.nombre_medicamento}</p>
                          <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1 text-slate-500">
                            <span>Dosis: {item.dosis}</span>
                            <span>Frecuencia: {item.frecuencia}</span>
                            {item.duracion && <span>Duración: {item.duracion}</span>}
                            <span>Cantidad: {item.cantidad}</span>
                          </div>
                          {item.instrucciones && (
                            <p className="text-slate-500 mt-1">{item.instrucciones}</p>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
