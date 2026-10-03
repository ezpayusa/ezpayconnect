import { lazy, Suspense, useCallback, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  ChevronRight, PackageOpen, RefreshCw, AlertTriangle, CheckCircle2, MapPin, WifiOff, Navigation, List, Map as MapIcon, Coffee, Loader2,
} from 'lucide-react'
import { useEntregasRepartidor } from '@/repartidor/hooks/useEntregasRepartidor'
import { useColaEnVivo } from '@/repartidor/hooks/useColaEnVivo'
import { useUbicacion } from '@/repartidor/hooks/useUbicacion'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { colorEstado, LABEL_ESTADO } from '@/repartidor/lib/estados'
import { folioEntrega } from '@/repartidor/lib/folio'
import { estadoRepartidor, esPendienteDeRepartidor, formatoDistancia, ordenarCola } from '@/repartidor/lib/cola'
import type { EntregaRepartidor, EstadoEntrega } from '@/repartidor/types'

// Leaflet solo se descarga si el repartidor abre el mapa.
const MapaEntregas = lazy(() => import('@/repartidor/components/MapaEntregas'))

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

export default function ColaPage() {
  const navigate = useNavigate()
  const { cuenta } = useProveedorAuth()
  const { entregas, loading, error, offline, lastUpdated, recargar } = useEntregasRepartidor()
  const { posicion, estado: estadoUbicacion } = useUbicacion()
  const [filtro, setFiltro] = useState<EstadoEntrega | 'todas'>('todas')
  const [vista, setVista] = useState<'lista' | 'mapa'>('lista')

  const aplicarFiltro = useCallback((f: EstadoEntrega | 'todas') => {
    setFiltro(f)
    void recargar(f === 'todas' ? undefined : { estado: f })
  }, [recargar])

  // Cola en vivo: una asignación nueva (o una reasignación que me quita una) refresca la lista con el filtro actual.
  useColaEnVivo(cuenta?.id, useCallback(() => { void recargar(filtro === 'todas' ? undefined : { estado: filtro }) }, [recargar, filtro]))

  // Pendientes ordenadas por cercanía a la ubicación actual (o por hora de asignación sin ubicación). Se recalcula
  // cuando cambian las entregas o cuando la posición de referencia se movió más de 200 m (useUbicacion).
  const cola = useMemo(() => ordenarCola(entregas, posicion), [entregas, posicion])
  const mas = useMemo(() => entregas.filter((e) => !esPendienteDeRepartidor(e)), [entregas])
  const siguiente = cola.entregas[0] ?? null
  const libre = estadoRepartidor(entregas) === 'libre'

  const abrir = (id: number) => navigate(`/repartidor/entrega/${id}`)

  const tarjeta = (e: EntregaRepartidor, orden?: number) => {
    const d = cola.distancias.get(e.entrega_id)
    return (
      <button
        key={e.entrega_id}
        type="button"
        onClick={() => abrir(e.entrega_id)}
        className="w-full text-left rounded-2xl bg-white border border-gray-100 shadow-sm p-4 flex items-center gap-3 active:scale-[0.99] transition-transform"
      >
        {orden != null && (
          <span className="h-7 w-7 shrink-0 rounded-full bg-[#1E5C8E]/10 text-[#1E5C8E] text-sm font-semibold grid place-items-center">{orden}</span>
        )}
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
            {d != null && <span className="ml-1 shrink-0 text-gray-400">· {formatoDistancia(d)}</span>}
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
  }

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
        {!loading && !error && filtro === 'todas' && (
          <span className={`ml-auto text-xs font-semibold px-2.5 py-1 rounded-full border ${
            libre ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-blue-50 text-blue-700 border-blue-200'
          }`}>
            {libre ? 'Libre' : 'En ruta'}
          </span>
        )}
      </div>

      {/* Barra de stats */}
      <div className="rounded-2xl bg-[#1E5C8E] text-white px-4 py-3 flex items-center gap-4">
        <div>
          <p className="text-2xl font-bold leading-none">{entregas.length}</p>
          <p className="text-xs opacity-80 mt-1">entregas</p>
        </div>
        <div className="h-8 w-px bg-white/20" />
        <div>
          <p className="text-2xl font-bold leading-none">{cola.entregas.length}</p>
          <p className="text-xs opacity-80 mt-1">pendientes</p>
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

      {/* Siguiente entrega: la más cercana (o la más vieja sin ubicación) */}
      {!error && filtro === 'todas' && siguiente && (
        <button
          type="button"
          onClick={() => abrir(siguiente.entrega_id)}
          className="w-full text-left rounded-2xl border-2 border-emerald-500 bg-emerald-50 p-4 space-y-1.5"
        >
          <p className="text-xs font-semibold tracking-wider text-emerald-700 flex items-center gap-1">
            <Navigation className="h-3.5 w-3.5" /> SIGUIENTE ENTREGA
          </p>
          <div className="flex items-center gap-2">
            <span className="font-semibold text-gray-800">{folioEntrega(siguiente.entrega_id)}</span>
            <span className={`text-xs font-semibold px-2 py-0.5 rounded-full border ${colorEstado(siguiente.estado)}`}>{LABEL_ESTADO[siguiente.estado]}</span>
            {cola.distancias.get(siguiente.entrega_id) != null && (
              <span className="ml-auto text-sm font-medium text-emerald-700">{formatoDistancia(cola.distancias.get(siguiente.entrega_id) as number)}</span>
            )}
          </div>
          <p className="text-sm text-gray-700 truncate">{siguiente.direccion_entrega ?? 'Sin dirección'}</p>
        </button>
      )}

      {/* Sin ubicación: el orden es por hora de asignación */}
      {!error && filtro === 'todas' && cola.entregas.length > 1 && cola.criterio === 'asignacion' && (
        <div className="rounded-xl bg-amber-50 border border-amber-200 text-amber-800 text-sm px-3 py-2 flex items-start gap-2">
          <MapPin className="h-4 w-4 shrink-0 mt-0.5" />
          <span>
            {estadoUbicacion === 'buscando'
              ? 'Buscando tu ubicación… Mientras tanto, la cola va por hora de asignación.'
              : 'Sin tu ubicación la cola va por hora de asignación. Activá la ubicación para ordenarla por cercanía.'}
          </span>
        </div>
      )}

      {/* Chips de filtro + Lista / Mapa */}
      <div className="flex items-center gap-2">
        <div className="flex gap-2 overflow-x-auto -mx-1 px-1 pb-1 flex-1">
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
        <div className="flex rounded-full border border-gray-200 bg-white p-0.5 shrink-0">
          <button type="button" aria-label="Ver lista" onClick={() => setVista('lista')}
            className={`rounded-full p-1.5 ${vista === 'lista' ? 'bg-[#1E5C8E] text-white' : 'text-gray-500'}`}>
            <List className="h-4 w-4" />
          </button>
          <button type="button" aria-label="Ver mapa" onClick={() => setVista('mapa')}
            className={`rounded-full p-1.5 ${vista === 'mapa' ? 'bg-[#1E5C8E] text-white' : 'text-gray-500'}`}>
            <MapIcon className="h-4 w-4" />
          </button>
        </div>
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

      {/* Libre: sin pendientes (con o sin historial del día) */}
      {!loading && !error && filtro === 'todas' && libre && (
        <div className="rounded-2xl bg-white border border-gray-100 p-8 text-center">
          <div className="h-16 w-16 mx-auto mb-3 rounded-full bg-emerald-50 grid place-items-center">
            {entregas.length === 0 ? <PackageOpen className="h-8 w-8 text-emerald-300" /> : <Coffee className="h-8 w-8 text-emerald-400" />}
          </div>
          <p className="font-semibold text-gray-700">Estás libre</p>
          <p className="text-sm text-gray-500 mt-1">No tenés entregas pendientes. Cuando te asignen, te avisamos y aparecen acá.</p>
          <button type="button" onClick={() => aplicarFiltro(filtro)} className="mt-4 inline-flex items-center gap-1 text-[#1E5C8E] font-medium">
            <RefreshCw className="h-4 w-4" /> Actualizar
          </button>
        </div>
      )}

      {/* Vacío con filtro */}
      {!loading && !error && filtro !== 'todas' && entregas.length === 0 && (
        <p className="text-sm text-gray-500 text-center py-8">No hay entregas en este estado.</p>
      )}

      {/* Mapa: pendientes ordenadas, numeradas por orden de la cola */}
      {!error && vista === 'mapa' && cola.entregas.length > 0 && (
        <Suspense fallback={<div className="flex justify-center py-10 text-gray-400"><Loader2 className="h-6 w-6 animate-spin" /></div>}>
          <MapaEntregas entregas={cola.entregas} distancias={cola.distancias} posicion={posicion} onAbrir={abrir} />
        </Suspense>
      )}

      {/* Lista: pendientes en orden de la cola + el resto */}
      {!loading && !error && vista === 'lista' && entregas.length > 0 && (
        <div className="space-y-5">
          {cola.entregas.length > 0 && (
            <section className="space-y-3">
              <h2 className="text-xs font-semibold tracking-wider text-gray-400">
                {cola.criterio === 'cercania' ? 'PENDIENTES · POR CERCANÍA' : 'PENDIENTES · POR HORA DE ASIGNACIÓN'}
              </h2>
              {cola.entregas.map((e, i) => tarjeta(e, i + 1))}
            </section>
          )}
          {mas.length > 0 && (
            <section className="space-y-3">
              <h2 className="text-xs font-semibold tracking-wider text-gray-400">{filtro === 'todas' ? 'MÁS' : LABEL_ESTADO[filtro].toUpperCase()}</h2>
              {mas.map((e) => tarjeta(e))}
            </section>
          )}
        </div>
      )}
    </div>
  )
}
