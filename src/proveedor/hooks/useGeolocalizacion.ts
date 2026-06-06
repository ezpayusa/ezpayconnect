import { useState, useCallback } from 'react'

interface Ubicacion {
  lat: number
  lng: number
  precision?: number
  error?: string
}

export function useGeolocalizacion() {
  const [ubicacion, setUbicacion] = useState<Ubicacion | null>(null)
  const [cargando, setCargando] = useState(false)

  const obtenerUbicacion = useCallback(async (forzar = false): Promise<Ubicacion | null> => {
    setCargando(true)
    try {
      const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(
          resolve,
          reject,
          { enableHighAccuracy: true, timeout: 10000, maximumAge: forzar ? 0 : 60000 }
        )
      })
      const u = {
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        precision: pos.coords.accuracy,
      }
      setUbicacion(u)
      return u
    } catch (err: any) {
      const errorMsg = err.code === 1 ? 'Permiso denegado' : err.code === 2 ? 'Ubicación no disponible' : 'Timeout'
      setUbicacion({ lat: 0, lng: 0, error: errorMsg })
      return null
    } finally {
      setCargando(false)
    }
  }, [])

  return { ubicacion, cargando, obtenerUbicacion }
}
