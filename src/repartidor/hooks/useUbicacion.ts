import { useEffect, useState } from 'react'
import { debeRecalcular, type Coordenada } from '@/repartidor/lib/cola'

export type EstadoUbicacion = 'buscando' | 'ok' | 'denegada' | 'no_disponible'

/**
 * Ubicación actual del repartidor (geolocalización del navegador, solo en el dispositivo: no se envía a ningún lado).
 * Devuelve una posición de REFERENCIA que solo cambia la primera vez o cuando se movió más de 200 m, para que el
 * orden de la cola no salte con cada lectura del GPS.
 */
export function useUbicacion() {
  const [posicion, setPosicion] = useState<Coordenada | null>(null)
  const [estado, setEstado] = useState<EstadoUbicacion>(
    typeof navigator !== 'undefined' && 'geolocation' in navigator ? 'buscando' : 'no_disponible',
  )

  useEffect(() => {
    if (typeof navigator === 'undefined' || !('geolocation' in navigator)) return
    const id = navigator.geolocation.watchPosition(
      (p) => {
        const nueva = { lat: p.coords.latitude, lng: p.coords.longitude }
        setEstado('ok')
        setPosicion((ref) => (debeRecalcular(ref, nueva) ? nueva : ref))
      },
      (err) => setEstado(err.code === err.PERMISSION_DENIED ? 'denegada' : 'no_disponible'),
      { enableHighAccuracy: true, maximumAge: 30_000, timeout: 20_000 },
    )
    return () => navigator.geolocation.clearWatch(id)
  }, [])

  return { posicion, estado }
}
