import { FlaskConical } from 'lucide-react'

export default function WebAppExamenes() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mis Exámenes</h1>
        <p className="text-slate-500 mt-1">Resultados de laboratorio y estudios</p>
      </div>
      <div className="text-center py-12">
        <FlaskConical className="h-12 w-12 text-slate-300 mx-auto mb-3" />
        <p className="text-slate-500">No tienes exámenes registrados</p>
      </div>
    </div>
  )
}
