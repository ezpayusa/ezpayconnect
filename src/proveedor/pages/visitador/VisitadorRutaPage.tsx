import { useState } from 'react'
import { useVisitasAgendadas } from '@/proveedor/hooks/useVisitasAgendadas'
import { useRutaVisitador } from '@/proveedor/hooks/useRutaVisitador'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { 
  MapPin, Clock, Navigation, Calendar, Route, 
  ChevronRight, Car, Footprints, Smartphone, Compass
} from 'lucide-react'
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import iconUrl from 'leaflet/dist/images/marker-icon.png'
import iconShadowUrl from 'leaflet/dist/images/marker-shadow.png'

// Fix leaflet default icon path issue in Vite
const DefaultIcon = L.icon({
  iconUrl,
  shadowUrl: iconShadowUrl,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
})
L.Marker.prototype.options.icon = DefaultIcon

export default function VisitadorRutaPage() {
  const { visitas } = useVisitasAgendadas()
  const [fechaSeleccionada, setFechaSeleccionada] = useState(new Date().toISOString().split('T')[0])
  const { ruta, tiempoTotal, distanciaTotalKm } = useRutaVisitador(visitas, fechaSeleccionada)

  // Determinar siguiente visita pendiente (sin check-in)
  const siguienteParada = ruta.find((p) => !p.visita.checkin_fecha)

  const formatDuracion = (minutos: number) => {
    const h = Math.floor(minutos / 60)
    const m = minutos % 60
    if (h > 0) return `${h}h ${m}m`
    return `${m}m`
  }

  const abrirGoogleMaps = (desde: { lat: number; lng: number } | null, hasta: { lat: number; lng: number }) => {
    const origen = desde ? `${desde.lat},${desde.lng}` : ''
    const destino = `${hasta.lat},${hasta.lng}`
    const url = origen 
      ? `https://www.google.com/maps/dir/?api=1&origin=${origen}&destination=${destino}&travelmode=driving`
      : `https://www.google.com/maps/search/?api=1&query=${destino}`
    window.open(url, '_blank')
  }

  return (
    <div className="p-4 max-w-4xl mx-auto space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Route className="w-6 h-6" />
            Mi Ruta del Día
          </h1>
          <p className="text-muted-foreground">Planifica tu recorrido optimizado con buffer entre visitas.</p>
        </div>
        <div className="flex items-center gap-2">
          <input
            type="date"
            className="border rounded px-3 py-2 text-sm"
            value={fechaSeleccionada}
            onChange={(e) => setFechaSeleccionada(e.target.value)}
          />
        </div>
      </div>

      {/* Siguiente visita destacada */}
      {siguienteParada && (
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <Badge variant="secondary" className="text-xs">Siguiente visita</Badge>
                  <span className="text-sm text-muted-foreground">
                    {siguienteParada.visita.hora_inicio?.slice(0,5)} – {siguienteParada.visita.hora_fin?.slice(0,5)}
                  </span>
                </div>
                <h2 className="text-lg font-semibold">{siguienteParada.visita.medico?.nombre_completo}</h2>
                <p className="text-sm text-muted-foreground flex items-center gap-1">
                  <MapPin className="w-3 h-3" />
                  {siguienteParada.direccion}
                </p>
              </div>
              <div className="flex flex-col items-center gap-2">
                <div className="flex gap-2">
                  {/* Google Maps */}
                  <button
                    onClick={() => {
                      const destino = `${siguienteParada!.lat},${siguienteParada!.lng}`
                      window.open(`https://www.google.com/maps/dir/?api=1&destination=${destino}&travelmode=driving`, '_blank')
                    }}
                    className="flex flex-col items-center gap-1 px-3 py-2 rounded-lg border border-gray-200 bg-white hover:bg-gray-50 transition-colors shadow-sm"
                  >
                    <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
                      <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" fill="#EA4335"/>
                      <circle cx="12" cy="9" r="2.5" fill="white"/>
                    </svg>
                    <span className="text-[10px] font-semibold text-gray-700 leading-tight">Google Maps</span>
                  </button>

                  {/* Waze */}
                  <button
                    onClick={() => {
                      const destino = `${siguienteParada!.lat},${siguienteParada!.lng}`
                      window.open(`https://waze.com/ul?ll=${destino}&navigate=yes`, '_blank')
                    }}
                    className="flex flex-col items-center gap-1 px-3 py-2 rounded-lg bg-[#33CCFF] hover:bg-[#2AB8E8] transition-colors shadow-sm"
                  >
                    <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" fill="white"/>
                      <circle cx="9" cy="10" r="1.5" fill="#33CCFF"/>
                      <circle cx="15" cy="10" r="1.5" fill="#33CCFF"/>
                      <path d="M9 15c1 1.5 4 1.5 5 0" stroke="#33CCFF" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
                      <path d="M7 8c0-1 1-2 2-2M17 8c0-1-1-2-2-2" stroke="#33CCFF" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
                    </svg>
                    <span className="text-[10px] font-semibold text-white leading-tight">Waze</span>
                  </button>
                </div>
                <span className="text-[10px] font-bold text-muted-foreground uppercase tracking-wider">Navega</span>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Resumen */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
              <MapPin className="w-5 h-5 text-blue-600" />
            </div>
            <div>
              <p className="text-2xl font-bold">{ruta.length}</p>
              <p className="text-sm text-muted-foreground">Paradas</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="h-10 w-10 rounded-full bg-green-100 flex items-center justify-center">
              <Car className="w-5 h-5 text-green-600" />
            </div>
            <div>
              <p className="text-2xl font-bold">{distanciaTotalKm} km</p>
              <p className="text-sm text-muted-foreground">Distancia total</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="h-10 w-10 rounded-full bg-amber-100 flex items-center justify-center">
              <Clock className="w-5 h-5 text-amber-600" />
            </div>
            <div>
              <p className="text-2xl font-bold">{formatDuracion(tiempoTotal)}</p>
              <p className="text-sm text-muted-foreground">Tiempo estimado</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Ruta secuencial */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <Navigation className="w-5 h-5" />
            Secuencia de Visitas
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-0">
          {ruta.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              <Calendar className="mx-auto h-10 w-10 mb-3" />
              <p>No hay visitas confirmadas para esta fecha.</p>
              <p className="text-sm mt-1">Las visitas deben estar en estado "confirmada" para aparecer en la ruta.</p>
            </div>
          ) : (
            ruta.map((parada, index) => {
              const isLast = index === ruta.length - 1
              const visita = parada.visita

              return (
                <div key={visita.id} className="relative">
                  {/* Línea de conexión */}
                  {!isLast && (
                    <div className="absolute left-5 top-12 bottom-0 w-0.5 bg-border" />
                  )}

                  <div className="flex gap-4 pb-6">
                    {/* Punto numerado */}
                    <div className="flex-shrink-0 w-10 h-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center font-bold text-sm">
                      {index + 1}
                    </div>

                    {/* Contenido */}
                    <div className="flex-1 space-y-2">
                      <div className="flex items-start justify-between">
                        <div>
                          <h3 className="font-semibold">{visita.medico?.nombre_completo}</h3>
                          <p className="text-sm text-muted-foreground">
                            <Clock className="w-3 h-3 inline mr-1" />
                            {visita.hora_inicio?.slice(0,5)} - {visita.hora_fin?.slice(0,5)}
                          </p>
                        </div>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => abrirGoogleMaps(index > 0 ? { lat: ruta[index-1].lat, lng: ruta[index-1].lng } : null, { lat: parada.lat, lng: parada.lng })}
                        >
                          <Navigation className="w-3 h-3 mr-1" />
                          Navegar
                        </Button>
                      </div>

                      <div className="text-sm bg-muted/50 rounded p-2 space-y-1">
                        <p className="flex items-center gap-2">
                          <MapPin className="w-4 h-4 text-muted-foreground" />
                          {parada.direccion}
                        </p>
                        {parada.bufferMinutos > 0 && (
                          <p className="flex items-center gap-2 text-amber-600">
                            <Car className="w-4 h-4" />
                            Buffer de viaje: ~{parada.bufferMinutos} min desde parada anterior
                          </p>
                        )}
                      </div>

                      {visita.notas_empresa && (
                        <p className="text-sm text-muted-foreground italic">
                          Notas: {visita.notas_empresa}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )
            })
          )}
        </CardContent>
      </Card>

      {/* Mapa de ruta con Leaflet + OpenStreetMap */}
      {ruta.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Mapa de Ruta</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="aspect-video bg-muted rounded-lg overflow-hidden">
              <MapContainer
                center={[ruta[0].lat, ruta[0].lng]}
                zoom={13}
                scrollWheelZoom={true}
                style={{ height: '100%', width: '100%' }}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                {ruta.map((parada, idx) => (
                  <Marker key={parada.visita.id} position={[parada.lat, parada.lng]}>
                    <Popup>
                      <div className="space-y-1">
                        <p className="font-semibold">{idx + 1}. {parada.visita.medico?.nombre_completo}</p>
                        <p className="text-sm">{parada.direccion}</p>
                        <p className="text-sm text-muted-foreground">
                          {parada.visita.hora_inicio?.slice(0,5)} – {parada.visita.hora_fin?.slice(0,5)}
                        </p>
                      </div>
                    </Popup>
                  </Marker>
                ))}
                <Polyline
                  positions={ruta.map(p => [p.lat, p.lng])}
                  color="#1E5C8E"
                  weight={4}
                  opacity={0.8}
                />
              </MapContainer>
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              * Mapa gratuito vía OpenStreetMap. Haz clic en los marcadores para ver detalles de cada parada.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
