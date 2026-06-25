import { AlertTriangle, Building2, FileWarning } from 'lucide-react'
import type { FaltanteReconciliacion } from '@/farmacia/hooks/useEntregasMonitoreo'

// Panel/alerta SEPARADO (reconciliar_entregas_faltantes, discrepancia #2): grupos delivery despachados SIN entrega.
// Separado de la lista porque la fila NO existe en `entregas` (no es una entrega editable).
export default function ReconciliacionPanel({ faltantes }: { faltantes: FaltanteReconciliacion[] }) {
  if (faltantes.length === 0) {
    return (
      <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700">
        Sin entregas faltantes a reconciliar. Todo lo despachado como delivery tiene su entrega.
      </div>
    )
  }
  return (
    <div className="space-y-3">
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 flex items-center gap-2">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        <span><b>{faltantes.length}</b> grupo(s) despachado(s) como delivery <b>sin entrega</b>. Requieren reconciliación.</span>
      </div>
      <div className="space-y-2">
        {faltantes.map((f) => (
          <div key={`${f.receta_base_id}-${f.farmacia_id}`} className="rounded-lg border border-gray-100 bg-white p-3 flex items-center gap-3">
            <FileWarning className="h-5 w-5 text-amber-500 shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-[#1a2a3a]">Receta #{f.receta_base_id}</p>
              <p className="text-xs text-[#8a9aaa] flex items-center gap-1">
                <Building2 className="h-3 w-3" /> {f.sucursal_nombre ?? `Sucursal ${f.farmacia_id}`}
              </p>
            </div>
            {f.fallo_log && (
              <span className="text-[10px] font-semibold text-amber-700 bg-amber-100 border border-amber-200 rounded-full px-2 py-0.5 shrink-0">
                fallo auto-create
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
