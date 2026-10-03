import { useEffect, useState } from 'react'
import { Loader2 } from 'lucide-react'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { useAsignacionEntregas, type ErrorGestion, type RepartidorAsignable } from '@/farmacia/hooks/useGestionEntregas'
import { mensajeErrorEntrega, puedeElegirRepartidorActual, textoBotonAsignacion } from '@/farmacia/lib/gestionEntregas'
import { folioEntrega } from '@/repartidor/lib/folio'
import type { EstadoEntrega } from '@/repartidor/types'

interface Props {
  /** 'asignar' = tanda de pendientes (asignar_entregas_lote); 'reasignar' = una entrega (reasignar_entrega). */
  modo: 'asignar' | 'reasignar'
  /** Entregas a asignar (todas de la misma sucursal) o la entrega a reasignar. */
  entregaIds: number[]
  /** Repartidor actual (solo reasignar): se marca en la lista. */
  repartidorActual?: string | null
  /** Estado de la entrega a reasignar: si está fallida, se puede reabrir con el mismo repartidor. */
  estadoEntrega?: EstadoEntrega | null
  /** Recibe el repartidor elegido. */
  onHecho: (repartidorId: string) => void
  onClose: () => void
}

// Selector de repartidor: lista los que el servidor aceptaría para la sucursal de las entregas
// (listar_repartidores_asignables), menos cargado primero. El servidor re-valida todo al confirmar.
export default function AsignarRepartidorDialog({ modo, entregaIds, repartidorActual, estadoEntrega = null, onHecho, onClose }: Props) {
  const { listarAsignables, asignarLote, reasignar } = useAsignacionEntregas()
  const [opciones, setOpciones] = useState<RepartidorAsignable[]>([])
  const [cargando, setCargando] = useState(true)
  const [errorLista, setErrorLista] = useState<ErrorGestion>(null)
  const [elegido, setElegido] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)
  const [errorAccion, setErrorAccion] = useState<ErrorGestion>(null)

  useEffect(() => {
    let vivo = true
    void (async () => {
      setCargando(true)
      const { data, error } = await listarAsignables(entregaIds[0])
      if (!vivo) return
      setErrorLista(error)
      setOpciones(data)
      setCargando(false)
    })()
    return () => { vivo = false }
  }, [listarAsignables, entregaIds])

  const confirmar = async () => {
    if (!elegido) return
    setGuardando(true)
    setErrorAccion(null)
    const { error } = modo === 'asignar' ? await asignarLote(entregaIds, elegido) : await reasignar(entregaIds[0], elegido)
    setGuardando(false)
    if (error) { setErrorAccion(error); return }
    onHecho(elegido)
  }

  const titulo = modo === 'asignar'
    ? (entregaIds.length === 1 ? `Asignar ${folioEntrega(entregaIds[0])}` : `Asignar ${entregaIds.length} entregas`)
    : `Reasignar ${folioEntrega(entregaIds[0])}`

  return (
    <Dialog open onOpenChange={(o) => { if (!o && !guardando) onClose() }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{titulo}</DialogTitle>
          <DialogDescription>
            {modo === 'asignar'
              ? 'Elegí el repartidor. Le llega un aviso con las entregas nuevas.'
              : estadoEntrega === 'fallida'
                ? 'Elegí el repartidor: podés reabrirla con el mismo o pasarla a otro. Le llega un aviso.'
                : 'Elegí el nuevo repartidor. Les avisamos a los dos.'}
          </DialogDescription>
        </DialogHeader>

        {cargando && <div className="flex justify-center py-6 text-[#8a9aaa]"><Loader2 className="h-5 w-5 animate-spin" /></div>}
        {!cargando && errorLista && <p className="text-sm text-red-700">{mensajeErrorEntrega(errorLista)}</p>}
        {!cargando && !errorLista && opciones.length === 0 && (
          <p className="text-sm text-[#8a9aaa]">No hay repartidores activos en la sucursal de esta entrega.</p>
        )}
        {!cargando && !errorLista && opciones.length > 0 && (
          <div className="space-y-2 max-h-72 overflow-y-auto" role="radiogroup">
            {opciones.map((r) => {
              const actual = r.repartidor_id === repartidorActual
              // fallida: el actual se puede elegir (reasignar_entrega la reabre); asignada / en camino: no
              const bloqueado = actual && !(estadoEntrega != null && puedeElegirRepartidorActual(estadoEntrega))
              return (
                <button
                  key={r.repartidor_id}
                  type="button"
                  role="radio"
                  aria-checked={elegido === r.repartidor_id}
                  disabled={bloqueado}
                  onClick={() => setElegido(r.repartidor_id)}
                  className={`w-full text-left rounded-lg border px-3 py-2 flex items-center justify-between gap-2 ${
                    elegido === r.repartidor_id ? 'border-[#1E5C8E] bg-[#1E5C8E]/5' : 'border-gray-200'
                  } ${bloqueado ? 'opacity-50 cursor-not-allowed' : ''}`}
                >
                  <span className="text-sm font-medium text-[#1a2a3a]">{r.nombre}{actual ? ' (actual)' : ''}</span>
                  <span className="text-xs text-[#8a9aaa]">
                    {r.estado_calc === 'libre' ? 'Libre' : `${r.asignadas + r.en_camino} en cola`}
                  </span>
                </button>
              )
            })}
          </div>
        )}

        {errorAccion && <p className="text-sm text-red-700">{mensajeErrorEntrega(errorAccion)}</p>}

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={guardando}>Cancelar</Button>
          <Button onClick={() => void confirmar()} disabled={!elegido || guardando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
            {guardando && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
            {textoBotonAsignacion(modo, estadoEntrega, elegido, repartidorActual ?? null)}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
