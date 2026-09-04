import { useEffect, useState, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowLeft, MapPin, MapPinOff, CheckCircle2, AlertTriangle, Paperclip } from 'lucide-react'
import {
  obtenerVisita, reporteDeVisita, adjuntosDeVisita, listarResultados, configVisitasEfectiva,
  checkinVisita, checkoutVisita, guardarReporte,
  subirAdjuntoVisita, urlFirmada, validarAdjunto, ACCEPT_ADJUNTO,
  type VisitaComercial, type ItemCatalogo, type ResultadoCheckin,
} from '../lib/api'
import { reportarError, type ErrorInline } from '../lib/reportarError'
import { pedirUbicacion, coordsDe, avisoPrevio, type EstadoGeo } from '../lib/geo'

// Ficha de visita: check-in, check-out, informe y adjuntos.
//
// DECISIÓN (3): el resultado del check-in se muestra COMPLETO. Si vuelve verificado=false, la UI
// dice por qué — distancia, precisión, prospecto sin coordenada. Un check-in que se ve igual
// verificado o no le enseña al asesor que da lo mismo, y entonces el dato no vale nada.
export default function VisitaFichaPage() {
  const { id = '' } = useParams()
  const [v, setV] = useState<VisitaComercial | null>(null)
  const [reporte, setReporte] = useState<{ id: string; resultado: string; resumen: string; compromisos: string | null } | null>(null)
  const [adjuntos, setAdjuntos] = useState<{ id: string; storage_path: string }[]>([])
  const [progreso, setProgreso] = useState<number | null>(null)
  const [errAdjunto, setErrAdjunto] = useState<ErrorInline>(null)
  const [huerfano, setHuerfano] = useState<string | null>(null)
  const [resultados, setResultados] = useState<ItemCatalogo[]>([])
  const [precisionMax, setPrecisionMax] = useState<number | null>(null)
  const [radio, setRadio] = useState<number | null>(null)
  const [geo, setGeo] = useState<EstadoGeo>({ estado: 'inicial' })
  const [ultimoCheckin, setUltimoCheckin] = useState<ResultadoCheckin | null>(null)
  const [cargando, setCargando] = useState(true)
  const [trabajando, setTrabajando] = useState(false)

  const [resultado, setResultado] = useState('')
  const [resumen, setResumen] = useState('')
  const [compromisos, setCompromisos] = useState('')
  const [errReporte, setErrReporte] = useState<ErrorInline>(null)

  const cargar = useCallback(async () => {
    setCargando(true)
    const [vi, re, ad, cat, cfg] = await Promise.all([
      obtenerVisita(id), reporteDeVisita(id), adjuntosDeVisita(id), listarResultados(), configVisitasEfectiva(),
    ])
    if (vi.error) reportarError(vi.error)
    setV((vi.data ?? null) as unknown as VisitaComercial | null)
    setReporte((re.data ?? null) as never)
    if (ad.data) setAdjuntos(ad.data as never)
    if (cat.data) { setResultados(cat.data as ItemCatalogo[]); if (!resultado) setResultado((cat.data[0] as ItemCatalogo)?.codigo ?? '') }
    if (cfg.data && Array.isArray(cfg.data) && cfg.data[0]) {
      setPrecisionMax(Number(cfg.data[0].precision_max_m)); setRadio(Number(cfg.data[0].radio_checkin_m))
    }
    setCargando(false)
  }, [id])

  useEffect(() => { void cargar() }, [cargar])

  const onCheckin = async () => {
    setTrabajando(true)
    const g = geo.estado === 'ok' ? geo : await pedirUbicacion()
    setGeo(g)
    const { data, error } = await checkinVisita(id, coordsDe(g))
    setTrabajando(false)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    const r = data as unknown as ResultadoCheckin
    setUltimoCheckin(r)
    // No se dice "listo" a secas: si no verificó, el toast ya lo anticipa y el bloque de abajo lo
    // explica. Que el asesor se entere acá, no cuando el supervisor se lo reclame.
    if (r?.verificado) toast.success('Check-in verificado')
    else toast.warning('Check-in registrado SIN verificar')
    void cargar()
  }

  const onCheckout = async () => {
    setTrabajando(true)
    const g = geo.estado === 'ok' ? geo : await pedirUbicacion()
    setGeo(g)
    const { error } = await checkoutVisita(id, coordsDe(g))
    setTrabajando(false)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    toast.success('Check-out registrado')
    void cargar()
  }

  const onGuardarReporte = async () => {
    setErrReporte(null); setTrabajando(true)
    const { error } = await guardarReporte({ visitaId: id, resultado, resumen, compromisos: compromisos || null })
    setTrabajando(false)
    if (error) { reportarError(error, { setInline: setErrReporte, onRecargar: () => void cargar() }); return }
    toast.success('Informe guardado')
    void cargar()
  }

  const onAdjuntar = async (archivo: File | null) => {
    if (!archivo || !v) return
    setErrAdjunto(null); setHuerfano(null)

    // Validación ANTES de tocar la red. No es el control (el bucket lo impone igual): es que
    // nadie suba 40 MB en 3G para que lo rechacen al final.
    const motivo = validarAdjunto(archivo)
    if (motivo) { setErrAdjunto({ campo: 'adjunto', mensaje: motivo }); return }

    setTrabajando(true); setProgreso(0)
    const { error, huerfano: h } = await subirAdjuntoVisita(
      { id: v.id, pais_id: v.pais_id }, archivo, setProgreso)
    setTrabajando(false); setProgreso(null)
    if (error) {
      reportarError(error, { setInline: setErrAdjunto, onRecargar: () => void cargar() })
      if (h) setHuerfano(h)   // el borrado compensatorio también falló: se dice, no se esconde
      return
    }
    toast.success('Adjunto guardado')
    void cargar()
  }

  const verAdjunto = async (path: string) => {
    const { data, error } = await urlFirmada(path)
    if (error || !data?.signedUrl) { reportarError(error ?? { message: 'sin url' }); return }
    // La URL sólo existe en esta variable y en la pestaña que se abre: no se guarda en ningún lado.
    window.open(data.signedUrl, '_blank', 'noopener')
  }

  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>
  if (!v) {
    return (
      <div className="rounded-lg border bg-white p-6">
        <p className="text-sm text-gray-700">No encontramos esa visita en tu cartera.</p>
        <Link to="/comercial/hoy" className="mt-3 inline-block text-sm text-[#1E5C8E]">← Volver</Link>
      </div>
    )
  }

  const aviso = avisoPrevio(geo, precisionMax)
  const motivo = ultimoCheckin?.motivo ?? v.checkin_motivo

  return (
    <div className="space-y-4">
      <Link to="/comercial/hoy" className="inline-flex items-center gap-1 text-sm text-[#1E5C8E]">
        <ArrowLeft className="h-4 w-4" /> Volver
      </Link>

      <section className="rounded-lg border bg-white p-4">
        <h1 className="font-semibold text-gray-900">{v.prospecto?.nombre ?? 'Visita'}</h1>
        <p className="mt-0.5 text-xs text-gray-500">
          {v.fecha_planificada} · estado {v.estado}
          {v.prospecto?.lat == null && ' · el prospecto NO tiene coordenada cargada'}
        </p>
      </section>

      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Check-in</h2>

        {!v.checkin_at ? (
          <>
            <div className="mt-3 rounded border bg-gray-50 p-3 text-sm">
              <div className="flex items-center gap-2">
                {geo.estado === 'ok' ? <MapPin className="h-4 w-4 text-green-700" /> : <MapPinOff className="h-4 w-4 text-gray-500" />}
                <span id="geo-estado">
                  {geo.estado === 'ok' && <>precisión <b>±{geo.precision_m} m</b>{precisionMax != null && <> · máximo {precisionMax} m</>}{radio != null && <> · radio {radio} m</>}</>}
                  {geo.estado === 'inicial' && 'Ubicación sin leer'}
                  {geo.estado === 'pidiendo' && 'Pidiendo ubicación…'}
                  {geo.estado === 'denegado' && 'Permiso DENEGADO'}
                  {geo.estado === 'no_disponible' && 'Sin ubicación en este navegador'}
                  {geo.estado === 'error' && geo.mensaje}
                </span>
                <button type="button" onClick={async () => { setGeo({ estado: 'pidiendo' }); setGeo(await pedirUbicacion()) }}
                  className="ml-auto text-xs text-[#1E5C8E] underline">Leer ubicación</button>
              </div>
              {aviso && (
                <p id="geo-aviso" className="mt-2 flex items-start gap-1.5 text-xs text-amber-800">
                  <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />{aviso}
                </p>
              )}
            </div>
            <button type="button" id="btn-checkin" onClick={onCheckin} disabled={trabajando}
              className="mt-3 rounded-md bg-[#1E5C8E] px-4 py-2 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
              Hacer check-in
            </button>
          </>
        ) : (
          <div id="checkin-resultado" className="mt-3 space-y-2">
            <div className={`flex items-start gap-2 rounded p-3 text-sm ${v.checkin_verificado ? 'bg-green-50 text-green-900' : 'bg-amber-50 text-amber-900'}`}>
              {v.checkin_verificado
                ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
                : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
              <div>
                <p className="font-medium">
                  {v.checkin_verificado ? 'Check-in VERIFICADO' : 'Check-in registrado SIN verificar'}
                </p>
                {/* El detalle completo: distancia, motivo y origen. Nunca sólo el booleano. */}
                <p className="mt-0.5 text-xs">
                  {new Date(v.checkin_at).toLocaleTimeString()}
                  {v.checkin_distancia_m != null && <> · a {Math.round(v.checkin_distancia_m)} m del prospecto</>}
                  {v.checkin_precision_m != null && <> · precisión ±{Math.round(v.checkin_precision_m)} m</>}
                  {v.checkin_origen === 'diferido' && ' · registrado en diferido'}
                </p>
                {!v.checkin_verificado && motivo && (
                  <p id="checkin-motivo" className="mt-1 text-xs">Por qué no verificó: {motivo}</p>
                )}
                {!v.checkin_verificado && (
                  <p className="mt-1 text-xs opacity-80">
                    Queda registrado igual. "Verificado" sólo dice que la ubicación reportada es
                    consistente con la del prospecto.
                  </p>
                )}
              </div>
            </div>
            {!v.checkout_at && (
              <button type="button" id="btn-checkout" onClick={onCheckout} disabled={trabajando}
                className="rounded-md border border-[#1E5C8E] px-4 py-2 text-sm text-[#1E5C8E] hover:bg-blue-50 disabled:opacity-50">
                Hacer check-out
              </button>
            )}
            {v.checkout_at && <p className="text-xs text-gray-600">Check-out a las {new Date(v.checkout_at).toLocaleTimeString()}</p>}
          </div>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Informe</h2>
        {reporte ? (
          <div className="mt-2 space-y-1 text-sm">
            <p><span className="text-gray-500">Resultado:</span> {reporte.resultado}</p>
            <p className="whitespace-pre-wrap">{reporte.resumen}</p>
            {reporte.compromisos && <p className="text-gray-700"><span className="text-gray-500">Pendientes:</span> {reporte.compromisos}</p>}
            <p className="pt-1 text-xs text-gray-500">Hay un solo informe por visita.</p>
          </div>
        ) : (
          <div className="mt-3 space-y-2">
            <select id="resultado" value={resultado} onChange={(e) => setResultado(e.target.value)}
              className="w-full rounded border px-2 py-1.5 text-sm">
              {resultados.map(r => <option key={r.codigo} value={r.codigo}>{r.etiqueta}</option>)}
            </select>
            <textarea id="resumen" value={resumen} onChange={(e) => setResumen(e.target.value)} rows={3}
              placeholder="Qué pasó en la visita" className="w-full rounded border px-2 py-1.5 text-sm" />
            <input id="compromisos" value={compromisos} onChange={(e) => setCompromisos(e.target.value)}
              placeholder="Qué queda pendiente" className="w-full rounded border px-2 py-1.5 text-sm" />
            {errReporte && <p className="text-xs text-red-600">{errReporte.mensaje}</p>}
            <button type="button" id="btn-reporte" onClick={onGuardarReporte} disabled={trabajando || !resumen.trim()}
              className="rounded-md bg-[#1E5C8E] px-4 py-2 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
              Guardar informe
            </button>
          </div>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <h2 className="flex items-center gap-1.5 font-semibold text-gray-900">
          <Paperclip className="h-4 w-4" /> Adjuntos
        </h2>
        {adjuntos.length === 0
          ? <p className="mt-1 text-sm text-gray-500">Sin fotos ni videos todavía.</p>
          : <ul className="mt-1 space-y-1">{adjuntos.map(a => (
              <li key={a.id}>
                <button type="button" onClick={() => void verAdjunto(a.storage_path)}
                  className="truncate text-xs text-[#1E5C8E] underline">
                  {a.storage_path.split('/').pop()}
                </button>
              </li>))}</ul>}

        {!v.checkin_at ? (
          <p className="mt-2 rounded bg-gray-50 p-2 text-xs text-gray-600">
            Los adjuntos se suben después del check-in.
          </p>
        ) : (
          <>
            <input type="file" id="adjunto" accept={ACCEPT_ADJUNTO} disabled={trabajando}
              onChange={(e) => void onAdjuntar(e.target.files?.[0] ?? null)}
              className="mt-2 block w-full text-xs" />
            {progreso != null && (
              <div className="mt-2">
                <div className="h-1.5 w-full overflow-hidden rounded bg-gray-200">
                  <div id="barra-progreso" className="h-full bg-[#1E5C8E] transition-all"
                    style={{ width: `${progreso}%` }} />
                </div>
                <p className="mt-1 text-xs text-gray-600">Subiendo… {progreso}%</p>
              </div>
            )}
            {errAdjunto && <p id="err-adjunto" className="mt-2 text-xs text-red-600">{errAdjunto.mensaje}</p>}
            {huerfano && (
              <p className="mt-1 text-xs text-amber-800">
                No se pudo limpiar el archivo a medio subir. Avisale a soporte con este dato:
                <span className="font-mono"> {huerfano}</span>
              </p>
            )}
          </>
        )}
      </section>
    </div>
  )
}
