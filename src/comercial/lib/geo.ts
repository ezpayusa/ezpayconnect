// Geolocalización del navegador para el módulo comercial.
//
// DECISIÓN (1): SI EL USUARIO NIEGA EL PERMISO, IGUAL PUEDE TRABAJAR.
// Un asesor bloqueado por un permiso de navegador es un módulo muerto. La jornada se abre y el
// check-in se registra sin coordenada — y el check-in queda `verificado = false` con el motivo
// "el dispositivo no reportó coordenada", que es exactamente lo que hace la RPC de la mig 273
// cuando le llegan lat/lng nulos. No hace falta ninguna rama especial en el backend: el camino
// sin coordenada YA ES un camino previsto y fail-closed.
//
// Lo que sí hace falta es que la UI lo diga ANTES y DESPUÉS, y eso es responsabilidad de las
// pantallas: acá sólo se reporta el estado con precisión.

export type EstadoGeo =
  | { estado: 'inicial' }
  | { estado: 'pidiendo' }
  | { estado: 'ok'; lat: number; lng: number; precision_m: number }
  | { estado: 'denegado' }        // el usuario dijo que no
  | { estado: 'no_disponible' }   // el navegador no tiene la API (o contexto inseguro)
  | { estado: 'error'; mensaje: string }  // timeout, GPS apagado, etc.

export const GEO_TIMEOUT_MS = 12000

/**
 * Pide una lectura. NUNCA rechaza: todos los caminos devuelven un EstadoGeo, porque quien la
 * consume tiene que poder seguir trabajando en cualquiera de ellos.
 */
export function pedirUbicacion(): Promise<EstadoGeo> {
  return new Promise((resolve) => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      resolve({ estado: 'no_disponible' })
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        resolve({
          estado: 'ok',
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          // accuracy viene en metros y es EL dato que decide si el check-in va a verificar.
          precision_m: Math.round(pos.coords.accuracy),
        }),
      (err) => {
        if (err.code === err.PERMISSION_DENIED) resolve({ estado: 'denegado' })
        else if (err.code === err.POSITION_UNAVAILABLE) resolve({ estado: 'error', mensaje: 'No se pudo obtener la ubicación (GPS sin señal).' })
        else resolve({ estado: 'error', mensaje: 'La ubicación tardó demasiado. Probá de nuevo al aire libre.' })
      },
      { enableHighAccuracy: true, timeout: GEO_TIMEOUT_MS, maximumAge: 0 },
    )
  })
}

/** Las coordenadas para mandar a la RPC. Sin lectura válida van en null, que es un caso previsto. */
export function coordsDe(g: EstadoGeo): { lat: number | null; lng: number | null; precision_m: number | null } {
  return g.estado === 'ok'
    ? { lat: g.lat, lng: g.lng, precision_m: g.precision_m }
    : { lat: null, lng: null, precision_m: null }
}

/**
 * DECISIÓN (2): el asesor tiene que enterarse ANTES de hacer check-in de que su GPS lo va a dejar
 * sin verificar. `precisionMax` viene de config_visitas_efectiva() — la misma fuente que usa la
 * RPC — para no tener dos versiones del umbral.
 */
export function avisoPrevio(g: EstadoGeo, precisionMax: number | null): string | null {
  if (g.estado === 'denegado')
    return 'Sin permiso de ubicación: vas a poder registrar, pero la visita va a quedar SIN VERIFICAR.'
  if (g.estado === 'no_disponible')
    return 'Este navegador no da ubicación: vas a poder registrar, pero la visita va a quedar SIN VERIFICAR.'
  if (g.estado === 'error')
    return `${g.mensaje} Si seguís sin señal, la visita va a quedar SIN VERIFICAR.`
  if (g.estado === 'ok' && precisionMax != null && g.precision_m > precisionMax)
    return `Tu GPS está reportando ±${g.precision_m} m y el máximo para verificar es ${precisionMax} m. `
      + 'Si hacés check-in así, la visita va a quedar SIN VERIFICAR. Probá al aire libre.'
  return null
}
