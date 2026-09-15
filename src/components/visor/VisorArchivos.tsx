import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import {
  AlertTriangle, ChevronLeft, ChevronRight, Download, ExternalLink, FileText, Loader2,
  Maximize, Minimize, RefreshCw, RotateCw, X, ZoomIn, ZoomOut,
} from 'lucide-react'
import { Dialog, DialogOverlay, DialogPortal } from '@/components/ui/dialog'
import {
  MENSAJE_FALLA, descargarArchivo, guardarBlob, nombreDeArchivo, obtenerBlob, type MotivoFalla,
} from '@/lib/signedUrl'

// ############################################################################################
// Visor de archivos compartido: zoom, pan, rotación, pantalla completa y navegación
// ############################################################################################
// Lo montan las pantallas vía `useVisor()`, nunca copiado. No conoce ninguna tabla: recibe
// { bucket, path } y se encarga de firmar, bajar y mostrar.
//
// CICLO DE VIDA DEL ARCHIVO. Por cada archivo que se muestra: firmar (60 s) → fetch → blob →
// URL.createObjectURL. Al cambiar de archivo o cerrar: abort del fetch en curso + revokeObjectURL.
// La URL firmada no pasa por acá: la maneja `obtenerBlob` y muere dentro de esa función.
//
// Escrito a mano, sin dependencia: zoom/pan/rotación de un solo raster son transformaciones CSS
// sobre el mismo bitmap, y el PDF lo resuelve el visor nativo del navegador.

export interface ArchivoVisor {
  bucket: string
  path: string
  /** Para la descarga y el título. Si falta, el último segmento del path. */
  nombre?: string
}

type Tipo = 'imagen' | 'pdf' | 'otro'
type Carga =
  | { estado: 'cargando' }
  | { estado: 'listo'; url: string; blob: Blob; tipo: Tipo }
  | { estado: 'error'; motivo: MotivoFalla }

const ESCALA_MIN = 0.25
const ESCALA_MAX = 8
const PASO = 1.25
const limitar = (e: number) => Math.min(ESCALA_MAX, Math.max(ESCALA_MIN, e))
const INICIAL = { escala: 1, x: 0, y: 0, rot: 0 }

const MIME_IMAGEN = ['image/jpeg', 'image/png', 'image/webp', 'image/gif']

