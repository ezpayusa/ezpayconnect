import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppExamenes } from '@/webapp/hooks/useWebAppExamenes'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { FlaskConical, Calendar, FileText, Loader2 } from 'lucide-react'

export default function WebAppExamenes() {
  const { perfil } = useWebAppAuth()
  const { examenes, loading, error } = useWebAppExamenes(perfil?.id)

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'pendiente': return 'bg-amber-50 text-amber-700 border-amber-200'
      case 'completado': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
      case 'revision': return 'bg-sky-50 text-sky-700 border-sky-200'
      default: return 'bg-slate-50 text-slate-700'
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mis Exámenes</h1>
        <p className="text-slate-500 mt-1">Resultados de laboratorio y estudios</p>
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

      {!loading && !error && examenes.length === 0 && (
        <div className="text-center py-12">
          <FlaskConical className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No tienes exámenes registrados</p>
        </div>
      )}

      {!loading && !error && examenes.length > 0 && (
        <div className="space-y-3">
          {examenes.map((ex) => (
            <Card key={ex.id} className="bg-white border-slate-100 hover:shadow-md transition-shadow">
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold text-slate-800">{ex.tipo}</h3>
                      <Badge variant="outline" className={getEstadoColor(ex.estado)}>
                        {ex.estado}
                      </Badge>
                    </div>
                    {ex.descripcion && (
                      <p className="text-sm text-slate-500">{ex.descripcion}</p>
                    )}
                    <div className="flex items-center gap-4 text-sm text-slate-500">
                      <div className="flex items-center gap-1">
                        <Calendar className="h-4 w-4" />
                        <span>
                          {new Date(ex.fecha).toLocaleDateString('es-GT', {
                            year: 'numeric', month: 'long', day: 'numeric'
                          })}
                        </span>
                      </div>
                    </div>
                    <p className="text-sm text-slate-500">
                      Dr. {ex.medico_nombre}
                    </p>
                  </div>
                </div>

                {ex.resultados && (
                  <div className="mt-3 pt-3 border-t border-slate-100">
                    <p className="text-sm text-slate-600 flex items-start gap-2">
                      <FileText className="h-4 w-4 mt-0.5 shrink-0" />
                      <span>{ex.resultados}</span>
                    </p>
                  </div>
                )}

                {ex.archivo_url && (
                  <div className="mt-2">
                    <a
                      href={ex.archivo_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-sm text-sky-600 hover:underline"
                    >
                      Ver archivo adjunto →
                    </a>
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
