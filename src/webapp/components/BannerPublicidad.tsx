import { useEffect, useState } from 'react'
import { useWebAppCampanas } from '@/webapp/hooks/useWebAppCampanas'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ExternalLink, ChevronLeft, ChevronRight, Megaphone } from 'lucide-react'

export default function BannerPublicidad() {
  const { perfil } = useWebAppAuth()
  const { campanas, loading, registrarVista } = useWebAppCampanas(perfil?.id, perfil)
  const [indice, setIndice] = useState(0)

  useEffect(() => {
    if (campanas.length > 0 && indice >= campanas.length) {
      setIndice(0)
    }
  }, [campanas, indice])

  useEffect(() => {
    if (campanas[indice]) {
      registrarVista(campanas[indice].id, false)
    }
  }, [indice, campanas])

  if (loading || campanas.length === 0) return null

  const campana = campanas[indice]
  const tipoColor: Record<string, string> = {
    farmacia: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    equipo_medico: 'bg-blue-50 text-blue-700 border-blue-200',
    laboratorio: 'bg-amber-50 text-amber-700 border-amber-200',
    general: 'bg-slate-50 text-slate-700 border-slate-200',
  }
  const tipoLabel: Record<string, string> = {
    farmacia: 'Farmacia',
    equipo_medico: 'Equipo Médico',
    laboratorio: 'Laboratorio',
    general: 'Promoción',
  }

  return (
    <div className="relative rounded-xl overflow-hidden border border-slate-200 bg-white shadow-sm">
      {campana.imagen_url && (
        <div className="h-40 w-full bg-slate-100">
          <img
            key={campana.id + '-img'}
            src={campana.imagen_url}
            alt={campana.titulo}
            className="w-full h-full object-cover"
            onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          />
        </div>
      )}
      <div className="p-4">
        <div className="flex items-center gap-2 mb-2">
          <Megaphone className="w-4 h-4 text-sky-500" />
          <Badge variant="outline" className={tipoColor[campana.tipo] || tipoColor.general}>
            {tipoLabel[campana.tipo] || 'Promoción'}
          </Badge>
          <span className="text-xs text-slate-400 ml-auto">
            {indice + 1} / {campanas.length}
          </span>
        </div>
        <h3 className="font-semibold text-slate-800">{campana.titulo}</h3>
        {campana.descripcion && (
          <p className="text-sm text-slate-500 mt-1 line-clamp-2">{campana.descripcion}</p>
        )}
        {campana.link_url && (
          <Button
            size="sm"
            variant="outline"
            className="mt-3 w-full"
            onClick={() => {
              registrarVista(campana.id, true)
              const url = campana.link_url?.startsWith('http') ? campana.link_url : `https://${campana.link_url}`
              window.open(url, '_blank')
            }}
          >
            <ExternalLink className="w-3 h-3 mr-1" />
            Ver oferta
          </Button>
        )}
      </div>

      {campanas.length > 1 && (
        <div className="flex items-center justify-between px-4 pb-4">
          <Button
            size="icon"
            variant="ghost"
            className="h-8 w-8"
            onClick={() => setIndice((prev) => (prev - 1 + campanas.length) % campanas.length)}
          >
            <ChevronLeft className="w-4 h-4" />
          </Button>
          <div className="flex gap-1">
            {campanas.map((_, i) => (
              <button
                key={i}
                className={`w-2 h-2 rounded-full transition-colors ${i === indice ? 'bg-sky-500' : 'bg-slate-200'}`}
                onClick={() => setIndice(i)}
              />
            ))}
          </div>
          <Button
            size="icon"
            variant="ghost"
            className="h-8 w-8"
            onClick={() => setIndice((prev) => (prev + 1) % campanas.length)}
          >
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      )}
    </div>
  )
}
