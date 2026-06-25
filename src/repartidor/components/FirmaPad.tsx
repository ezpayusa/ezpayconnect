import { useRef, useState, useEffect, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Eraser, X } from 'lucide-react'

interface FirmaPadProps {
  onSave: (blob: Blob) => void
  onCancel?: () => void
  saving?: boolean
  folio?: string
}

const EXPORT_MAX_W = 600 // PNG de firma acotado (~10–20 KB), no escala con el DPR de la pantalla

// Pad de firma FULLSCREEN sobre <canvas> con POINTER events (cubre touch + mouse + stylus). Maneja
// devicePixelRatio para que el trazo no salga borroso/escalado en pantallas retina.
export default function FirmaPad({ onSave, onCancel, saving, folio }: FirmaPadProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const drawing = useRef(false)
  const [vacio, setVacio] = useState(true)

  // Dimensionar el backing-store al tamaño CSS * DPR (cap 2) y escalar el contexto:
  // así dibujamos en coordenadas CSS y el trazo queda nítido. Se mide tras el layout fullscreen.
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const rect = canvas.getBoundingClientRect()
    canvas.width = Math.round(rect.width * dpr)
    canvas.height = Math.round(rect.height * dpr)
    const ctx = canvas.getContext('2d')
    if (ctx) {
      ctx.scale(dpr, dpr)
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.lineWidth = 2.5
      ctx.strokeStyle = '#111827'
    }
  }, [])

  // Coordenadas en px CSS (el contexto ya está escalado por DPR).
  const pos = (e: React.PointerEvent<HTMLCanvasElement>): [number, number] => {
    const rect = canvasRef.current!.getBoundingClientRect()
    return [e.clientX - rect.left, e.clientY - rect.top]
  }

  const start = (e: React.PointerEvent<HTMLCanvasElement>) => {
    e.preventDefault()
    const ctx = canvasRef.current?.getContext('2d')
    if (!ctx) return
    drawing.current = true
    setVacio(false)
    const [x, y] = pos(e)
    ctx.beginPath()
    ctx.moveTo(x, y)
    canvasRef.current?.setPointerCapture(e.pointerId)
  }

  const move = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawing.current) return
    const ctx = canvasRef.current?.getContext('2d')
    if (!ctx) return
    const [x, y] = pos(e)
    ctx.lineTo(x, y)
    ctx.stroke()
  }

  const end = () => {
    drawing.current = false
  }

  const limpiar = useCallback(() => {
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    if (canvas && ctx) ctx.clearRect(0, 0, canvas.width, canvas.height)
    setVacio(true)
  }, [])

  // Exportar a una resolución ACOTADA (no la del backing-store retina) → PNG liviano.
  const guardar = useCallback(() => {
    const src = canvasRef.current
    if (!src) return
    const scale = Math.min(1, EXPORT_MAX_W / src.width)
    const out = document.createElement('canvas')
    out.width = Math.max(1, Math.round(src.width * scale))
    out.height = Math.max(1, Math.round(src.height * scale))
    const ctx = out.getContext('2d')
    if (!ctx) return
    ctx.drawImage(src, 0, 0, out.width, out.height)
    out.toBlob((blob) => {
      if (blob) onSave(blob)
    }, 'image/png')
  }, [onSave])

  return (
    <div className="fixed inset-0 z-40 bg-white flex flex-col">
      <header className="flex items-center gap-2 px-4 py-3 border-b border-gray-100">
        <div className="min-w-0">
          <p className="font-semibold text-gray-800">Firma del paciente</p>
          {folio && <p className="text-xs text-gray-400">#{folio}</p>}
        </div>
        {onCancel && (
          <button type="button" onClick={onCancel} disabled={saving} aria-label="Cerrar" className="ml-auto rounded-full p-2 text-gray-400 active:bg-gray-100">
            <X className="h-5 w-5" />
          </button>
        )}
      </header>

      <div className="relative flex-1 m-4 rounded-2xl border-2 border-dashed border-gray-200">
        <canvas
          ref={canvasRef}
          onPointerDown={start}
          onPointerMove={move}
          onPointerUp={end}
          onPointerLeave={end}
          onPointerCancel={end}
          className="absolute inset-0 w-full h-full touch-none"
        />
        {vacio && (
          <div className="absolute inset-0 grid place-items-center pointer-events-none">
            <p className="text-sm text-gray-300">Firmá dentro del recuadro</p>
          </div>
        )}
      </div>

      <div className="flex gap-2 p-4 border-t border-gray-100">
        <Button type="button" variant="outline" onClick={limpiar} className="flex-1" disabled={saving}>
          <Eraser className="h-4 w-4 mr-1" /> Borrar
        </Button>
        <Button type="button" onClick={guardar} disabled={vacio || saving} className="flex-1">
          {saving ? 'Guardando…' : 'Confirmar firma'}
        </Button>
      </div>
    </div>
  )
}