function tipoDe(blob: Blob, path: string): Tipo {
  const t = (blob.type || '').toLowerCase()
  if (MIME_IMAGEN.includes(t)) return 'imagen'
  if (t === 'application/pdf') return 'pdf'
  // Storage suele mandar el Content-Type real; la extensión es el respaldo para octet-stream.
  const ext = path.split('.').pop()?.toLowerCase()
  if (ext && ['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext)) return 'imagen'
  if (ext === 'pdf') return 'pdf'
  return 'otro'
}

// iOS Safari (y la PWA del paciente) muestra SOLO la primera página de un PDF dentro de un iframe.
// Ahí se ofrece abrir/descargar en vez de un visor que parece funcionar y esconde páginas.
const esIOS = () =>
  typeof navigator !== 'undefined'
  && (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1))

interface Props {
  archivos: ArchivoVisor[]
  indice: number
  onIndice: (i: number) => void
  onCerrar: () => void
}

export default function VisorArchivos({ archivos, indice, onIndice, onCerrar }: Props) {
  const archivo = archivos[indice]
  const nombre = archivo ? (archivo.nombre || nombreDeArchivo(archivo.bucket, archivo.path)) : ''
  const hayVarios = archivos.length > 1

  const [carga, setCarga] = useState<Carga>({ estado: 'cargando' })
  const [t, setT] = useState(INICIAL)
  const [reintento, setReintento] = useState(0)
  const [pantallaCompleta, setPantallaCompleta] = useState(false)
  const contenedor = useRef<HTMLDivElement>(null)
  const lienzo = useRef<HTMLDivElement>(null)

  // ---- carga del archivo actual ------------------------------------------------------------
  useEffect(() => {
    if (!archivo) return
    const ctrl = new AbortController()
    let url: string | null = null
    setCarga({ estado: 'cargando' })
    setT(INICIAL)
    obtenerBlob(archivo.bucket, archivo.path, ctrl.signal)
      .then((r) => {
        if (ctrl.signal.aborted) return
        // `in` y no `!r.ok`: sin strictNullChecks, la negación no estrecha la unión discriminada.
        if ('motivo' in r) { setCarga({ estado: 'error', motivo: r.motivo }); return }
        url = URL.createObjectURL(r.blob)
        setCarga({ estado: 'listo', url, blob: r.blob, tipo: tipoDe(r.blob, archivo.path) })
      })
      .catch((e) => {
        if ((e as Error)?.name !== 'AbortError') setCarga({ estado: 'error', motivo: 'red' })
      })
    return () => {
      ctrl.abort()
      if (url) URL.revokeObjectURL(url)
    }
  }, [archivo, reintento])

  // ---- navegación y controles -------------------------------------------------------------
  const ir = useCallback((d: number) => {
    if (!hayVarios) return
    onIndice((indice + d + archivos.length) % archivos.length)
  }, [hayVarios, indice, archivos.length, onIndice])

  const zoom = (factor: number) => setT((s) => ({ ...s, escala: limitar(s.escala * factor) }))
  const rotar = () => setT((s) => ({ ...s, rot: (s.rot + 90) % 360 }))
  const reiniciar = () => setT(INICIAL)

  const descargar = () => {
    if (!archivo) return
    if (carga.estado === 'listo') { guardarBlob(carga.blob, nombre); return }
    void descargarArchivo(archivo.bucket, archivo.path).then((r) => {
      if (r && 'motivo' in r) alert(MENSAJE_FALLA[r.motivo])
    })
  }

  const alternarPantallaCompleta = () => {
    const el = contenedor.current
    if (!el) return
    if (document.fullscreenElement) void document.exitFullscreen()
    else void el.requestFullscreen?.()
  }
  useEffect(() => {
    const f = () => setPantallaCompleta(Boolean(document.fullscreenElement))
    document.addEventListener('fullscreenchange', f)
    return () => document.removeEventListener('fullscreenchange', f)
  }, [])
  const puedePantallaCompleta = typeof document !== 'undefined' && Boolean(document.fullscreenEnabled)

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); ir(1) }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); ir(-1) }
    else if (carga.estado === 'listo' && carga.tipo === 'imagen') {
      if (e.key === '+' || e.key === '=') zoom(PASO)
      else if (e.key === '-') zoom(1 / PASO)
      else if (e.key === 'r' || e.key === 'R') rotar()
      else if (e.key === '0') reiniciar()
    }
  }

  // ---- pan (1 puntero) y pinch (2 punteros) -----------------------------------------------
  const punteros = useRef(new Map<number, { x: number; y: number }>())
  const gesto = useRef<
    | { tipo: 'pan'; x0: number; y0: number; tx: number; ty: number }
    | { tipo: 'pinch'; d0: number; e0: number }
    | null
  >(null)

  const distancia = () => {
    const [a, b] = [...punteros.current.values()]
    return Math.hypot(a.x - b.x, a.y - b.y)
  }
  const iniciarGesto = () => {
    const ps = [...punteros.current.values()]
    if (ps.length === 1) gesto.current = { tipo: 'pan', x0: ps[0].x, y0: ps[0].y, tx: t.x, ty: t.y }
    else if (ps.length === 2) gesto.current = { tipo: 'pinch', d0: distancia(), e0: t.escala }
    else gesto.current = null
  }
  const onPointerDown = (e: PointerEvent) => {
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    punteros.current.set(e.pointerId, { x: e.clientX, y: e.clientY })
    iniciarGesto()
  }
  const onPointerMove = (e: PointerEvent) => {
    if (!punteros.current.has(e.pointerId)) return
    punteros.current.set(e.pointerId, { x: e.clientX, y: e.clientY })
    const g = gesto.current
    if (!g) return
    if (g.tipo === 'pan') setT((s) => ({ ...s, x: g.tx + (e.clientX - g.x0), y: g.ty + (e.clientY - g.y0) }))
    else if (punteros.current.size === 2 && g.d0 > 0) {
      const d = distancia()
      setT((s) => ({ ...s, escala: limitar(g.e0 * (d / g.d0)) }))
    }
  }
  const onPointerUp = (e: PointerEvent) => {
    punteros.current.delete(e.pointerId)
    iniciarGesto() // al soltar uno de dos dedos, el que queda sigue paneando sin salto
  }

  // `onWheel` de React es pasivo: no puede frenar el scroll de la página. Listener nativo.
  useEffect(() => {
    const el = lienzo.current
    if (!el) return
    const f = (e: WheelEvent) => {
      e.preventDefault()
      setT((s) => ({ ...s, escala: limitar(s.escala * (e.deltaY < 0 ? 1.1 : 1 / 1.1)) }))
    }
    el.addEventListener('wheel', f, { passive: false })
    return () => el.removeEventListener('wheel', f)
  }, [carga.estado])

  const esImagen = carga.estado === 'listo' && carga.tipo === 'imagen'
  const boton = 'inline-flex h-9 w-9 items-center justify-center rounded-md text-white/90 hover:bg-white/10 disabled:opacity-30 disabled:hover:bg-transparent'

  return (
    <Dialog open onOpenChange={(abierto) => { if (!abierto) onCerrar() }}>
      <DialogPortal>
        <DialogOverlay className="bg-black/90" />
        <DialogPrimitive.Content
          ref={contenedor}
          onKeyDown={onKeyDown}
          aria-describedby={undefined}
          className="fixed inset-0 z-50 flex flex-col bg-black/95 text-white outline-none"
        >
          <DialogPrimitive.Title className="sr-only">Visor de archivo: {nombre}</DialogPrimitive.Title>

          {/* Barra superior */}
          <div className="flex items-center gap-1 border-b border-white/10 px-2 py-1.5 sm:px-3">
            <div className="min-w-0 flex-1 truncate text-sm" title={nombre}>
              {nombre}
              {hayVarios && <span className="ml-2 text-white/50">{indice + 1} / {archivos.length}</span>}
            </div>
            <button type="button" className={boton} onClick={() => zoom(1 / PASO)} disabled={!esImagen} aria-label="Alejar"><ZoomOut size={18} /></button>
            <span className="hidden w-12 text-center text-xs tabular-nums text-white/70 sm:inline">
              {esImagen ? `${Math.round(t.escala * 100)}%` : ''}
            </span>
            <button type="button" className={boton} onClick={() => zoom(PASO)} disabled={!esImagen} aria-label="Acercar"><ZoomIn size={18} /></button>
            <button type="button" className={boton} onClick={rotar} disabled={!esImagen} aria-label="Rotar"><RotateCw size={18} /></button>
            <button type="button" className={`${boton} hidden sm:inline-flex`} onClick={reiniciar} disabled={!esImagen} aria-label="Restablecer vista">
              <span className="text-xs">1:1</span>
            </button>
            {puedePantallaCompleta && (
              <button type="button" className={boton} onClick={alternarPantallaCompleta}
                aria-label={pantallaCompleta ? 'Salir de pantalla completa' : 'Pantalla completa'}>
                {pantallaCompleta ? <Minimize size={18} /> : <Maximize size={18} />}
              </button>
            )}
            <button type="button" className={boton} onClick={descargar} aria-label="Descargar"><Download size={18} /></button>
            <DialogPrimitive.Close className={boton} aria-label="Cerrar visor"><X size={20} /></DialogPrimitive.Close>
          </div>

          {/* Lienzo */}
          <div ref={lienzo} className="relative flex flex-1 items-center justify-center overflow-hidden">
            {carga.estado === 'cargando' && (
              <div role="status" className="flex flex-col items-center gap-2 text-white/70">
                <Loader2 className="h-8 w-8 animate-spin" />
                <span className="text-sm">Cargando archivo…</span>
              </div>
            )}

            {carga.estado === 'error' && (
              <div role="alert" className="mx-4 flex max-w-sm flex-col items-center gap-3 rounded-lg bg-white/5 p-6 text-center">
                <AlertTriangle className="h-8 w-8 text-amber-400" />
                <p className="text-sm">{MENSAJE_FALLA[carga.motivo]}</p>
                {carga.motivo !== 'sin_acceso' && (
                  <button type="button" onClick={() => setReintento((n) => n + 1)}
                    className="inline-flex items-center gap-2 rounded-md bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20">
                    <RefreshCw size={14} /> Reintentar
                  </button>
                )}
              </div>
            )}

            {carga.estado === 'listo' && carga.tipo === 'imagen' && (
              <div
                className="h-full w-full touch-none select-none"
                style={{ cursor: gesto.current?.tipo === 'pan' ? 'grabbing' : 'grab' }}
                onPointerDown={onPointerDown}
                onPointerMove={onPointerMove}
                onPointerUp={onPointerUp}
                onPointerCancel={onPointerUp}
                onDoubleClick={() => setT((s) => (s.escala === 1 ? { ...s, escala: 2 } : INICIAL))}
              >
                <div className="flex h-full w-full items-center justify-center">
                  <img
                    src={carga.url}
                    alt={nombre}
                    draggable={false}
                    onError={() => setCarga({ estado: 'error', motivo: 'desconocido' })}
                    className="max-h-full max-w-full object-contain"
                    style={{ transform: `translate(${t.x}px, ${t.y}px) scale(${t.escala}) rotate(${t.rot}deg)`, transition: gesto.current ? 'none' : 'transform 80ms ease-out' }}
                  />
                </div>
              </div>
            )}

            {carga.estado === 'listo' && carga.tipo === 'pdf' && !esIOS() && (
              <iframe src={carga.url} title={nombre} className="h-full w-full border-0 bg-white" />
            )}

            {carga.estado === 'listo' && (carga.tipo === 'otro' || (carga.tipo === 'pdf' && esIOS())) && (
              <div className="mx-4 flex max-w-sm flex-col items-center gap-3 rounded-lg bg-white/5 p-6 text-center">
                <FileText className="h-10 w-10 text-white/70" />
                <p className="text-sm">
                  {carga.tipo === 'pdf'
                    ? 'Este dispositivo no muestra PDFs completos dentro de la app.'
                    : 'Este tipo de archivo no se puede previsualizar.'}
                </p>
                <div className="flex gap-2">
                  {carga.tipo === 'pdf' && (
                    <button type="button" onClick={() => window.open(carga.url, '_blank', 'noopener')}
                      className="inline-flex items-center gap-2 rounded-md bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20">
                      <ExternalLink size={14} /> Abrir
                    </button>
                  )}
                  <button type="button" onClick={descargar}
                    className="inline-flex items-center gap-2 rounded-md bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20">
                    <Download size={14} /> Descargar
                  </button>
                </div>
              </div>
            )}

            {hayVarios && (
              <>
                <button type="button" onClick={() => ir(-1)} aria-label="Archivo anterior"
                  className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 hover:bg-black/70">
                  <ChevronLeft size={24} />
                </button>
                <button type="button" onClick={() => ir(1)} aria-label="Archivo siguiente"
                  className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 hover:bg-black/70">
                  <ChevronRight size={24} />
                </button>
              </>
            )}
          </div>
        </DialogPrimitive.Content>
      </DialogPortal>
    </Dialog>
  )
}
