import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import { useFotoPaciente } from '@/hooks/useFotoPaciente'
import { useConsentimientoGate } from '@/hooks/useConsentimientoGate'
import { Button } from '@/components/ui/button'
import { User, Camera, Loader2, ShieldOff, AlertTriangle } from 'lucide-react'

/**
 * Avatar circular de la foto del paciente (bucket privado → signed URL).
 * Si editable, muestra un botón cámara que sube/reemplaza (input file capture).
 * Re-firma la URL al montar/cambiar fotoPath (TTL 120 s, suficiente para la vista).
 */
export function FotoPacienteAvatar({
  pacienteId,
  fotoPath,
  editable = false,
  size = 'sm',
  onUpdated,
}: {
  pacienteId: number
  fotoPath: string | null
  editable?: boolean
  size?: 'sm' | 'lg'
  onUpdated?: (nuevoPath: string) => void
}) {
  const { subirFoto, urlFirmadaFoto, subiendo } = useFotoPaciente()
  // Gate de consentimiento solo cuando editable (con undefined el hook no dispara RPC). Grandfather: solo
  // bloquea si foto_perfil está revocado (concedido=false vigente); sin fila o concedido=true → permite.
  const { permitido, error: errorConsent, recargar } = useConsentimientoGate(editable ? pacienteId : undefined)
  const fotoBloqueada = editable && !permitido('foto_perfil')
  const [src, setSrc] = useState<string | null>(null)
  const [pathActual, setPathActual] = useState<string | null>(fotoPath)
  const [bust, setBust] = useState(0) // fuerza re-firma + remonte del <img> tras subir (mismo path = mismo perfil.jpg)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { setPathActual(fotoPath) }, [fotoPath])

  useEffect(() => {
    let vivo = true
    urlFirmadaFoto(pathActual).then((u) => { if (vivo) setSrc(u) })
    return () => { vivo = false }
  }, [pathActual, bust, urlFirmadaFoto])

  const dim = size === 'lg' ? 'h-24 w-24' : 'h-16 w-16'
  const iconSize = size === 'lg' ? 'h-10 w-10' : 'h-7 w-7'

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    const nuevo = await subirFoto(pacienteId, file)
    if (nuevo) { setPathActual(nuevo); onUpdated?.(nuevo); setBust(Date.now()) }
  }

  return (
    <div className="flex flex-col items-start gap-1 shrink-0">
      <div className={`relative ${dim}`}>
        <div className={`${dim} rounded-full overflow-hidden bg-slate-100 flex items-center justify-center border`}>
          {src ? (
            <img key={`${pathActual}-${bust}`} src={src} alt="Foto del paciente" className="h-full w-full object-cover" />
          ) : (
            <User className={`${iconSize} text-slate-400`} />
          )}
        </div>
        {/* Control de subida: solo si editable, NO bloqueado por consentimiento revocado y sin error de verificación. */}
        {editable && !fotoBloqueada && !errorConsent && (
          <>
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              disabled={subiendo}
              aria-label="Subir o reemplazar foto"
              className="absolute -bottom-1 -right-1 h-7 w-7 rounded-full bg-[#1E5C8E] text-white flex items-center justify-center shadow hover:bg-[#164a70] disabled:opacity-60"
            >
              {subiendo ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
            </button>
            <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={onFile} />
          </>
        )}
        {/* Bloqueado: badge ShieldOff en lugar del botón (el avatar sigue mostrando la foto si la hay). */}
        {fotoBloqueada && (
          <span
            className="absolute -bottom-1 -right-1 h-7 w-7 rounded-full bg-amber-100 text-amber-600 flex items-center justify-center border border-amber-200"
            aria-label="Subida bloqueada por consentimiento revocado"
          >
            <ShieldOff className="h-4 w-4" />
          </span>
        )}
      </div>
      {fotoBloqueada && (
        <p className="text-[11px] leading-tight text-amber-700 max-w-[12rem]">
          El paciente revocó la autorización de foto. Captúrala de nuevo en la sección Consentimiento.
        </p>
      )}
      {/* FAIL-CLOSED: si no se pudo verificar el consentimiento, NO se ofrece subir; alerta + reintentar. */}
      {editable && errorConsent && (
        <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 p-2 max-w-[14rem]">
          <span className="flex items-center gap-1 text-[11px] leading-tight text-red-700">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0" /> No se pudo verificar el consentimiento de foto
          </span>
          <Button variant="outline" size="sm" onClick={() => recargar()}>Reintentar</Button>
        </div>
      )}
    </div>
  )
}
