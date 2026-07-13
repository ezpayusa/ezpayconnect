import { useState, useRef, useCallback, useEffect } from 'react'
import { AlertTriangle, Loader2, ShieldOff } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { useConsentimientoGate } from '@/hooks/useConsentimientoGate'

interface DictadoVozProps {
  onTranscript: (text: string) => void
  pacienteId: number
  placeholder?: string
  className?: string
}

export default function DictadoVoz({ onTranscript, pacienteId, placeholder = 'Dicta tu nota aqui...', className = '' }: DictadoVozProps) {
  // Gate UX (no es la barrera real — esa la aplica el edge): evita el intento si está revocado.
  const { permitido, error: errorConsent, recargar } = useConsentimientoGate(pacienteId)
  const grabacionBloqueada = !permitido('grabacion_consulta')
  const [estado, setEstado] = useState<'idle' | 'grabando' | 'procesando'>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [tiempoGrabacion, setTiempoGrabacion] = useState(0)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const chunksRef = useRef<Blob[]>([])
  const streamRef = useRef<MediaStream | null>(null)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current)
      if (streamRef.current) streamRef.current.getTracks().forEach(t => t.stop())
    }
  }, [])

  const detenerGrabacion = useCallback(() => {
    console.log('[DictadoVoz] detenerGrabacion llamado')
    if (timerRef.current) {
      clearInterval(timerRef.current)
      timerRef.current = null
    }
    if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
      try { mediaRecorderRef.current.stop() } catch (e) { console.log('stop error:', e) }
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(t => t.stop())
      streamRef.current = null
    }
    setEstado('idle')
    setTiempoGrabacion(0)
  }, [])

  const enviarAudio = useCallback(async (audioBlob: Blob) => {
    console.log('[DictadoVoz] enviarAudio, tamaño:', audioBlob.size)
    setEstado('procesando')
    setErrorMsg('')
    try {
      const formData = new FormData()
      formData.append('audio', audioBlob, 'audio.webm')
      formData.append('paciente_id', String(pacienteId))

      const { data, error } = await supabase.functions.invoke('dictado-voz', {
        body: formData,
      })

      if (error) throw error
      if (data?.error) throw new Error(data.error)

      const texto = data?.texto || ''
      if (texto) {
        onTranscript(texto)
        toast.success('Dictado transcrito')
      } else {
        toast.warning('No se detectó texto en el audio')
      }
    } catch (e: any) {
      console.error('Error transcribiendo:', e)
      const msg = e.message || 'Error al transcribir el audio'
      setErrorMsg(msg)
      toast.error(msg)
    } finally {
      setEstado('idle')
      setTiempoGrabacion(0)
    }
  }, [onTranscript, pacienteId])

  const iniciarGrabacion = useCallback(async () => {
    console.log('[DictadoVoz] iniciarGrabacion')
    setErrorMsg('')
    chunksRef.current = []

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      streamRef.current = stream

      const mimeType = MediaRecorder.isTypeSupported('audio/webm')
        ? 'audio/webm'
        : MediaRecorder.isTypeSupported('audio/mp4')
          ? 'audio/mp4'
          : 'audio/ogg'

      const mediaRecorder = new MediaRecorder(stream, { mimeType })
      mediaRecorderRef.current = mediaRecorder

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data)
      }

      mediaRecorder.onstop = () => {
        console.log('[DictadoVoz] onstop')
        const audioBlob = new Blob(chunksRef.current, { type: mimeType })
        stream.getTracks().forEach(t => t.stop())
        streamRef.current = null
        if (audioBlob.size > 100) {
          enviarAudio(audioBlob)
        } else {
          setErrorMsg('El audio es muy corto. Intenta de nuevo hablando más.')
          setEstado('idle')
          setTiempoGrabacion(0)
        }
      }

      mediaRecorder.onerror = () => {
        setErrorMsg('Error al grabar audio.')
        detenerGrabacion()
      }

      mediaRecorder.start(100)
      setEstado('grabando')

      let segundos = 0
      timerRef.current = setInterval(() => {
        segundos++
        setTiempoGrabacion(segundos)
        if (segundos >= 120) detenerGrabacion()
      }, 1000)

    } catch (err: any) {
      console.error('Error iniciando:', err)
      if (err.name === 'NotAllowedError') {
        setErrorMsg('Permiso de micrófono denegado. Actívalo en la barra de direcciones (🔒).')
      } else if (err.name === 'NotFoundError') {
        setErrorMsg('No se encontró micrófono.')
      } else {
        setErrorMsg('No se pudo acceder al micrófono.')
      }
      setEstado('idle')
    }
  }, [enviarAudio, detenerGrabacion])

  const formatearTiempo = (s: number) => {
    const m = Math.floor(s / 60)
    const seg = s % 60
    return `${m}:${seg.toString().padStart(2, '0')}`
  }

  console.log('[DictadoVoz] render estado:', estado)

  return (
    <div className={`flex flex-col gap-2 ${className}`}>
      {/* IDLE */}
      {estado === 'idle' && (
        errorConsent ? (
          <div className="inline-flex items-center gap-2 rounded-md border border-red-200 bg-red-50 px-2 py-1.5 w-fit">
            <span className="inline-flex items-center gap-2 text-sm text-red-700">
              <AlertTriangle className="h-3.5 w-3.5 shrink-0" /> No se pudo verificar el consentimiento de grabación
            </span>
            <Button variant="outline" size="sm" onClick={() => recargar()}>Reintentar</Button>
          </div>
        ) : grabacionBloqueada ? (
          <div className="inline-flex items-center gap-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1.5 w-fit">
            <ShieldOff className="h-3.5 w-3.5 shrink-0" />
            El paciente revocó la grabación. Captúrala en Consentimiento.
          </div>
        ) : (
          <button
            type="button"
            onClick={iniciarGrabacion}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium border border-gray-300 rounded-md bg-white hover:bg-gray-50 text-gray-700 w-fit"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/></svg>
            Dictar
          </button>
        )
      )}

      {/* GRABANDO */}
      {estado === 'grabando' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={detenerGrabacion}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md bg-red-600 hover:bg-red-700 text-white border border-red-700"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
              Detener grabación
            </button>
            <span className="text-sm font-mono text-red-600 font-bold">
              {formatearTiempo(tiempoGrabacion)}
            </span>
          </div>
          <div className="flex items-center gap-2 text-xs text-red-600">
            <span className="w-2.5 h-2.5 bg-red-500 rounded-full animate-pulse inline-block" />
            Grabando audio... habla ahora y luego presiona el botón rojo de arriba
          </div>
        </div>
      )}

      {/* PROCESANDO */}
      {estado === 'procesando' && (
        <div className="flex items-center gap-2 text-sm text-blue-600 bg-blue-50 p-2 rounded border border-blue-200">
          <Loader2 className="h-4 w-4 animate-spin" />
          Enviando a Whisper para transcribir...
        </div>
      )}

      {/* ERROR */}
      {errorMsg && (
        <div className="text-xs text-red-600 bg-red-50 p-2 rounded flex items-start gap-1.5 border border-red-200">
          <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
          {errorMsg}
        </div>
      )}

      {/* PLACEHOLDER */}
      {estado === 'idle' && !errorMsg && (
        <p className="text-xs text-muted-foreground">{placeholder}</p>
      )}
    </div>
  )
}
