// Walk-in QR (Frente B) — R2: patrón de 2 PASOS (gate reveal-registrado, Puerta 2).
// PASO 1 (verificar token): valida el token y muestra paciente + "N ítems pendientes". SIN medicamento.
// PASO 2 ("Ver / despachar"): revelar_items_receta(receta_id,'walkin_qr') trae el med Y registra el reveal
//         (server-side, actor=auth.uid; mig 154, bloqueante). Recién ahí se ven los ítems y se despacha.
// El despacho sigue por TOKEN (registrar_dispensacion), no por receta_id.
//
// SEGURIDAD DEL TOKEN (secreto del paciente):
//  · Vive solo en estado local de ESTE modal; se mantiene desde el paso 1 hasta el despacho.
//  · NUNCA se loguea (sin console.log), ni se persiste (storage/global/URL), ni autocomplete.
//  · Decodificación QR 100% client-side (html5-qrcode); jamás se envía la imagen/token a un tercero.
//  · Se limpia al cerrar/desmontar.
import { useEffect, useRef, useState } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { toast } from 'sonner'
import { X, Camera, Search, Loader2, CheckCircle, AlertCircle, Package, Eye } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useRecetasEntrantes, type CabeceraWalkin, type ItemEntrante } from '@/farmacia/hooks/useRecetasEntrantes'

interface Props { open: boolean; onClose: () => void }

const READER_ID = 'qr-reader-walkin'

