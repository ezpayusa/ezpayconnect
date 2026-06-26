// Bandeja de recetas entrantes (Frente B) — R3: patrón de 2 PASOS (gate reveal-registrado, Puerta 1).
// PASO 1 (lista): RPC listar_recetas_entrantes devuelve CABECERA (paciente, médico, fecha, n_pendientes, sucursales).
//   SIN medicamento.
// PASO 2 (expandir): revelar_items_receta(receta_id,'bandeja') trae el med Y registra el reveal (mig 154, bloqueante).
//   Recién ahí se ven los ítems y se despacha. El despacho sigue por receta_id (registrar_dispensacion_dirigida).
// La UI es solo gating por 'recetas_dispensar'; la barrera real es el RPC.
import { useCallback, useEffect, useState } from 'react'
import { toast } from 'sonner'
import { ClipboardList, QrCode, UserSearch, Loader2, Package, ChevronDown, ChevronRight, Lock, RefreshCw, Eye, AlertCircle, Building2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { useRecetasEntrantes, type RecetaEntrante, type ItemEntrante } from '@/farmacia/hooks/useRecetasEntrantes'
import EscanearQRModal from '@/farmacia/pages/EscanearQRModal'
import BuscarPacienteModal from '@/farmacia/pages/BuscarPacienteModal'

export default function FarmaciaRecetasPage() {
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const puede = tienePermiso('recetas_dispensar')
  const { listar, revelarItems, despacharDirigido } = useRecetasEntrantes()

  const [recetas, setRecetas] = useState<RecetaEntrante[]>([])
  const [cargando, setCargando] = useState(false)
  const [expandida, setExpandida] = useState<number | null>(null)
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set())
  const [farmaceutico, setFarmaceutico] = useState('')
  const [despachando, setDespachando] = useState(false)
  const [scanOpen, setScanOpen] = useState(false)
  const [buscarOpen, setBuscarOpen] = useState(false)
  // PASO 2 (reveal) — KEYED por receta_id para no mezclar ítems revelados entre recetas.
  const [itemsPorReceta, setItemsPorReceta] = useState<Record<number, ItemEntrante[]>>({})
  const [revelandoReceta, setRevelandoReceta] = useState<number | null>(null)
  const [errorRevelar, setErrorRevelar] = useState<Record<number, string>>({})

  const recargar = useCallback(async () => {
    if (!puede) return
    setCargando(true)
    try {
      setRecetas(await listar())
    } catch (e: any) {
      toast.error(e?.message || 'No se pudo cargar la bandeja')
    } finally {
      setCargando(false)
    }
  }, [puede, listar])

  useEffect(() => { if (!permLoading && puede) void recargar() }, [permLoading, puede, recargar])

  // PASO 2: revela los ítems de una receta (registra el reveal server-side) y los guarda KEYED por receta.
  const revelar = useCallback(async (recetaId: number) => {
    setRevelandoReceta(recetaId)
    setErrorRevelar((m) => { const n = { ...m }; delete n[recetaId]; return n })
    try {
      const its = await revelarItems(recetaId, 'bandeja')
      setItemsPorReceta((m) => ({ ...m, [recetaId]: its }))
      setSeleccion(new Set(its.map((i) => i.item_id)))
    } catch (e: any) {
      setErrorRevelar((m) => ({ ...m, [recetaId]: e?.message || 'No se pudo mostrar la receta' }))
    } finally {
      setRevelandoReceta(null)
    }
  }, [revelarItems])

  const abrir = (r: RecetaEntrante) => {
    if (!r.tiene_token) return // fila deshabilitada
    if (expandida === r.receta_id) { setExpandida(null); return }
    setExpandida(r.receta_id)
    setFarmaceutico('')
    const ya = itemsPorReceta[r.receta_id]
    if (ya) {
      setSeleccion(new Set(ya.map((i) => i.item_id)))   // ya revelada: reusa
    } else {
      setSeleccion(new Set())
      void revelar(r.receta_id)                          // revela (registra) al abrir
    }
  }

  const toggle = (id: number) =>
    setSeleccion((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  const despachar = async (r: RecetaEntrante) => {
    if (!farmaceutico.trim()) { toast.error('Nombre del farmacéutico requerido'); return }
    const ids = [...seleccion]
    if (ids.length === 0) { toast.error('Selecciona al menos un ítem'); return }
    setDespachando(true)
    try {
      const res = await despacharDirigido(r.receta_id, ids, farmaceutico.trim())
      const ya = ids.length - (res?.despachados ?? 0)
      if ((res?.despachados ?? 0) > 0 && ya > 0)
        toast.warning(`${res.despachados} despachado(s); ${ya} ya estaban despachados (actualizado)`)
      else toast.success(`${res?.despachados ?? 0} ítem(s) despachado(s)`)
      setExpandida(null)
      setItemsPorReceta((m) => { const n = { ...m }; delete n[r.receta_id]; return n })   // fuerza re-reveal fresco
      await recargar()
    } catch (e: any) {
      const msg = e?.message || 'No se pudo despachar'
      if (/sin ítems despachables/i.test(msg)) {
        toast.warning('Esos ítems ya fueron despachados (actualizado)')
        setExpandida(null)
        setItemsPorReceta((m) => { const n = { ...m }; delete n[r.receta_id]; return n })
        await recargar()
      } else toast.error(msg)
    } finally {
      setDespachando(false)
    }
  }

  if (permLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-[#B45309]" /></div>
  }

  if (!puede) {
    return (
      <div className="max-w-md mx-auto mt-16 text-center">
        <Lock className="h-10 w-10 text-gray-400 mx-auto mb-3" />
        <h2 className="font-semibold text-gray-700">Sin permiso</h2>
        <p className="text-sm text-gray-500">Tu rol no puede despachar recetas (se requiere <code>recetas_dispensar</code>).</p>
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <ClipboardList className="h-7 w-7 text-[#B45309]" />
          <div>
            <h1 className="text-2xl font-bold text-[#3a2410]">Recetas entrantes</h1>
            <p className="text-sm text-gray-500">Recetas dirigidas a tu farmacia, pendientes de despacho.</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={recargar} disabled={cargando}>
            <RefreshCw className={`h-4 w-4 mr-1 ${cargando ? 'animate-spin' : ''}`} /> Actualizar
          </Button>
          <Button variant="outline" onClick={() => setBuscarOpen(true)} className="border-[#B45309] text-[#B45309] hover:bg-[#fdf6ee]">
            <UserSearch className="h-4 w-4 mr-1" /> Buscar sin QR
          </Button>
          <Button onClick={() => setScanOpen(true)} className="bg-[#B45309] hover:bg-[#92400e]">
            <QrCode className="h-4 w-4 mr-1" /> Escanear QR (walk-in)
          </Button>
        </div>
      </div>

      {cargando && recetas.length === 0 ? (
        <div className="flex justify-center py-16"><Loader2 className="h-8 w-8 animate-spin text-[#B45309]" /></div>
      ) : recetas.length === 0 ? (
        <div className="text-center py-16 text-gray-500">
          <ClipboardList className="h-10 w-10 mx-auto mb-3 text-gray-300" />
          No hay recetas entrantes pendientes.
        </div>
      ) : (
        <div className="space-y-3">
          {recetas.map((r) => {
            const nPend = r.n_pendientes ?? 0
            const abierta = expandida === r.receta_id
            const sucursales = (r.sucursales ?? []).map((s) => s.sucursal_nombre).filter(Boolean).join(', ')
            const items = itemsPorReceta[r.receta_id]
            const errRev = errorRevelar[r.receta_id]
            return (
              <div key={r.receta_id} className={`bg-white rounded-xl border ${r.tiene_token ? 'border-gray-200' : 'border-gray-100 opacity-60'}`}>
                <button
                  onClick={() => abrir(r)}
                  disabled={!r.tiene_token}
                  title={r.tiene_token ? '' : 'PDF no generado — no despachable'}
                  className={`w-full flex items-center gap-3 p-4 text-left ${r.tiene_token ? 'cursor-pointer hover:bg-gray-50' : 'cursor-not-allowed'}`}
                >
                  {r.tiene_token ? (abierta ? <ChevronDown className="h-5 w-5 text-gray-400" /> : <ChevronRight className="h-5 w-5 text-gray-400" />) : <Lock className="h-5 w-5 text-gray-300" />}
                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-[#1a2a3a] truncate">{r.paciente_nombre || 'Paciente'}</p>
                    <p className="text-xs text-gray-500 truncate">
                      {r.medico_nombre || 'Médico'} · {new Date(r.created_at).toLocaleDateString()} · {nPend} ítem(s) pendiente(s)
                    </p>
                    {sucursales && (
                      <p className="text-xs text-[#B45309] truncate flex items-center gap-1"><Building2 className="h-3 w-3 shrink-0" /> {sucursales}</p>
                    )}
                  </div>
                  {!r.tiene_token && <span className="text-xs text-amber-600 font-medium shrink-0">PDF no generado</span>}
                </button>

                {abierta && r.tiene_token && (
                  <div className="px-4 pb-4 border-t pt-4 space-y-3">
                    {revelandoReceta === r.receta_id ? (
                      <div className="flex justify-center py-4 text-gray-400"><Loader2 className="h-5 w-5 animate-spin" /></div>
                    ) : errRev ? (
                      <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-xs text-red-700 flex items-center justify-between">
                        <span className="flex items-center gap-1"><AlertCircle className="h-3.5 w-3.5 shrink-0" /> No se pudo mostrar la receta.</span>
                        <Button size="sm" variant="outline" onClick={() => revelar(r.receta_id)}>Reintentar</Button>
                      </div>
                    ) : items ? (
                      <>
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
                        </div>
                        <div>
                          <label className="text-sm text-gray-600">Farmacéutico (requerido)</label>
                          <input
                            type="text" value={farmaceutico} onChange={(e) => setFarmaceutico(e.target.value)}
                            placeholder="Tu nombre" autoComplete="off"
                            className="w-full md:w-1/2 mt-1 p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
                          />
                        </div>
                        <Button onClick={() => despachar(r)} disabled={despachando || !farmaceutico.trim() || seleccion.size === 0}
                          className="bg-green-600 hover:bg-green-700">
                          {despachando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Eye className="h-4 w-4 mr-1" />}
                          Despachar seleccionados
                        </Button>
                      </>
                    ) : null}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      <EscanearQRModal open={scanOpen} onClose={() => setScanOpen(false)} />
      <BuscarPacienteModal open={buscarOpen} onClose={() => setBuscarOpen(false)} onDespachado={recargar} />
    </div>
  )
}
