import { Clock } from 'lucide-react'

export default function WebAppHistorial() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Historial Médico</h1>
        <p className="text-slate-500 mt-1">Tu timeline de atención médica completa</p>
      </div>
      <div className="text-center py-12">
        <Clock className="h-12 w-12 text-slate-300 mx-auto mb-3" />
        <p className="text-slate-500">Tu historial aparecerá aquí</p>
      </div>
    </div>
  )
}
