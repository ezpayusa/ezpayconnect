import { Loader2, ShieldCheck, Clock, UserPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { textoPrioridad, type PrioridadAgendar } from '@/visitador/lib/enrolamiento'

interface Props {
  prioridad: PrioridadAgendar | null
  /** Mostrar "Enrolar médico" con 'libre' (pieza 6: lab farmacéutico con el módulo de enrolamiento). */
  puedeEnrolar: boolean
  enrolando: boolean
  onEnrolar: () => void
}

// Lo que dice prioridad_para_agendar del médico elegido. Solo pinta lo que la RPC devuelve: nunca el otro laboratorio.
export default function IndicadorPrioridad({ prioridad, puedeEnrolar, enrolando, onEnrolar }: Props) {
  if (!prioridad) return null
  const texto = textoPrioridad(prioridad)

  if (prioridad.estado === 'propia' && texto) {
    return (
      <div data-testid="prioridad-propia" className="flex items-start gap-2 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800">
        <ShieldCheck className="h-4 w-4 mt-0.5 shrink-0" />
        <p>{texto}</p>
      </div>
    )
  }

  if (prioridad.estado === 'otro_laboratorio' && texto) {
    return (
      <div data-testid="prioridad-otro" className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
        <Clock className="h-4 w-4 mt-0.5 shrink-0" />
        <p>{texto}</p>
      </div>
    )
  }

  // 'libre': sin aviso. Solo el botón, si la empresa puede enrolar.
  if (prioridad.estado === 'libre' && puedeEnrolar) {
    return (
      <Button variant="outline" size="sm" disabled={enrolando} onClick={onEnrolar} className="border-[#1E5C8E] text-[#1E5C8E]">
        {enrolando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <UserPlus className="h-4 w-4 mr-1" />}
        Enrolar médico
      </Button>
    )
  }
  return null
}
