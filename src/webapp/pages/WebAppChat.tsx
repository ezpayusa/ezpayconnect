import { useState, useRef, useEffect } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppChat } from '@/webapp/hooks/useWebAppChat'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  MessageCircle, Send, User, Stethoscope, Loader2, AlertCircle
} from 'lucide-react'

export default function WebAppChat() {
  const { perfil } = useWebAppAuth()
  const {
    mensajes,
    medicoId,
    medicoNombre,
    loading,
    error,
    enviando,
    enviarMensaje,
  } = useWebAppChat(perfil?.id)

  const [texto, setTexto] = useState('')
  const scrollRef = useRef<HTMLDivElement>(null)

  // Auto-scroll al último mensaje
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [mensajes])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!texto.trim() || enviando) return
    await enviarMensaje(texto)
    setTexto('')
  }

  const formatearFecha = (fecha: string) => {
    return new Date(fecha).toLocaleTimeString('es-GT', {
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  return (
    <div className="space-y-4 h-[calc(100vh-120px)] flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between shrink-0">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Chat con mi Médico</h1>
          <p className="text-slate-500 mt-1">
            {medicoId ? (() => { const n = medicoNombre || ''; return /^Dr\.?\s|^Dra\.?\s/i.test(n) ? n : `Dr. ${n}` })() : 'Buscando médico asignado...'}
          </p>
        </div>
        <div className="w-10 h-10 rounded-full bg-sky-50 flex items-center justify-center">
          <MessageCircle className="h-5 w-5 text-sky-500" />
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-3 text-red-700 text-sm flex items-center gap-2 shrink-0">
          <AlertCircle className="h-4 w-4" />
          {error}
        </div>
      )}

      {/* Chat */}
      {!loading && (
        <>
          {/* Mensajes */}
          <div
            ref={scrollRef}
            className="flex-1 overflow-y-auto space-y-3 pr-1"
          >
            {loading && mensajes.length === 0 && (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-8 w-8 animate-spin text-sky-500" />
              </div>
            )}

            {mensajes.length === 0 && !loading && (
              <div className="text-center py-12">
                <MessageCircle className="h-12 w-12 text-slate-300 mx-auto mb-3" />
                <p className="text-slate-500">Aún no hay mensajes</p>
                <p className="text-sm text-slate-400">
                  Envía un mensaje para iniciar la conversación
                </p>
              </div>
            )}

            {mensajes.map((msg) => {
              const esPaciente = msg.remitente === 'paciente'
              return (
                <div
                  key={msg.id}
                  className={`flex ${esPaciente ? 'justify-end' : 'justify-start'}`}
                >
                  <div
                    className={`max-w-[80%] rounded-2xl px-4 py-2.5 ${
                      esPaciente
                        ? 'bg-sky-500 text-white rounded-br-md'
                        : 'bg-slate-100 text-slate-700 rounded-bl-md'
                    }`}
                  >
                    <p className="text-sm leading-relaxed">{msg.mensaje}</p>
                    <p
                      className={`text-xs mt-1 ${
                        esPaciente ? 'text-sky-100' : 'text-slate-400'
                      }`}
                    >
                      {formatearFecha(msg.created_at)}
                      {esPaciente && (
                        <span className="ml-1">
                          {msg.leido ? '· Leído' : '· Enviado'}
                        </span>
                      )}
                    </p>
                  </div>
                </div>
              )
            })}
          </div>

          {/* Input */}
          <form
            onSubmit={handleSubmit}
            className="flex gap-2 shrink-0 bg-white p-2 rounded-xl border border-slate-200"
          >
            <Input
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              placeholder="Escribe un mensaje..."
              className="border-0 focus-visible:ring-0 bg-transparent"
              disabled={enviando}
            />
            <Button
              type="submit"
              size="icon"
              className="bg-sky-500 hover:bg-sky-600 shrink-0"
              disabled={!texto.trim() || enviando}
            >
              {enviando ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Send className="h-4 w-4" />
              )}
            </Button>
          </form>
        </>
      )}
    </div>
  )
}
