// Walk-in QR (Frente B). El paciente presenta el QR/código del PDF; la farmacia verifica
// y despacha por TOKEN vía RPC (verificar_receta_despacho / registrar_dispensacion).
//
// SEGURIDAD DEL TOKEN (secreto del paciente):
//  · Vive solo en estado local de ESTE modal mientras dura el flujo.
//  · NUNCA se loguea (sin console.log), ni se persiste (storage/global/URL), ni autocomplete.
//  · Decodificación QR 100% client-side (html5-qrcode); jamás se envía la imagen/token a
//    una API de decodificación de terceros.
//  · Se limpia al cerrar/desmontar.
// La UI es solo gating; la barrera real es el RPC.
import { useEffect, useRef, useState } from 'react'
import { Html5Qrcode } from 'html5-qrcode'
import { toast } from 'sonner'
import { X, Camera, Search, Loader2, CheckCircle, AlertCircle, Package } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useRecetasEntrantes, type DetalleEntrante } from '@/farmacia/hooks/useRecetasEntrantes'

interface Props { open: boolean; onClose: () => void }

const READER_ID = 'qr-reader-walkin'

export default function EscanearQRModal({ open, onClose }: Props) {
  const { verificarToken, despacharWalkin } = useRecetasEntrantes()
  // Token transitorio: en estado local; nunca sale de aquí salvo hacia el RPC.
  const [token, setToken] = useState('')
  const [verificando, setVerificando] = useState(false)
  const [verificada, setVerificada] = useState<DetalleEntrante | null>(null)
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set())
  const [farmaceutico, setFarmaceutico] = useState('')
  const [despachando, setDespachando] = useState(false)
  const [camActiva, setCamActiva] = useState(false)
  const scannerRef = useRef<Html5Qrcode | null>(null)

  const limpiar = () => {
    setToken('')
    setVerificada(null)
    setSeleccion(new Set())
    setFarmaceutico('')
    setVerificando(false)
    setDespachando(false)
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

  const verificar = async (valor?: string) => {
    const t = (valor ?? token).trim()
    if (!t) { toast.error('Ingresa o escanea el código de la receta'); return }
    setVerificando(true)
    setVerificada(null)
    try {
      const rec = await verificarToken(t)
      setVerificada(rec)
      setSeleccion(new Set((rec.items || []).filter((i) => !i.dispensado).map((i) => i.item_id)))
    } catch (e: any) {
      // Token EZP- viejo o vencido → mensaje claro, sin crash.
      toast.error(e?.message || 'Receta no válida o no autorizada')
    } finally {
      setVerificando(false)
    }
  }

  // Cámara: decodifica client-side; al leer, verifica y se detiene.
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

  const pendientes = (verificada?.items || []).filter((i) => !i.dispensado)
  const yaTodo = !!verificada && pendientes.length === 0

  const toggle = (id: number) =>
    setSeleccion((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  const despachar = async () => {
    if (!verificada) return
    if (!farmaceutico.trim()) { toast.error('Nombre del farmacéutico requerido'); return }
    const ids = [...seleccion]
    if (ids.length === 0) { toast.error('Selecciona al menos un ítem'); return }
    setDespachando(true)
    try {
      const res = await despacharWalkin(token, ids, farmaceutico.trim())
      const ya = ids.length - (res?.despachados ?? 0)
      if ((res?.despachados ?? 0) > 0 && ya > 0)
        toast.warning(`${res.despachados} despachado(s); ${ya} ya estaban despachados (actualizado)`)
      else toast.success(`${res?.despachados ?? 0} ítem(s) despachado(s)`)
      await verificar(token)   // refresca estado (concurrencia)
    } catch (e: any) {
      const msg = e?.message || 'No se pudo despachar'
      if (/sin ítems despachables/i.test(msg)) { toast.warning('Esos ítems ya fueron despachados (actualizado)'); await verificar(token) }
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
          {verificada && (
            <div className="border rounded-lg overflow-hidden">
              <div className={`p-4 ${yaTodo ? 'bg-red-50' : 'bg-green-50'}`}>
                <div className="flex items-center gap-2">
                  {yaTodo ? <AlertCircle className="h-5 w-5 text-red-500" /> : <CheckCircle className="h-5 w-5 text-green-600" />}
                  <div>
                    <p className="font-medium text-sm">{verificada.paciente_nombre || 'Paciente'}</p>
                    <p className="text-xs text-gray-500">Estado: {verificada.estado}</p>
                  </div>
                </div>
              </div>

              {!yaTodo && (
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
                    {pendientes.map((it) => (
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
              {yaTodo && <p className="p-4 text-sm text-gray-600">Todos los ítems de tu farmacia ya fueron despachados.</p>}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
