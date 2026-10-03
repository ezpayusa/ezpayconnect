// Reglas puras de la cola del repartidor (lote demo 1): orden por cercanía, estado libre / en ruta y cuándo recalcular.
// Sin red ni geolocalización acá: el hook pasa la posición y las entregas; esto solo decide.
import type { EntregaRepartidor } from '@/repartidor/types'

export interface Coordenada {
  lat: number
  lng: number
}

/** Distancia en metros entre dos puntos (haversine, radio terrestre medio). */
export function haversineMetros(a: Coordenada, b: Coordenada): number {
  const R = 6371000
  const rad = (g: number) => (g * Math.PI) / 180
  const dLat = rad(b.lat - a.lat)
  const dLng = rad(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)))
}

/** Una entrega está en la cola del repartidor mientras está asignada o en camino. */
export function esPendienteDeRepartidor(e: Pick<EntregaRepartidor, 'estado'>): boolean {
  return e.estado === 'asignada' || e.estado === 'en_camino'
}

/** 'libre' con la cola vacía; 'en_ruta' si tiene alguna asignada o en camino (mismo criterio que el tablero). */
export function estadoRepartidor(entregas: Pick<EntregaRepartidor, 'estado'>[]): 'libre' | 'en_ruta' {
  return entregas.some(esPendienteDeRepartidor) ? 'en_ruta' : 'libre'
}

type EntregaOrdenable = Pick<EntregaRepartidor, 'entrega_id' | 'estado' | 'lat' | 'lng' | 'asignado_at'>

export interface ColaOrdenada<T extends EntregaOrdenable> {
  /** Las pendientes (asignada / en camino), en el orden en que conviene hacerlas. */
  entregas: T[]
  /** Distancia en metros desde la posición actual (solo con ubicación y coordenadas). */
  distancias: Map<number, number>
  /** 'cercania' con ubicación; 'asignacion' sin ubicación (orden por hora de asignación). */
  criterio: 'cercania' | 'asignacion'
}

function porAsignacion(a: EntregaOrdenable, b: EntregaOrdenable): number {
  // la más vieja primero; sin hora de asignación al final; desempate por id
  const ta = a.asignado_at ? Date.parse(a.asignado_at) : Number.POSITIVE_INFINITY
  const tb = b.asignado_at ? Date.parse(b.asignado_at) : Number.POSITIVE_INFINITY
  if (ta !== tb) return ta < tb ? -1 : 1
  return a.entrega_id - b.entrega_id
}

/**
 * Ordena las pendientes del repartidor. Con ubicación: por cercanía a la posición actual; las que no tienen
 * coordenadas van al final, por hora de asignación. Sin ubicación: todas por hora de asignación.
 */
export function ordenarCola<T extends EntregaOrdenable>(entregas: T[], posicion: Coordenada | null): ColaOrdenada<T> {
  const pendientes = entregas.filter(esPendienteDeRepartidor)
  const distancias = new Map<number, number>()
  if (!posicion) return { entregas: [...pendientes].sort(porAsignacion), distancias, criterio: 'asignacion' }
  for (const e of pendientes) {
    if (e.lat != null && e.lng != null) distancias.set(e.entrega_id, haversineMetros(posicion, { lat: e.lat, lng: e.lng }))
  }
  const ordenadas = [...pendientes].sort((a, b) => {
    const da = distancias.get(a.entrega_id)
    const db = distancias.get(b.entrega_id)
    if (da != null && db != null) return da !== db ? da - db : porAsignacion(a, b)
    if (da != null) return -1
    if (db != null) return 1
    return porAsignacion(a, b)
  })
  return { entregas: ordenadas, distancias, criterio: 'cercania' }
}

/** Umbral de movimiento para recalcular el orden (evita reordenar la lista con cada lectura del GPS). */
export const UMBRAL_RECALCULO_M = 200

/** ¿Hay que tomar la nueva posición como referencia? Sí la primera vez, o si se movió más que el umbral. */
export function debeRecalcular(referencia: Coordenada | null, nueva: Coordenada, umbral = UMBRAL_RECALCULO_M): boolean {
  return referencia == null || haversineMetros(referencia, nueva) > umbral
}

/** Distancia legible: "350 m" o "2,4 km". */
export function formatoDistancia(metros: number): string {
  if (metros < 1000) return `${Math.round(metros / 10) * 10} m`
  return `${(metros / 1000).toFixed(1).replace('.', ',')} km`
}

/** Texto del aviso de entregas nuevas (el mismo de la notificación del servidor). */
export function textoEntregasNuevas(n: number): string {
  return n === 1 ? 'Tenés 1 entrega nueva' : `Tenés ${n} entregas nuevas`
}
