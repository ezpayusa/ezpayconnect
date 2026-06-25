import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronRight, PackageOpen, RefreshCw, AlertTriangle, CheckCircle2, MapPin, WifiOff } from 'lucide-react'
import { useEntregasRepartidor } from '@/repartidor/hooks/useEntregasRepartidor'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { colorEstado, LABEL_ESTADO } from '@/repartidor/lib/estados'
import { folioEntrega } from '@/repartidor/lib/folio'
import type { EntregaRepartidor, EstadoEntrega } from '@/repartidor/types'

const CHIPS: { value: EstadoEntrega | 'todas'; label: string }[] = [
  { value: 'todas', label: 'Todas' },
  { value: 'en_camino', label: 'En camino' },
  { value: 'asignada', label: 'Asignada' },
  { value: 'entregada', label: 'Entregada' },
]

function saludo(): string {
  const h = new Date().getHours()
  if (h < 12) return 'Buenos días'
  if (h < 19) return 'Buenas tardes'
  return 'Buenas noches'
}

function iniciales(nombre?: string | null): string {
  if (!nombre) return '··'
  const partes = nombre.trim().split(/\s+/)
  return ((partes[0]?.[0] ?? '') + (partes[1]?.[0] ?? '')).toUpperCase() || '··'
}

function esActiva(e: EntregaRepartidor): boolean {
  return e.estado === 'asignada' || e.estado === 'en_camino'
}

