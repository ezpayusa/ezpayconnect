import { Card, CardContent } from '@/components/ui/card'
import { Building2, TrendingUp, Banknote, RefreshCw, AlertTriangle } from 'lucide-react'
import type { StatsSucursal } from '@/farmacia/hooks/useEntregasMonitoreo'

// Tarjetas por sucursal (stats_entregas_sucursal). Q1: el exento ve N filas (todas sus sucursales); el confinable, una.
export default function StatsSucursales({ stats }: { stats: StatsSucursal[] }) {
  if (stats.length === 0) {
    return <p className="text-sm text-[#8a9aaa] text-center py-8">Sin datos en el rango seleccionado.</p>
  }
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
      {stats.map((s) => {
        const disc = s.disc_monto + s.disc_cobrada_fallida
        return (
          <Card key={s.farmacia_id} className="border-[#1E5C8E]/15">
            <CardContent className="p-4 space-y-3">
              <div className="flex items-center justify-between">
                <p className="font-semibold text-[#1a2a3a] flex items-center gap-1.5 min-w-0">
                  <Building2 className="h-4 w-4 text-[#1E5C8E] shrink-0" />
                  <span className="truncate">{s.sucursal_nombre ?? `Sucursal ${s.farmacia_id}`}</span>
                </p>
                <span className="text-xs text-[#8a9aaa]">{s.total} total</span>
              </div>

              <div className="grid grid-cols-5 gap-1 text-center text-xs">
                {([['Pend.', s.pendiente], ['Asig.', s.asignada], ['Camino', s.en_camino], ['Entreg.', s.entregada], ['Fallida', s.fallida]] as const).map(([l, n]) => (
                  <div key={l} className="rounded-md bg-[#f4f8fc] py-1.5">
                    <p className="font-bold text-[#1a2a3a]">{n}</p>
                    <p className="text-[#8a9aaa]">{l}</p>
                  </div>
                ))}
              </div>

              <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-[#5a6a7a]">
                <span className="flex items-center gap-1"><TrendingUp className="h-3.5 w-3.5 text-emerald-600" /> Éxito: <b>{s.pct_exito != null ? `${s.pct_exito}%` : '—'}</b></span>
                <span className="flex items-center gap-1"><Banknote className="h-3.5 w-3.5 text-[#1E5C8E]" /> Cobrado: <b>Q{Number(s.monto_cobrado).toFixed(2)}</b></span>
                <span className="flex items-center gap-1"><RefreshCw className="h-3.5 w-3.5 text-amber-600" /> Reintentos: <b>{s.reintentos}</b></span>
                {disc > 0 && (
                  <span className="flex items-center gap-1 text-amber-700"><AlertTriangle className="h-3.5 w-3.5" /> Discrepancias: <b>{disc}</b></span>
                )}
              </div>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}
