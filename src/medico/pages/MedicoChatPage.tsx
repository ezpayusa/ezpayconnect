import { useState, useEffect, useRef, useMemo } from 'react'
import { useMedicoChat, type HiloChat } from '@/medico/hooks/useMedicoChat'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Avatar, AvatarImage, AvatarFallback } from '@/components/ui/avatar'
import { MessageCircle, Send, ArrowLeft, Loader2, RefreshCw, AlertCircle } from 'lucide-react'

function iniciales(nombre?: string, apellido?: string) {
  return `${(nombre?.[0] ?? '').toUpperCase()}${(apellido?.[0] ?? '').toUpperCase()}` || '?'
}

function horaCorta(iso: string) {
  const d = new Date(iso)
  return d.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' })
}

function fechaHora(iso: string) {
  const d = new Date(iso)
  return d.toLocaleString('es', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}

export default function MedicoChatPage() {
  const {
    hilos, loadingHilos, errorHilos,
    hiloActivo, setHiloActivo,
    mensajes, loadingMensajes, enviando, error,
    enviarMensaje, refetchHilos,
  } = useMedicoChat()

  const [texto, setTexto] = useState('')
  const finRef = useRef<HTMLDivElement | null>(null)

  const hiloSel: HiloChat | undefined = useMemo(
    () => hilos.find((h) => h.paciente_id === hiloActivo),
    [hilos, hiloActivo]
  )

  // scroll al fondo al cargar / llegar mensaje nuevo
  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [mensajes])

  const handleEnviar = async () => {
    const t = texto.trim()
    if (!t || enviando) return
    setTexto('')
    await enviarMensaje(t)
  }

  return (
    <div className="p-4 md:p-6">
      <div className="flex items-center gap-2 mb-4">
        <MessageCircle className="h-6 w-6 text-[#5BA8D1]" />
        <h1 className="text-2xl font-bold">Mensajes</h1>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-[320px_1fr] gap-4 h-[calc(100vh-160px)]">
        {/* ── Panel izquierdo: lista de hilos ── */}
        <Card className={`overflow-hidden flex flex-col ${hiloActivo != null ? 'hidden md:flex' : 'flex'}`}>
          <div className="flex items-center justify-between px-4 py-3 border-b">
            <span className="font-semibold text-sm">Conversaciones</span>
            <Button variant="ghost" size="icon" onClick={() => refetchHilos()} title="Actualizar">
              <RefreshCw className="h-4 w-4" />
            </Button>
          </div>

          <div className="flex-1 overflow-y-auto">
            {loadingHilos ? (
              <div className="flex items-center justify-center py-10 text-muted-foreground">
                <Loader2 className="h-5 w-5 animate-spin" />
              </div>
            ) : errorHilos ? (
              <div className="p-4 text-sm text-red-600 flex flex-col items-center gap-2">
                <AlertCircle className="h-5 w-5" />
                <p className="text-center">{errorHilos}</p>
                <Button variant="outline" size="sm" onClick={() => refetchHilos()}>Reintentar</Button>
              </div>
            ) : hilos.length === 0 ? (
              <div className="p-6 text-sm text-muted-foreground text-center">
                Aún no tienes conversaciones. Los pacientes con cita o asignados pueden escribirte.
              </div>
            ) : (
              hilos.map((h) => (
                <button
                  key={h.paciente_id}
                  onClick={() => setHiloActivo(h.paciente_id)}
                  className={`w-full flex items-center gap-3 px-4 py-3 border-b text-left hover:bg-muted/50 transition-colors ${
                    h.paciente_id === hiloActivo ? 'bg-muted' : ''
                  }`}
                >
                  <Avatar className="h-10 w-10 shrink-0">
                    {h.foto_url && <AvatarImage src={h.foto_url} alt="" />}
                    <AvatarFallback>{iniciales(h.nombre, h.apellido)}</AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-medium text-sm truncate">{h.nombre} {h.apellido}</span>
                      <span className="text-[10px] text-muted-foreground shrink-0">{horaCorta(h.ultimo_at)}</span>
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs text-muted-foreground truncate">{h.ultimo_mensaje}</span>
                      {h.no_leidos > 0 && (
                        <span className="bg-[#5BA8D1] text-white text-[10px] font-bold px-2 py-0.5 rounded-full min-w-[20px] text-center shrink-0">
                          {h.no_leidos}
                        </span>
                      )}
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        </Card>

        {/* ── Panel derecho: conversación ── */}
        <Card className={`overflow-hidden flex flex-col ${hiloActivo == null ? 'hidden md:flex' : 'flex'}`}>
          {hiloActivo == null || !hiloSel ? (
            <div className="flex-1 flex items-center justify-center text-muted-foreground text-sm">
              {hilos.length === 0 ? 'No hay conversaciones' : 'Seleccioná una conversación'}
            </div>
          ) : (
            <>
              {/* header conversación */}
              <div className="flex items-center gap-3 px-4 py-3 border-b">
                <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setHiloActivo(null)}>
                  <ArrowLeft className="h-5 w-5" />
                </Button>
                <Avatar className="h-9 w-9">
                  {hiloSel.foto_url && <AvatarImage src={hiloSel.foto_url} alt="" />}
                  <AvatarFallback>{iniciales(hiloSel.nombre, hiloSel.apellido)}</AvatarFallback>
                </Avatar>
                <span className="font-semibold text-sm">{hiloSel.nombre} {hiloSel.apellido}</span>
              </div>

              {/* mensajes */}
              <div className="flex-1 overflow-y-auto p-4 space-y-2 bg-muted/20">
                {loadingMensajes ? (
                  <div className="flex items-center justify-center py-10 text-muted-foreground">
                    <Loader2 className="h-5 w-5 animate-spin" />
                  </div>
                ) : mensajes.length === 0 ? (
                  <div className="text-center text-sm text-muted-foreground py-10">Sin mensajes todavía.</div>
                ) : (
                  mensajes.map((m) => {
                    const mio = m.remitente === 'medico'
                    return (
                      <div key={m.id} className={`flex ${mio ? 'justify-end' : 'justify-start'}`}>
                        <div
                          className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm ${
                            mio ? 'bg-[#5BA8D1] text-white rounded-br-sm' : 'bg-white border rounded-bl-sm'
                          }`}
                        >
                          <p className="whitespace-pre-wrap break-words">{m.mensaje}</p>
                          <p className={`text-[10px] mt-1 ${mio ? 'text-white/70' : 'text-muted-foreground'}`}>
                            {fechaHora(m.created_at)}
                          </p>
                        </div>
                      </div>
                    )
                  })
                )}
                <div ref={finRef} />
              </div>

              {/* input */}
              {error && (
                <div className="px-4 py-1.5 text-xs text-red-600 border-t bg-red-50">{error}</div>
              )}
              <div className="flex items-center gap-2 p-3 border-t">
                <Input
                  value={texto}
                  onChange={(e) => setTexto(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleEnviar() } }}
                  placeholder="Escribe un mensaje…"
                  disabled={enviando}
                />
                <Button onClick={handleEnviar} disabled={enviando || !texto.trim()}>
                  {enviando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </Button>
              </div>
            </>
          )}
        </Card>
      </div>
    </div>
  )
}
