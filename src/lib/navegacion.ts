// Links de navegación (Google Maps y Waze) hacia un destino.
//
// Es el ÚNICO lugar que arma estos links. VisitadorRutaPage y EntregaDetallePage todavía arman los
// suyos a mano: se migran después, no en este PR.
//
// Funciones puras: no leen la base, no tocan el DOM y no dependen de ningún módulo.

export type Destino = { lat?: unknown; lng?: unknown; direccion?: string | null }
export type Enlaces = { googleMaps: string; waze: string; porDireccion: boolean }

/**
 * Misma regla que el CHECK prospectos_coord_valida (mig 374): dos números finitos, lat en [-90, 90],
 * lng en [-180, 180], y nunca (0, 0) — el valor basura de un pin sin inicializar, que mandaría al
 * asesor al golfo de Guinea.
 */
function coordenadaValida(lat: unknown, lng: unknown): lat is number {
  if (typeof lat !== 'number' || typeof lng !== 'number') return false
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false
  return !(lat === 0 && lng === 0)
}

/**
 * Coordenada válida → links por coordenada. Si no, dirección no vacía → links por texto
 * (`porDireccion: true`: la app de mapas la geocodifica y puede equivocarse). Sin ninguna → null.
 */
export function enlacesNavegacion(d: Destino): Enlaces | null {
  if (coordenadaValida(d.lat, d.lng)) {
    const ll = `${d.lat},${d.lng as number}`
    return {
      googleMaps: `https://www.google.com/maps/dir/?api=1&destination=${ll}&travelmode=driving`,
      waze: `https://waze.com/ul?ll=${ll}&navigate=yes`,
      porDireccion: false,
    }
  }
  const dir = d.direccion?.trim() ?? ''
  if (!dir) return null
  const q = encodeURIComponent(dir)
  return {
    googleMaps: `https://www.google.com/maps/dir/?api=1&destination=${q}&travelmode=driving`,
    waze: `https://waze.com/ul?q=${q}&navigate=yes`,
    porDireccion: true,
  }
}
