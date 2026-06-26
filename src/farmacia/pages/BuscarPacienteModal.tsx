// F4 + R1 — Búsqueda de mostrador SIN-QR, patrón de 2 PASOS (gate reveal-registrado, Puerta 3).
// PASO 1: buscar por identidad → CABECERA (paciente + "N ítems" por receta). SIN medicamento/dosis.
// PASO 2: "Ver / despachar" en una receta → revelar_items_receta('sinqr') trae el med Y registra el reveal
//         (server-side, actor=auth.uid; mig 154, bloqueante). Recién ahí se ven los ítems y se despacha.
// El despacho reusa registrar_dispensacion_dirigida (despacharDirigido), el MISMO camino que la bandeja.
//
// PRIVACIDAD:
//  · paciente_ref / receta_base_id se usan solo como React key / handoff. NUNCA renderizados como texto ni en URL/logs.
//  · El paso 1 NO trae datos clínicos (el RPC devuelve cabecera). El med aparece solo en el paso 2.
//  · `instrucciones` llega del paso 2 pero NO se renderiza.
//  · Sin campo "Dependiente" de texto libre: la identidad del reveal es auth.uid, registrada server-side.
import { useState } from 'react'
import { toast } from 'sonner'
import { X, Search, Loader2, CheckCircle, Package, AlertCircle, UserSearch, Eye } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useRecetasEntrantes, type PacienteCabecera, type ItemEntrante } from '@/farmacia/hooks/useRecetasEntrantes'

interface Props {
  open: boolean
  onClose: () => void
  onDespachado?: () => void   // refresca la bandeja del page padre tras un despacho OK
}