export default function ColaPage() {
  const navigate = useNavigate()
  const { cuenta } = useProveedorAuth()
  const { entregas, loading, error, offline, lastUpdated, recargar } = useEntregasRepartidor()
  const [filtro, setFiltro] = useState<EstadoEntrega | 'todas'>('todas')

  const aplicarFiltro = (f: EstadoEntrega | 'todas') => {
    setFiltro(f)
    void recargar(f === 'todas' ? undefined : { estado: f })
  }

  const activas = useMemo(() => entregas.filter(esActiva), [entregas])
  const mas = useMemo(() => entregas.filter((e) => !esActiva(e)), [entregas])

  const tarjeta = (e: EntregaRepartidor) => (
    <button
      key={e.entrega_id}
      type="button"
      onClick={() => navigate(`/repartidor/entrega/${e.entrega_id}`)}
      className="w-full text-left rounded-2xl bg-white border border-gray-100 shadow-sm p-4 flex items-center gap-3 active:scale-[0.99] transition-transform"
    >
      <div className="flex-1 min-w-0 space-y-1.5">
        <div className="flex items-center gap-2">
          <span className={`text-xs font-semibold px-2 py-0.5 rounded-full border ${colorEstado(e.estado)}`}>
            {LABEL_ESTADO[e.estado]}
          </span>
          <span className="text-[10px] font-semibold tracking-wide px-1.5 py-0.5 rounded bg-[#1E5C8E]/10 text-[#1E5C8E]">
            DELIVERY
          </span>
          <span className="ml-auto text-xs font-mono text-gray-400">{folioEntrega(e.entrega_id)}</span>
        </div>
        <p className="text-sm font-medium text-gray-800 truncate">{e.sucursal_nombre ?? `Sucursal ${e.farmacia_id}`}</p>
        <p className="text-xs text-gray-500 truncate flex items-center gap-1">
          <MapPin className="h-3.5 w-3.5 shrink-0 text-gray-400" />
          {e.direccion_entrega ?? 'Sin dirección'}
        </p>
        {e.monto != null && (
          <p className="text-sm">
            {e.cobrado ? (
              <span className="text-emerald-600 font-semibold inline-flex items-center gap-1">
                <CheckCircle2 className="h-4 w-4" /> Cobrado Q{Number(e.monto).toFixed(2)}
              </span>
            ) : (
              <span className="text-gray-700 font-semibold">A cobrar Q{Number(e.monto).toFixed(2)}</span>
            )}
          </p>
        )}
      </div>
      <ChevronRight className="h-5 w-5 text-gray-300 shrink-0" />
    </button>
  )

  return (
    <div className="space-y-5">
      {/* Saludo + avatar */}
      <div className="flex items-center gap-3">
        <div className="h-11 w-11 rounded-full bg-[#1E5C8E] text-white grid place-items-center font-semibold shrink-0">
          {iniciales(cuenta?.nombre_completo)}
        </div>
        <div className="min-w-0">
          <p className="text-sm text-gray-500">{saludo()}</p>
          <p className="font-semibold text-gray-800 truncate">{cuenta?.nombre_completo ?? 'Repartidor'}</p>
        </div>
      </div>

      {/* Barra de stats */}
      <div className="rounded-2xl bg-[#1E5C8E] text-white px-4 py-3 flex items-center gap-4">
        <div>
          <p className="text-2xl font-bold leading-none">{entregas.length}</p>
          <p className="text-xs opacity-80 mt-1">entregas</p>
        </div>
        <div className="h-8 w-px bg-white/20" />
        <div>
          <p className="text-2xl font-bold leading-none">{activas.length}</p>
          <p className="text-xs opacity-80 mt-1">activas</p>
        </div>
        <button
          type="button"
          onClick={() => aplicarFiltro(filtro)}
          aria-label="Actualizar"
          className="ml-auto rounded-full p-2 bg-white/10 active:bg-white/20"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* Chips de filtro */}
      <div className="flex gap-2 overflow-x-auto -mx-1 px-1 pb-1">
        {CHIPS.map((c) => (
          <button
            key={c.value}
            type="button"
            onClick={() => aplicarFiltro(c.value)}
            className={`whitespace-nowrap rounded-full px-3.5 py-1.5 text-sm font-medium border transition-colors ${
              filtro === c.value ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]' : 'bg-white text-gray-600 border-gray-200'
            }`}
          >
            {c.label}
          </button>
        ))}
      </div>

      {/* Offline / última actualización */}
      {offline && (
        <div className="rounded-xl bg-amber-50 border border-amber-200 text-amber-800 text-sm px-3 py-2 flex items-center gap-2">
          <WifiOff className="h-4 w-4 shrink-0" />
          <span>Mostrando la última lista guardada{lastUpdated ? ` · ${lastUpdated}` : ''}. Las acciones requieren conexión.</span>
        </div>
      )}
      {!offline && lastUpdated && !loading && (
        <p className="text-xs text-gray-400 -mt-2">Última actualización {lastUpdated}</p>
      )}

      {/* Loading */}
      {loading && entregas.length === 0 && (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => <div key={i} className="h-24 rounded-2xl bg-white border border-gray-100 animate-pulse" />)}
        </div>
      )}

      {/* Error */}
      {!loading && error && (
        <div className="rounded-2xl bg-red-50 border border-red-200 p-4 text-sm text-red-700">
          <div className="flex items-start gap-2">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div className="flex-1">
              <p className="font-medium">No se pudo cargar tu lista.</p>
              <p className="opacity-80">Revisá tu conexión e intentá de nuevo.</p>
            </div>
          </div>
          <button type="button" onClick={() => aplicarFiltro(filtro)} className="mt-3 w-full rounded-lg bg-red-600 text-white py-2 font-medium">
            Reintentar
          </button>
        </div>
      )}

      {/* Empty */}
      {!loading && !error && entregas.length === 0 && (
        <div className="rounded-2xl bg-white border border-gray-100 p-10 text-center">
          <div className="h-16 w-16 mx-auto mb-3 rounded-full bg-gray-50 grid place-items-center">
            <PackageOpen className="h-8 w-8 text-gray-300" />
          </div>
          <p className="font-semibold text-gray-700">No tenés entregas asignadas</p>
          <p className="text-sm text-gray-500 mt-1">Cuando te asignen una, aparecerá acá.</p>
          <button type="button" onClick={() => aplicarFiltro(filtro)} className="mt-4 inline-flex items-center gap-1 text-[#1E5C8E] font-medium">
            <RefreshCw className="h-4 w-4" /> Actualizar
          </button>
        </div>
      )}

      {/* Secciones (sin filtro) o lista única (con filtro) */}
      {!loading && !error && entregas.length > 0 &&
        (filtro === 'todas' ? (
          <div className="space-y-5">
            {activas.length > 0 && (
              <section className="space-y-3">
                <h2 className="text-xs font-semibold tracking-wider text-gray-400">ACTIVAS</h2>
                {activas.map(tarjeta)}
              </section>
            )}
            {mas.length > 0 && (
              <section className="space-y-3">
                <h2 className="text-xs font-semibold tracking-wider text-gray-400">MÁS</h2>
                {mas.map(tarjeta)}
              </section>
            )}
          </div>
        ) : (
          <div className="space-y-3">{entregas.map(tarjeta)}</div>
        ))}
    </div>
  )
}