export default function EscanearQRModal({ open, onClose }: Props) {
  const { verificarToken, revelarItems, despacharWalkin } = useRecetasEntrantes()
  // Token transitorio: en estado local; se mantiene del paso 1 al despacho; nunca sale salvo hacia el RPC.
  const [token, setToken] = useState('')
  const [verificando, setVerificando] = useState(false)
  const [cabecera, setCabecera] = useState<CabeceraWalkin | null>(null)
  // PASO 2: ítems revelados (con med), loading/error del reveal.
  const [items, setItems] = useState<ItemEntrante[] | null>(null)
  const [revelando, setRevelando] = useState(false)
  const [errorRevelar, setErrorRevelar] = useState<string | null>(null)
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set())
  const [farmaceutico, setFarmaceutico] = useState('')
  const [despachando, setDespachando] = useState(false)
  const [camActiva, setCamActiva] = useState(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)

  const resetReveal = () => { setItems(null); setRevelando(false); setErrorRevelar(null); setSeleccion(new Set()) }

  const limpiar = () => {
    setToken('')
    setCabecera(null)
    setFarmaceutico('')
    setVerificando(false)
    setDespachando(false)
    resetReveal()
  }

  const detenerCamara = async () => {
    const s = scannerRef.current
    scannerRef.current = null
    if (s) { try { await s.stop() } catch { /* ya detenido */ } try { s.clear() } catch { /* noop */ } }
  }

  const cerrar = async () => {
    await detenerCamara()
    setCamActiva(false)
    limpiar()           // descarta el token al cerrar
    onClose()
  }

  // PASO 1: verifica el token → cabecera (sin med).
  const verificar = async (valor?: string) => {
    const t = (valor ?? token).trim()
    if (!t) { toast.error('Ingresa o escanea el código de la receta'); return }
    setVerificando(true)
    setCabecera(null)
    resetReveal()
    try {
      const cab = await verificarToken(t)
      setCabecera(cab)
    } catch (e: any) {
      // Token EZP- viejo o vencido / inválido → mensaje claro, sin crash.
      toast.error(e?.message || 'Receta no válida o no autorizada')
    } finally {
      setVerificando(false)
    }
  }

  // PASO 2: revela los ítems de la receta del token (registra el reveal server-side) y los muestra.
  const verDespachar = async () => {
    if (!cabecera) return
    setRevelando(true)
    setErrorRevelar(null)
    try {
      const its = await revelarItems(cabecera.receta_id, 'walkin_qr')
      setItems(its)
      setSeleccion(new Set(its.map((i) => i.item_id)))
    } catch (e: any) {
      setErrorRevelar(e?.message || 'No se pudo mostrar la receta')
    } finally {
      setRevelando(false)
    }
  }

  // Cámara: decodifica client-side; al leer, verifica (paso 1) y se detiene.
  useEffect(() => {
    if (!camActiva) return
    let cancelado = false
    const scanner = new Html5Qrcode(READER_ID)
    scannerRef.current = scanner
    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: { width: 240, height: 240 } },
        async (decoded) => {
          if (cancelado) return
          cancelado = true
          await detenerCamara()
          setCamActiva(false)
          setToken(decoded)
          verificar(decoded)
        },
        () => { /* sin lectura en este frame; ignorar */ },
      )
      .catch(() => { toast.error('No se pudo abrir la cámara; usa la entrada manual'); setCamActiva(false) })
    return () => { cancelado = true; void detenerCamara() }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [camActiva])

  // Limpieza dura al desmontar.
  useEffect(() => () => { void detenerCamara() }, [])

  if (!open) return null

  const yaTodo = !!cabecera && cabecera.n_pendientes === 0

  const toggle = (id: number) =>
    setSeleccion((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  // Despacho POR TOKEN (registrar_dispensacion). El token se mantiene en estado desde el paso 1.
  const despachar = async () => {
    if (!items) return
    if (!farmaceutico.trim()) { toast.error('Nombre del farmacéutico requerido'); return }
    const ids = items.map((i) => i.item_id).filter((id) => seleccion.has(id))
    if (ids.length === 0) { toast.error('Selecciona al menos un ítem'); return }
    setDespachando(true)
    try {
      const res = await despacharWalkin(token, ids, farmaceutico.trim())
      toast.success(`${res?.despachados ?? 0} ítem(s) despachado(s)`)
      resetReveal()
      await verificar(token)   // vuelve al paso 1 con la cabecera actualizada (baja n_pendientes)
    } catch (e: any) {
      const msg = e?.message || 'No se pudo despachar'
      if (/sin ítems despachables/i.test(msg)) { toast.warning('Esos ítems ya fueron despachados (actualizado)'); resetReveal(); await verificar(token) }
      else toast.error(msg)
    } finally {
      setDespachando(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={cerrar}>
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b">
          <h2 className="font-bold text-lg text-[#3a2410]">Walk-in: escanear receta</h2>
          <button onClick={cerrar} className="text-gray-400 hover:text-gray-700"><X className="h-5 w-5" /></button>
        </div>

        <div className="p-5 space-y-4">
          {/* Entrada: cámara + manual (ambas) */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-gray-700">Código de la receta</label>
            <div className="flex gap-2">
              <input
                type="text"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                placeholder="Pega o escanea el código"
                autoComplete="off"
                spellCheck={false}
                className="flex-1 p-2.5 border border-gray-200 rounded-lg font-mono text-sm focus:outline-none focus:border-[#B45309]"
              />
              <Button onClick={() => verificar()} disabled={verificando} className="bg-[#B45309] hover:bg-[#92400e]">
                {verificando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
                <span className="ml-1">Verificar</span>
              </Button>
            </div>
            <p className="text-xs text-gray-500">Entrada manual (lector de mano o pegar el código) o cámara. Los PDF nuevos traen QR escaneable; los viejos (código en texto) van por entrada manual.</p>
            <button
              type="button"
              onClick={() => setCamActiva((v) => !v)}
              className="text-sm text-[#B45309] hover:underline flex items-center gap-1"
            >
              <Camera className="h-4 w-4" /> {camActiva ? 'Cerrar cámara' : 'Usar cámara'}
            </button>
            {camActiva && <div id={READER_ID} className="rounded-lg overflow-hidden border" />}
          </div>

          {/* Resultado */}
          {cabecera && (
            <div className="border rounded-lg overflow-hidden">
              <div className={`p-4 ${yaTodo ? 'bg-red-50' : 'bg-green-50'}`}>
                <div className="flex items-center gap-2">
                  {yaTodo ? <AlertCircle className="h-5 w-5 text-red-500" /> : <CheckCircle className="h-5 w-5 text-green-600" />}
                  <div>
                    <p className="font-medium text-sm">{cabecera.paciente_nombre || 'Paciente'}</p>
                    {cabecera.estado_dispensacion && <p className="text-xs text-gray-500">Estado: {cabecera.estado_dispensacion}</p>}
                  </div>
                </div>
              </div>

              {yaTodo ? (
                <p className="p-4 text-sm text-gray-600">Todos los ítems de tu farmacia ya fueron despachados.</p>
              ) : !items ? (
                // PASO 1: conteo + acción de revelar (sin med). Si no hay pendientes, no se llega acá (yaTodo).
                <div className="p-4 space-y-2">
                  <p className="text-sm text-gray-600">{cabecera.n_pendientes} ítem(s) pendiente(s)</p>
                  <Button onClick={verDespachar} disabled={revelando} className="w-full bg-[#B45309] hover:bg-[#92400e]">
                    {revelando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Eye className="h-4 w-4 mr-1" />}
                    Ver / despachar
                  </Button>
                  {errorRevelar && (
                    <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-xs text-red-700 flex items-center justify-between">
                      <span className="flex items-center gap-1"><AlertCircle className="h-3.5 w-3.5 shrink-0" /> No se pudo mostrar la receta.</span>
                      <Button size="sm" variant="outline" onClick={verDespachar} disabled={revelando}>Reintentar</Button>
                    </div>
                  )}
                </div>
              ) : (
                // PASO 2: ítems revelados (con med; sin instrucciones) + despacho por token.
                <div className="p-4 space-y-3">
                  <div>
                    <label className="text-sm text-gray-600">Farmacéutico (requerido)</label>
                    <input
                      type="text" value={farmaceutico} onChange={(e) => setFarmaceutico(e.target.value)}
                      placeholder="Tu nombre" autoComplete="off"
                      className="w-full mt-1 p-2.5 border border-gray-200 rounded-lg text-sm focus:outline-none focus:border-[#B45309]"
                    />
                  </div>
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
                  <Button onClick={despachar} disabled={despachando || !farmaceutico.trim() || seleccion.size === 0}
                    className="w-full bg-green-600 hover:bg-green-700">
                    {despachando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                    Despachar seleccionados
                  </Button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
