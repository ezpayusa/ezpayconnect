import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import { useFotoPaciente } from '@/hooks/useFotoPaciente'
import { User, Camera, Loader2 } from 'lucide-react'

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
  const [src, setSrc] = useState<string | null>(null)
  const [pathActual, setPathActual] = useState<string | null>(fotoPath)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { setPathActual(fotoPath) }, [fotoPath])

  useEffect(() => {
    let vivo = true
    urlFirmadaFoto(pathActual).then((u) => { if (vivo) setSrc(u) })
    return () => { vivo = false }
  }, [pathActual, urlFirmadaFoto])

  const dim = size === 'lg' ? 'h-24 w-24' : 'h-16 w-16'
  const iconSize = size === 'lg' ? 'h-10 w-10' : 'h-7 w-7'

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    const nuevo = await subirFoto(pacienteId, file)
    if (nuevo) { setPathActual(nuevo); onUpdated?.(nuevo) }
  }

  return (
    <div className={`relative ${dim} shrink-0`}>
      <div className={`${dim} rounded-full overflow-hidden bg-slate-100 flex items-center justify-center border`}>
        {src ? (
          <img src={src} alt="Foto del paciente" className="h-full w-full object-cover" />
        ) : (
          <User className={`${iconSize} text-slate-400`} />
        )}
      </div>
      {editable && (
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
    </div>
  )
}
