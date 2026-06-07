import { useEffect, useState, useRef, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ExternalLink, ChevronLeft, ChevronRight, Megaphone } from 'lucide-react'
import { registrarMetricaCampana, expandirCampanasPorPeso, filtrarCampanasPorFrequencyCap } from '@/lib/metricas/campanas'

interface Campana {
  id: number
  titulo: string
  descripcion: string | null
  tipo: string
  imagen_url: string | null
  link_url: string | null
  peso?: number
}

const AUTO_SLIDE_INTERVAL = 6000

export default function BannerPublicidadGlobal() {
  const [campanasRaw, setCampanasRaw] = useState<Campana[]>([])
  const [loading, setLoading] = useState(true)
  const [indice, setIndice] = useState(0)
  const [pausado, setPausado] = useState(false)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const yaRegistradas = useRef<Set<number>>(new Set())
  const { paisId } = usePaisFiltro()

  useEffect(() => {
    const fetchCampanas = async () => {
      let query = supabase
        .from('campanas_publicitarias')
        .select('id, titulo, descripcion, tipo, imagen_url, link_url, peso')
        .eq('activa', true)
        .gte('fecha_fin', new Date().toISOString().split('T')[0])
      if (paisId) query = query.eq('pais_id', paisId)
      const { data, error } = await query.order('created_at', { ascending: false })

      if (!error) {
        const filtradas = await filtrarCampanasPorFrequencyCap(data || [])
        setCampanasRaw(filtradas)
      }
      setLoading(false)
    }
    fetchCampanas()
  }, [])

  const campanas = expandirCampanasPorPeso(campanasRaw)

  const avanzar = useCallback(() => {
    setIndice((prev) => (prev + 1) % Math.max(1, campanas.length))
  }, [campanas.length])

  const retroceder = useCallback(() => {
    setIndice((prev) => (prev - 1 + Math.max(1, campanas.length)) % Math.max(1, campanas.length))
  }, [campanas.length])

  // Auto-slide
  useEffect(() => {
    if (campanas.length <= 1 || pausado) {
      if (intervalRef.current) clearInterval(intervalRef.current)
      return
    }
    intervalRef.current = setInterval(avanzar, AUTO_SLIDE_INTERVAL)
    return () => { if (intervalRef.current) clearInterval(intervalRef.current) }
  }, [campanas.length, pausado, avanzar])

  // Registrar impresión (una vez por campana real por sesión)
  const campanaActual = campanas[indice]
  useEffect(() => {
    if (campanaActual && !yaRegistradas.current.has(campanaActual.id)) {
      yaRegistradas.current.add(campanaActual.id)
      registrarMetricaCampana(campanaActual.id, {
        tipoPerfil: 'medico',
        contexto: 'dashboard',
      })
    }
  }, [campanaActual])

  if (loading || campanas.length === 0) return null

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
    <div
      className="relative rounded-xl overflow-hidden border border-slate-200 bg-white shadow-sm mb-6"
      onMouseEnter={() => setPausado(true)}
      onMouseLeave={() => setPausado(false)}
    >
      {campanaActual.imagen_url && (
        <div className="h-32 w-full bg-slate-100">
          <img
            key={campanaActual.id + '-img'}
            src={campanaActual.imagen_url}
            alt={campanaActual.titulo}
            className="w-full h-full object-cover"
            onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
          />
        </div>
      )}
      <div className="p-4">
        <div className="flex items-center gap-2 mb-2">
          <Megaphone className="w-4 h-4 text-rose-500" />
          <Badge variant="outline" className={tipoColor[campanaActual.tipo] || tipoColor.general}>
            {tipoLabel[campanaActual.tipo] || 'Promoción'}
          </Badge>
          <span className="text-xs text-slate-400 ml-auto">
            {indice + 1} / {campanas.length}
          </span>
        </div>
        <h3 className="font-semibold text-slate-800">{campanaActual.titulo}</h3>
        {campanaActual.descripcion && (
          <p className="text-sm text-slate-500 mt-1 line-clamp-2">{campanaActual.descripcion}</p>
        )}
        {campanaActual.link_url && (
          <Button
            size="sm"
            variant="outline"
            className="mt-3"
            onClick={() => {
              registrarMetricaCampana(campanaActual.id, {
                tipoPerfil: 'medico',
                contexto: 'dashboard',
                clickeado: true,
              })
              const url = campanaActual.link_url?.startsWith('http') ? campanaActual.link_url : `https://${campanaActual.link_url}`
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
          <Button size="icon" variant="ghost" className="h-8 w-8" onClick={retroceder}>
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
          <Button size="icon" variant="ghost" className="h-8 w-8" onClick={avanzar}>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      )}
    </div>
  )
}
