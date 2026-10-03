import { useEffect } from 'react'
import { MapContainer, TileLayer, Marker, Popup, CircleMarker, Polyline, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { EntregaRepartidor } from '@/repartidor/types'
import type { Coordenada } from '@/repartidor/lib/cola'
import { encuadreMapa, formatoDistancia } from '@/repartidor/lib/cola'
import { folioEntrega } from '@/repartidor/lib/folio'

interface Props {
  /** Pendientes ya ordenadas (ordenarCola): el número del marcador es su lugar en la cola. */
  entregas: EntregaRepartidor[]
  distancias: Map<number, number>
  posicion: Coordenada | null
  onAbrir: (entregaId: number) => void
}

// Mismo mapa que la ruta del visitador (react-leaflet + OpenStreetMap), con marcadores numerados por orden de la cola.
const icono = (n: number, primero: boolean) => L.divIcon({
  className: '',
  html: `<div style="width:28px;height:28px;border-radius:9999px;display:grid;place-items:center;font:600 13px system-ui;color:#fff;`
      + `background:${primero ? '#16a34a' : '#1E5C8E'};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.35)">${n}</div>`,
  iconSize: [28, 28],
  iconAnchor: [14, 14],
})

/** Encuadra el mapa en los puntos (fitBounds) y vuelve a encuadrar cuando cambian: entregas nuevas o movimiento > 200 m. */
function Encuadrar({ puntos }: { puntos: [number, number][] }) {
  const map = useMap()
  const clave = puntos.map((p) => p.join(',')).join(';')
  useEffect(() => {
    if (puntos.length === 0) return
    if (puntos.length === 1) map.setView(puntos[0], 15)
    else map.fitBounds(L.latLngBounds(puntos), { padding: [32, 32], maxZoom: 16 })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave, map])
  return null
}

export default function MapaEntregas({ entregas, distancias, posicion, onAbrir }: Props) {
  const conCoords = entregas.filter((e) => e.lat != null && e.lng != null)
  const sinCoords = entregas.length - conCoords.length
  // Encuadre inicial: ubicación + pendientes; a más de 200 km de la más cercana, solo las pendientes (y aviso).
  const encuadre = encuadreMapa(posicion, conCoords)
  const centro: [number, number] | null = encuadre.puntos[0] ?? null

  if (!centro || conCoords.length === 0) {
    return (
      <div className="rounded-2xl bg-white border border-gray-100 p-6 text-center text-sm text-gray-500">
        Ninguna de tus entregas tiene ubicación en el mapa todavía.
      </div>
    )
  }

  // La línea sale de la ubicación solo si está cerca: a cientos de km sería una raya que cruza el mapa.
  const recorrido: [number, number][] = [
    ...(posicion && !encuadre.lejos ? [[posicion.lat, posicion.lng] as [number, number]] : []),
    ...conCoords.map((e) => [e.lat as number, e.lng as number] as [number, number]),
  ]

  return (
    <div className="space-y-2">
      {encuadre.lejos && (
        <div className="rounded-xl bg-amber-50 border border-amber-200 text-amber-800 text-sm px-3 py-2">
          Estás lejos de tu zona de entregas: el mapa muestra solo tus entregas.
        </div>
      )}
      <div className="h-[60vh] rounded-2xl overflow-hidden border border-gray-100">
        <MapContainer center={centro} zoom={13} scrollWheelZoom style={{ height: '100%', width: '100%' }}>
          <Encuadrar puntos={encuadre.puntos} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {posicion && (
            <CircleMarker center={[posicion.lat, posicion.lng]} radius={8} pathOptions={{ color: '#fff', weight: 2, fillColor: '#2563eb', fillOpacity: 1 }}>
              <Popup>Tu ubicación</Popup>
            </CircleMarker>
          )}
          {conCoords.map((e) => {
            const n = entregas.indexOf(e) + 1
            const d = distancias.get(e.entrega_id)
            return (
              <Marker key={e.entrega_id} position={[e.lat as number, e.lng as number]} icon={icono(n, n === 1)}>
                <Popup>
                  <div className="space-y-1">
                    <p className="font-semibold">{n}. {folioEntrega(e.entrega_id)}</p>
                    <p className="text-sm">{e.direccion_entrega ?? 'Sin dirección'}</p>
                    {d != null && <p className="text-xs text-gray-500">A {formatoDistancia(d)}</p>}
                    <button type="button" className="text-sm font-medium text-[#1E5C8E] underline" onClick={() => onAbrir(e.entrega_id)}>
                      Abrir entrega
                    </button>
                  </div>
                </Popup>
              </Marker>
            )
          })}
          {recorrido.length > 1 && <Polyline positions={recorrido} pathOptions={{ color: '#1E5C8E', weight: 3, opacity: 0.6, dashArray: '6 6' }} />}
        </MapContainer>
      </div>
      {sinCoords > 0 && (
        <p className="text-xs text-gray-500">
          {sinCoords === 1 ? '1 entrega no tiene ubicación' : `${sinCoords} entregas no tienen ubicación`} y no aparece en el mapa: está en la lista.
        </p>
      )}
    </div>
  )
}