export default function BuscarPacienteModal({ open, onClose, onDespachado }: Props) {
  const { buscarPaciente, revelarItems, despacharDirigido } = useRecetasEntrantes()

  const [nombre, setNombre] = useState('')
  const [apellido, setApellido] = useState('')
  const [fechaNac, setFechaNac] = useState('')
  const [buscando, setBuscando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [buscado, setBuscado] = useState(false)
  const [resultados, setResultados] = useState<PacienteCabecera[]>([])
  const [farmaceutico, setFarmaceutico] = useState('')
  // PASO 2 (por receta): ítems revelados, loading del reveal, error del reveal, despacho en curso, selección.
  const [itemsPorReceta, setItemsPorReceta] = useState<Record<number, ItemEntrante[]>>({})
  const [revelando, setRevelando] = useState<number | null>(null)
  const [errorRevelar, setErrorRevelar] = useState<Record<number, string>>({})
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set())
  const [despachandoReceta, setDespachandoReceta] = useState<number | null>(null)

  const camposOk = nombre.trim() !== '' && apellido.trim() !== '' && fechaNac.trim() !== ''

  const resetPaso2 = () => { setItemsPorReceta({}); setErrorRevelar({}); setSeleccion(new Set()); setRevelando(null) }

  const limpiar = () => {
    setNombre(''); setApellido(''); setFechaNac('')
    setError(null); setBuscado(false); setResultados([]); setFarmaceutico('')
    resetPaso2()
  }

  const cerrar = () => { limpiar(); onClose() }

  const buscar = async () => {
    if (!camposOk) return   // no llamamos al RPC con campos incompletos
    setBuscando(true)
    setError(null)
    resetPaso2()
    try {
      const res = await buscarPaciente(nombre.trim(), apellido.trim(), fechaNac)
      setResultados(res)
      setBuscado(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo buscar')
    } finally {
      setBuscando(false)
    }
  }

  // PASO 2: revelar los ítems de una receta (registra el reveal server-side) y mostrarlos.
  const verDespachar = async (recetaBaseId: number) => {
    setRevelando(recetaBaseId)
    setErrorRevelar((m) => { const n = { ...m }; delete n[recetaBaseId]; return n })
    try {
      const items = await revelarItems(recetaBaseId, 'sinqr')
      setItemsPorReceta((m) => ({ ...m, [recetaBaseId]: items }))
      setSeleccion((s) => { const n = new Set(s); items.forEach((it) => n.add(it.item_id)); return n })
    } catch (e) {
      setErrorRevelar((m) => ({ ...m, [recetaBaseId]: e instanceof Error ? e.message : 'No se pudo revelar' }))
    } finally {
      setRevelando(null)
    }
  }

  const toggle = (id: number) =>
    setSeleccion((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  const despacharReceta = async (recetaBaseId: number, items: ItemEntrante[]) => {
    if (!farmaceutico.trim()) { toast.error('Nombre del farmacéutico requerido'); return }
    const ids = items.map((i) => i.item_id).filter((id) => seleccion.has(id))
    if (ids.length === 0) { toast.error('Selecciona al menos un ítem'); return }
    setDespachandoReceta(recetaBaseId)
    try {
      const res = await despacharDirigido(recetaBaseId, ids, farmaceutico.trim())
      toast.success(`${res?.despachados ?? 0} ítem(s) despachado(s)`)
      onDespachado?.()       // refresca la bandeja
      await buscar()         // vuelve al paso 1 con la cabecera actualizada (lo despachado ya no vuelve)
    } catch (e: any) {
      const msg = e?.message || 'No se pudo despachar'
      if (/sin ítems despachables/i.test(msg)) { toast.warning('Esos ítems ya fueron despachados (actualizado)'); await buscar() }
      else toast.error(msg)
    } finally {
      setDespachandoReceta(null)
    }
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={cerrar}>
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b">
          <h2 className="font-bold text-lg text-[#3a2410] flex items-center gap-2"><UserSearch className="h-5 w-5" /> Buscar sin QR</h2>
          <button onClick={cerrar} className="text-gray-400 hover:text-gray-700"><X className="h-5 w-5" /></button>
        </div>

        <div className="p-5 space-y-4">
          {/* Identidad del paciente (3 campos obligatorios, match exacto) */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-gray-700">Datos del paciente</label>
            <div className="grid grid-cols-2 gap-2">
              <input
                type="text" value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Nombre"
                autoComplete="off" spellCheck={false}
                className="p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
              />
              <input
                type="text" value={apellido} onChange={(e) => setApellido(e.target.value)} placeholder="Apellido"
                autoComplete="off" spellCheck={false}
                className="p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
              />
            </div>
            <div className="flex gap-2">
              <input
                type="date" value={fechaNac} onChange={(e) => setFechaNac(e.target.value)}
                className="flex-1 p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
              />
              <Button onClick={buscar} disabled={!camposOk || buscando} className="bg-[#B45309] hover:bg-[#92400e]">
                {buscando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
                <span className="ml-1">Buscar</span>
              </Button>
            </div>
            <p className="text-xs text-gray-500">Los tres campos son obligatorios y deben coincidir exactamente.</p>
          </div>

          {/* Error de búsqueda */}
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 flex items-center justify-between">
              <span className="flex items-center gap-2"><AlertCircle className="h-4 w-4 shrink-0" /> No se pudo buscar.</span>
              <Button size="sm" variant="outline" onClick={buscar} disabled={buscando}>Reintentar</Button>
            </div>
          )}

          {/* Vacío (neutral) */}
          {!error && buscado && resultados.length === 0 && (
            <p className="text-sm text-gray-500 text-center py-6">Sin recetas pendientes para esos datos.</p>
          )}

          {/* Resultados — PASO 1 (cabecera) + PASO 2 (reveal) */}
          {!error && resultados.length > 0 && (
            <div className="space-y-4">
              <div>
                <label className="text-sm text-gray-600">Farmacéutico (requerido)</label>
                <input
                  type="text" value={farmaceutico} onChange={(e) => setFarmaceutico(e.target.value)}
                  placeholder="Tu nombre" autoComplete="off"
                  className="w-full mt-1 p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
                />
              </div>

              {resultados.map((p) => (
                <div key={p.paciente_ref} className="border rounded-lg overflow-hidden">
                  <div className="bg-green-50 p-3 flex items-center gap-2">
                    <CheckCircle className="h-5 w-5 text-green-600" />
                    <p className="font-medium text-sm">{p.paciente_nombre}</p>
                  </div>
                  <div className="p-3 space-y-3">
                    {p.recetas.map((r) => {
                      const items = itemsPorReceta[r.receta_base_id]
                      const errRev = errorRevelar[r.receta_base_id]
                      return (
                        <div key={r.receta_base_id} className="rounded-lg border border-gray-100 p-3 space-y-2">
                          {!items ? (
                            // PASO 1: solo el conteo + acción de revelar (sin med)
                            <div className="flex items-center justify-between gap-2">
                              <span className="text-sm text-gray-600">{r.n_items_pendientes} ítem(s) pendiente(s)</span>
                              <Button
                                size="sm" variant="outline"
                                onClick={() => verDespachar(r.receta_base_id)}
                                disabled={revelando === r.receta_base_id}
                                className="border-[#B45309] text-[#B45309] hover:bg-[#fdf6ee] shrink-0"
                              >
                                {revelando === r.receta_base_id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Eye className="h-4 w-4 mr-1" />}
                                Ver / despachar
                              </Button>
                            </div>
                          ) : (
                            // PASO 2: ítems revelados (con med; sin instrucciones) + despacho
                            <div className="space-y-2">
                              {items.map((it) => (
                                <label key={it.item_id} className="flex items-center gap-3 bg-gray-50 p-3 rounded-lg cursor-pointer">
                                  <input type="checkbox" checked={seleccion.has(it.item_id)} onChange={() => toggle(it.item_id)} />
                                  <Package className="h-4 w-4 text-[#B45309]" />
                                  <div className="flex-1">
                                    <p className="text-sm font-medium">{it.nombre_medicamento}</p>
                                    <p className="text-xs text-gray-500">{it.dosis} · {it.frecuencia} · cant: {it.cantidad}</p>
                                  </div>
                                </label>
                              ))}
                              <Button
                                onClick={() => despacharReceta(r.receta_base_id, items)}
                                disabled={despachandoReceta === r.receta_base_id || !farmaceutico.trim() || !items.some((it) => seleccion.has(it.item_id))}
                                className="w-full bg-green-600 hover:bg-green-700"
                              >
                                {despachandoReceta === r.receta_base_id ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                                Despachar seleccionados
                              </Button>
                            </div>
                          )}
                          {/* Error del reveal (paso 2) con reintentar */}
                          {errRev && (
                            <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-xs text-red-700 flex items-center justify-between">
                              <span className="flex items-center gap-1"><AlertCircle className="h-3.5 w-3.5 shrink-0" /> No se pudo mostrar la receta.</span>
                              <Button size="sm" variant="outline" onClick={() => verDespachar(r.receta_base_id)} disabled={revelando === r.receta_base_id}>Reintentar</Button>
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
