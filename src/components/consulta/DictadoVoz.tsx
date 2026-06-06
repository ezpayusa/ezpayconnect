import { useState, useRef, useCallback, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Mic, MicOff } from 'lucide-react'

interface DictadoVozProps {
  onTranscript: (text: string) => void
  placeholder?: string
  className?: string
}

// Web Speech API types
interface SpeechRecognitionEvent extends Event {
  results: SpeechRecognitionResultList
}

interface SpeechRecognitionErrorEvent extends Event {
  error: string
}

interface SpeechRecognition extends EventTarget {
  lang: string
  continuous: boolean
  interimResults: boolean
  maxAlternatives: number
  start(): void
  stop(): void
  abort(): void
  onresult: ((event: SpeechRecognitionEvent) => void) | null
  onerror: ((event: SpeechRecognitionErrorEvent) => void) | null
  onend: (() => void) | null
}

declare global {
  interface Window {
    webkitSpeechRecognition: new () => SpeechRecognition
    SpeechRecognition: new () => SpeechRecognition
  }
}

export default function DictadoVoz({ onTranscript, placeholder = 'Dicta tu nota aqui...', className = '' }: DictadoVozProps) {
  const [grabando, setGrabando] = useState(false)
  const [transcripcion, setTranscripcion] = useState('')
  const [interim, setInterim] = useState('')
  const [soportado, setSoportado] = useState(true)
  const recognitionRef = useRef<SpeechRecognition | null>(null)

  useEffect(() => {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SpeechRecognition) {
      setSoportado(false)
      return
    }

    const recognition = new SpeechRecognition()
    recognition.lang = 'es-ES'
    recognition.continuous = true
    recognition.interimResults = true
    recognition.maxAlternatives = 1

    recognition.onresult = (event: SpeechRecognitionEvent) => {
      let finalTranscript = ''
      let interimTranscript = ''

      for (let i = event.results.length - 1; i >= 0; i--) {
        const result = event.results[i]
        if (result.isFinal) {
          finalTranscript = result[0].transcript + ' ' + finalTranscript
        } else {
          interimTranscript = result[0].transcript
        }
      }

      if (finalTranscript) {
        setTranscripcion(prev => {
          const nuevo = prev + finalTranscript
          onTranscript(nuevo)
          return nuevo
        })
      }
      setInterim(interimTranscript)
    }

    recognition.onerror = (event: SpeechRecognitionErrorEvent) => {
      if (event.error === 'no-speech') return
      console.error('Speech recognition error:', event.error)
      setGrabando(false)
    }

    recognition.onend = () => {
      if (grabando) {
        try { recognition.start() } catch {}
      }
    }

    recognitionRef.current = recognition

    return () => {
      recognition.abort()
    }
  }, [onTranscript, grabando])

  const toggleGrabacion = useCallback(() => {
    if (!recognitionRef.current) return

    if (grabando) {
      recognitionRef.current.stop()
      setGrabando(false)
      setInterim('')
    } else {
      setTranscripcion('')
      setInterim('')
      recognitionRef.current.start()
      setGrabando(true)
    }
  }, [grabando])

  if (!soportado) {
    return (
      <div className={`text-xs text-amber-600 bg-amber-50 p-2 rounded ${className}`}>
        Tu navegador no soporta dictado por voz. Usa Chrome o Edge.
      </div>
    )
  }

  return (
    <div className={`flex flex-col gap-2 ${className}`}>
      <div className="flex items-center gap-2">
        <Button
          type="button"
          variant={grabando ? 'destructive' : 'outline'}
          size="sm"
          onClick={toggleGrabacion}
          className={grabando ? 'animate-pulse' : ''}
        >
          {grabando ? (
            <>
              <MicOff className="h-4 w-4 mr-1" /> Detener
            </>
          ) : (
            <>
              <Mic className="h-4 w-4 mr-1" /> Dictar
            </>
          )}
        </Button>
        {grabando && (
          <span className="text-xs text-red-500 animate-pulse flex items-center gap-1">
            <span className="w-2 h-2 bg-red-500 rounded-full inline-block" />
            Escuchando...
          </span>
        )}
      </div>
      {(transcripcion || interim) && (
        <div className="bg-slate-50 p-3 rounded-lg border text-sm min-h-[60px]">
          <p className="text-slate-700">{transcripcion}<span className="text-slate-400 italic">{interim}</span></p>
        </div>
      )}
      {!transcripcion && !interim && !grabando && (
        <p className="text-xs text-muted-foreground">{placeholder}</p>
      )}
    </div>
  )
}
