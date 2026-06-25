import { useState, useEffect } from 'react'
import { Package, Truck, Lock, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

type Modalidad = 'pickup' | 'delivery'

interface ModalidadGrupoProps {
  recetaId: number
  farmaciaId: number
  farmaciaNombre: string
  modalidad: Modalidad
  /** Algún ítem del grupo ya dispensado → freeze: el server hace RAISE; la UI lo refleja deshabilitando. */
  despachado: boolean
  onChanged: () => void
}

// Control de modalidad pickup/delivery por grupo (receta, farmacia) — superficie PACIENTE (estética slate).
// Cambia vía el único RPC fijar_modalidad_grupo (última-escritura-gana; gate paciente_es_mio server-side).
export default function ModalidadGrupo({ recetaId, farmaciaId, farmaciaNombre, modalidad, despachado, onChanged }: ModalidadGrupoProps) {
  const [actual, setActual] = useState<Modalidad>(modalidad)
  const [saving, setSaving] = useState(false)

  // La VERDAD es del server: cuando el padre re-fetchea (onChanged) y llega un nuevo `modalidad`, sincronizamos
  // el estado local. Así el optimismo nunca queda pegado por encima del valor real.
  useEffect(() => { setActual(modalidad) }, [modalidad])

  const cambiar = async (nueva: Modalidad) => {
    if (nueva === actual || saving || despachado) return
    const previo = actual
    setActual(nueva) // optimista (toggle de modalidad, no es dinero)
    setSaving(true)
    try {
      const { error } = await supabase.rpc('fijar_modalidad_grupo', {
        p_receta_id: recetaId,
        p_farmacia_id: farmaciaId,
        p_modalidad: nueva,
      })
      if (error) throw error
      toast.success(nueva === 'delivery' ? 'Cambiado a entrega a domicilio' : 'Cambiado a retiro en farmacia')
    } catch (e: any) {
      setActual(previo) // revertir el optimismo de inmediato
      toast.error(e?.message || 'No se pudo cambiar la modalidad')
    } finally {
      setSaving(false)
      // Refetch en AMBOS caminos → trae la verdad del server (no el optimista). Si el RAISE fue por freeze
      // (el grupo se despachó entre el render y el tap), el refetch trae dispensado=true → el control queda
      // DISABLED (no en limbo). Si el server confirmó el cambio, el refetch lo ratifica.
      onChanged()
    }
  }

  return (
    <div className="rounded-lg bg-white border border-slate-200 p-3 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-medium text-slate-700 truncate">{farmaciaNombre}</p>
        {saving && <Loader2 className="h-4 w-4 animate-spin text-slate-400 shrink-0" />}
      </div>

      <div className="inline-flex w-full rounded-lg bg-slate-100 p-1">
        {(['pickup', 'delivery'] as Modalidad[]).map((opt) => {
          const activo = actual === opt
          const Icono = opt === 'pickup' ? Package : Truck
          return (
            <button
              key={opt}
              type="button"
              disabled={saving || despachado}
              onClick={() => cambiar(opt)}
              className={`flex-1 flex items-center justify-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                activo ? 'bg-white text-slate-800 shadow-sm' : 'text-slate-500'
              } ${(saving || despachado) ? 'opacity-60 cursor-not-allowed' : ''}`}
            >
              <Icono className="h-4 w-4" /> {opt === 'pickup' ? 'Retiro' : 'Domicilio'}
            </button>
          )
        })}
      </div>

      {despachado && (
        <p className="text-xs text-slate-400 flex items-center gap-1">
          <Lock className="h-3 w-3" /> Ya en preparación/despacho, no se puede cambiar.
        </p>
      )}
    </div>
  )
}
