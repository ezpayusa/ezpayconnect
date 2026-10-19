import { Navigation } from 'lucide-react'
import { enlacesNavegacion } from '@/lib/navegacion'

// Botones Navegar (Google Maps) y Waze hacia el prospecto de una visita. Es el ÚNICO lugar que pinta
// estos botones; los links los arma enlacesNavegacion. Son <a>, y un <a> nunca va dentro de un
// <Link> (HTML inválido: el toque abriría los dos), así que quien lo use lo pone FUERA del Link.
//
// Solo para visitas que todavía se hacen: en una realizada, cancelada o no_realizada no hay a dónde ir.
export default function BotonesNavegar({ estado, lat, lng, direccion }: {
  estado: string | null | undefined
  lat: unknown
  lng: unknown
  direccion: string | null | undefined
}) {
  if (estado !== 'planificada' && estado !== 'en_curso') return null
  const e = enlacesNavegacion({ lat, lng, direccion })
  if (!e) return null

  return (
    <div className="pb-2">
      <div className="flex gap-2">
        <a href={e.googleMaps} target="_blank" rel="noopener noreferrer"
          className="inline-flex min-h-9 items-center gap-1.5 rounded-md border border-[#1E5C8E] px-3 py-1.5 text-sm text-[#1E5C8E] hover:bg-blue-50">
          <Navigation className="h-4 w-4" />Navegar
        </a>
        <a href={e.waze} target="_blank" rel="noopener noreferrer"
          className="inline-flex min-h-9 items-center rounded-md border px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50">
          Waze
        </a>
      </div>
      {e.porDireccion && (
        <p className="mt-1 text-xs text-amber-700">Por dirección: este prospecto no tiene ubicación cargada</p>
      )}
    </div>
  )
}
