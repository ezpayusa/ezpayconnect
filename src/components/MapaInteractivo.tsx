import { useEffect, useState } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'

// Fix leaflet default icon path issue in Vite
import iconUrl from 'leaflet/dist/images/marker-icon.png'
import iconShadowUrl from 'leaflet/dist/images/marker-shadow.png'

const defaultIcon = L.icon({
  iconUrl,
  shadowUrl: iconShadowUrl,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
})

L.Marker.prototype.options.icon = defaultIcon

interface MapaInteractivoProps {
  lat?: number | null
  lng?: number | null
  onChange: (lat: number, lng: number) => void
  height?: string
}

function ClickHandler({ onClick }: { onClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      onClick(e.latlng.lat, e.latlng.lng)
    },
  })
  return null
}

export default function MapaInteractivo({ lat, lng, onChange, height = '300px' }: MapaInteractivoProps) {
  const defaultLat = 14.6349
  const defaultLng = -90.5069
  const [position, setPosition] = useState<[number, number]>([
    lat ?? defaultLat,
    lng ?? defaultLng,
  ])

  useEffect(() => {
    if (lat != null && lng != null) {
      setPosition([lat, lng])
    }
  }, [lat, lng])

  const handleClick = (newLat: number, newLng: number) => {
    setPosition([newLat, newLng])
    onChange(newLat, newLng)
  }

  return (
    <div style={{ height, width: '100%' }} className="rounded overflow-hidden border">
      <MapContainer
        center={position}
        zoom={16}
        scrollWheelZoom={true}
        style={{ height: '100%', width: '100%' }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <Marker position={position} draggable={true} eventHandlers={{
          dragend: (e) => {
            const marker = e.target as L.Marker
            const latlng = marker.getLatLng()
            handleClick(latlng.lat, latlng.lng)
          },
        }} />
        <ClickHandler onClick={handleClick} />
      </MapContainer>
    </div>
  )
}
