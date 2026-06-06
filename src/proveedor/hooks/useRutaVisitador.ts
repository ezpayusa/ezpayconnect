import { useMemo } from 'react'
import type { VisitaAgendada } from '@/proveedor/types/proveedor.types'

export interface RutaParada {
  visita: VisitaAgendada
  lat: number
  lng: number
  direccion: string
  bufferMinutos: number // Tiempo estimado de viaje desde parada anterior
}

export interface UbicacionVisita {
  direccion?: string | null
  lat?: number | null
  lng?: number | null
}

export function useRutaVisitador(visitas: VisitaAgendada[], fecha?: string) {
  const ruta = useMemo<RutaParada[]>(() => {
    const fechaFiltro = fecha || new Date().toISOString().split('T')[0]
    
    const visitasDelDia = visitas
      .filter((v) => v.fecha_visita === fechaFiltro)
      .filter((v) => v.estado === 'confirmada' || v.estado === 'aprobada')
      .sort((a, b) => a.hora_inicio.localeCompare(b.hora_inicio))
      .filter((v) => {
        // Prioridad: ubicacion del proveedor > perfil del medico
        const lat = v.ubicacion?.lat ?? v.medico?.lat
        const lng = v.ubicacion?.lng ?? v.medico?.lng
        return !!lat && !!lng
      })

    const paradas: RutaParada[] = []
    
    visitasDelDia.forEach((visita, index) => {
      const lat = (visita.ubicacion?.lat ?? visita.medico?.lat)!
      const lng = (visita.ubicacion?.lng ?? visita.medico?.lng)!
      const direccion = visita.ubicacion?.direccion || visita.medico?.direccion_consultorio || 'Sin dirección'
      
      let bufferMinutos = 0
      if (index > 0 && paradas[index - 1]) {
        const prev = paradas[index - 1]
        const distKm = calcularDistancia(prev.lat, prev.lng, lat, lng)
        // Buffer estimado: 2 min por km + 5 min fijos por parada anterior
        bufferMinutos = Math.round(distKm * 2) + 5
      }

      paradas.push({ visita, lat, lng, direccion, bufferMinutos })
    })

    return paradas
  }, [visitas, fecha])

  const tiempoTotal = useMemo(() => {
    if (ruta.length === 0) return 0
    const totalMinutos = ruta.reduce((acc, parada) => {
      const duracionVisita = 30 // Estimado base
      return acc + parada.bufferMinutos + duracionVisita
    }, 0)
    return totalMinutos
  }, [ruta])

  const distanciaTotalKm = useMemo(() => {
    let total = 0
    for (let i = 1; i < ruta.length; i++) {
      total += calcularDistancia(ruta[i - 1].lat, ruta[i - 1].lng, ruta[i].lat, ruta[i].lng)
    }
    return Math.round(total * 10) / 10
  }, [ruta])

  return { ruta, tiempoTotal, distanciaTotalKm }
}

// Fórmula de Haversine para distancia entre dos puntos
function calcularDistancia(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371 // Radio de la Tierra en km
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

function toRad(val: number) {
  return val * Math.PI / 180
}
