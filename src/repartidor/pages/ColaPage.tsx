import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronRight, Inbox, RefreshCw, AlertTriangle, CheckCircle2, MapPin } from 'lucide-react'
import { useEntregasRepartidor } from '@/repartidor/hooks/useEntregasRepartidor'
import { colorEstado, LABEL_ESTADO } from '@/repartidor/lib/estados'
import type { EstadoEntrega } from '@/repartidor/types'

const FILTROS: { value: EstadoEntrega | 'todas'; label: string }[] = [
  { value: 'todas', label: 'Todas' },
  { value: 'asignada', label: 'Asignadas' },
  { value: 'en_camino', label: 'En camino' },
  { value: 'entregada', label: 'Entregadas' },
  { value: 'fallida', label: 'Fallidas' },
]

export default function ColaPage() {
  const navigate = useNavigate()
  const { entregas, loading, error, offline, recargar } = useEntregasRepartidor()
  const [filtro, setFiltro] = useState<EstadoEntrega | 'todas'>('todas')

  const aplicarFiltro = (f: EstadoEntrega | 'todas') => {
    setFiltro(f)
    void recargar(f === 'todas' ? undefined : { estado: f })
  }

  return (
    <div className="space-y-4">
      {/* Filtros */}
      <div className="flex gap-2 overflow-x-auto pb-1 -mx-1 px-1">
        {FILTROS.map((f) => (
          <button
            key={f.value}
            type="button"
            onClick={() => aplicarFiltro(f.value)}
            className={`whitespace-nowrap rounded-full px-3 py-1 text-sm border transition-colors ${
              filtro === f.value
                ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]'
                : 'bg-white text-gray-600 border-gray-200'
            }`}
          >
            {f.label}
          </button>
        ))}
        <button
          type="button"
          onClick={() => aplicarFiltro(filtro)}
          aria-label="Recargar"
          className="ml-auto rounded-full p-1.5 text-gray-500 hover:text-[#1E5C8E]"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {offline && (
        <div className="rounded-md bg-amber-50 border border-amber-200 text-amber-800 text-sm px-3 py-2">
          Mostrando la última cola en caché (sin conexión). Las acciones requieren red.
        </div>
      )}

      {/* Loading */}
      {loading && entregas.length === 0 && (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-20 rounded-lg bg-white border border-gray-100 animate-pulse" />
          ))}
        </div>
      )}

      {/* Error */}
      {!loading && error && (
        <div className="rounded-lg bg-red-50 border border-red-200 p-4 text-sm text-red-700 flex items-start gap-2">
          <AlertTriangle className="h-5 w-5 shrink-0" />
          <div className="flex-1">
            <p className="font-medium">No se pudo cargar tu cola.</p>
            <p className="opacity-80">{error}</p>
            <button type="button" onClick={() => aplicarFiltro(filtro)} className="mt-2 underline">
              Reintentar
            </button>
          </div>
        </div>
      )}

      {/* Empty */}
      {!loading && !error && entregas.length === 0 && (
        <div className="rounded-lg bg-white border border-gray-100 p-8 text-center text-gray-500">
          <Inbox className="h-10 w-10 mx-auto mb-2 opacity-40" />
          <p className="font-medium">No tenés entregas asignadas.</p>
          <p className="text-sm opacity-80">Cuando te asignen una, aparecerá acá.</p>
        </div>
      )}

      {/* Lista */}
      {entregas.map((e) => (
        <button
          key={e.entrega_id}
          type="button"
          onClick={() => navigate(`/repartidor/entrega/${e.entrega_id}`)}
          className="w-full text-left rounded-lg bg-white border border-gray-100 shadow-sm p-3 flex items-center gap-3 active:bg-gray-50"
        >
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span className={`text-xs font-medium px-2 py-0.5 rounded-full border ${colorEstado(e.estado)}`}>
                {LABEL_ESTADO[e.estado]}
              </span>
              {e.cobrado && (
                <span className="flex items-center gap-1 text-xs text-emerald-600">
                  <CheckCircle2 className="h-3.5 w-3.5" /> Cobrado
                </span>
              )}
            </div>
            <p className="text-sm font-medium text-gray-800 truncate">
              {e.sucursal_nombre ?? `Sucursal ${e.farmacia_id}`}
            </p>
            <p className="text-xs text-gray-500 truncate flex items-center gap-1">
              <MapPin className="h-3 w-3 shrink-0" />
              {e.direccion_entrega ?? 'Sin dirección'}
            </p>
          </div>
          <div className="text-right shrink-0">
            {e.monto != null && <p className="text-sm font-semibold text-gray-800">Q{Number(e.monto).toFixed(2)}</p>}
            <ChevronRight className="h-5 w-5 text-gray-300 ml-auto" />
          </div>
        </button>
      ))}
    </div>
  )
}
