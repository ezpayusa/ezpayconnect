import { useState, useEffect, useRef, useMemo } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useMisMedicosChat } from '@/webapp/hooks/useMisMedicosChat'
import { useWebAppChat } from '@/webapp/hooks/useWebAppChat'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { MessageCircle, Send, ArrowLeft, Loader2, AlertCircle, RefreshCw } from 'lucide-react'

function iniciales(nombre?: string) {
  if (!nombre) return '?'
  const parts = nombre.replace(/^Dr[a]?\.?\s*/i, '').trim().split(/\s+/)
  return ((parts[0]?.[0] ?? '') + (parts[1]?.[0] ?? '')).toUpperCase() || '?'
}

function hora(iso: string) {
  return new Date(iso).toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' })
}

export default function WebAppChat() {
  const { perfil } = useWebAppAuth()
  const pacienteId = perfil?.id

  const { medicos, loading: loadingMedicos, error: errorMedicos, refetch: refetchMedicos } = useMisMedicosChat(pacienteId)
  const [medicoSel, setMedicoSel] = useState<string | null>(null)
  const { mensajes, loading: loadingMsgs, error, enviando, enviarMensaje } = useWebAppChat(pacienteId, medicoSel)

  const [texto, setTexto] = useState('')
  const scrollRef = useRef<HTMLDivElement>(null)

  const medico = useMemo(() => medicos.find((m) => m.medico_id === medicoSel), [medicos, medicoSel])

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
  }, [mensajes])

  // Tras abrir un hilo (marca leído en la base), re-contar la bandeja para bajar el badge sin recargar.
  // refetchMedicos es estable (useCallback) → NO va en deps para evitar re-fetch infinito.
  useEffect(() => {
    if (medicoSel != null && !loadingMsgs) refetchMedicos()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [medicoSel, mensajes.length, loadingMsgs])

  const handleEnviar = async (e?: React.FormEvent) => {
    e?.preventDefault()
    const t = texto.trim()
    if (!t || enviando) return
    setTexto('')
    await enviarMensaje(t)
    // al enviar, refrescar la bandeja para actualizar último mensaje
    refetchMedicos()
  }

  return (
    <div className="p-2 md:p-0">
      <div className="flex items-center gap-2 mb-4">
        <div className="w-9 h-9 rounded-full bg-sky-50 flex items-center justify-center">
          <MessageCircle className="h-5 w-5 text-sky-500" />
        </div>
        <h1 className="text-2xl font-bold text-slate-800">Chat</h1>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-[300px_1fr] gap-4 h-[calc(100vh-170px)]">
        {/* ── Lista de médicos ── */}
        <Card className={`overflow-hidden flex flex-col ${medicoSel ? 'hidden md:flex' : 'flex'}`}>
          <div className="flex items-center justify-between px-4 py-3 border-b">
            <span className="font-semibold text-sm text-slate-700">Mis médicos</span>
            <button onClick={() => refetchMedicos()} className="text-slate-400 hover:text-slate-600" title="Actualizar">
              <RefreshCw className="h-4 w-4" />
            </button>
          </div>
          <div className="flex-1 overflow-y-auto">
            {loadingMedicos ? (
              <div className="flex items-center justify-center py-10">
                <Loader2 className="h-5 w-5 animate-spin text-sky-500" />
              </div>
            ) : errorMedicos ? (
              <div className="p-4 text-sm text-red-600 flex flex-col items-center gap-2">
                <AlertCircle className="h-5 w-5" />
                <p className="text-center">{errorMedicos}</p>
                <Button variant="outline" size="sm" onClick={() => refetchMedicos()}>Reintentar</Button>
              </div>
            ) : medicos.length === 0 ? (
              <div className="p-6 text-sm text-slate-500 text-center">
                Aún no tienes médicos asignados. Agendá una cita para poder conversar.
              </div>
            ) : (
              medicos.map((m) => (
                <button
                  key={m.medico_id}
                  onClick={() => setMedicoSel(m.medico_id)}
                  className={`w-full flex items-center gap-3 px-4 py-3 border-b text-left hover:bg-slate-50 transition-colors ${
                    m.medico_id === medicoSel ? 'bg-sky-50' : ''
                  }`}
                >
                  {m.foto_url ? (
                    <img src={m.foto_url} alt="" className="w-10 h-10 rounded-full object-cover shrink-0" />
                  ) : (
                    <div className="w-10 h-10 rounded-full bg-sky-100 text-sky-700 flex items-center justify-center text-xs font-bold shrink-0">
                      {iniciales(m.nombre_completo)}
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-medium text-sm text-slate-800 truncate">{m.nombre_completo}</span>
                      {m.ultimo_at && <span className="text-[10px] text-slate-400 shrink-0">{hora(m.ultimo_at)}</span>}
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs text-slate-500 truncate">
                        {m.ultimo_mensaje ?? (m.especialidad || 'Toca para conversar')}
                      </span>
                      {m.no_leidos > 0 && (
                        <span className="bg-sky-500 text-white text-[10px] font-bold px-2 py-0.5 rounded-full min-w-[20px] text-center shrink-0">
                          {m.no_leidos}
                        </span>
                      )}
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        </Card>

        {/* ── Conversación ── */}
        <Card className={`overflow-hidden flex flex-col ${!medicoSel ? 'hidden md:flex' : 'flex'}`}>
          {!medicoSel || !medico ? (
            <div className="flex-1 flex items-center justify-center text-slate-400 text-sm p-6 text-center">
              {medicos.length === 0 ? 'No hay conversaciones' : 'Seleccioná un médico para ver la conversación.'}
            </div>
          ) : (
            <>
              {/* header */}
              <div className="flex items-center gap-3 px-4 py-3 border-b">
                <button className="md:hidden text-slate-500" onClick={() => setMedicoSel(null)}>
                  <ArrowLeft className="h-5 w-5" />
                </button>
                {medico.foto_url ? (
                  <img src={medico.foto_url} alt="" className="w-9 h-9 rounded-full object-cover" />
                ) : (
                  <div className="w-9 h-9 rounded-full bg-sky-100 text-sky-700 flex items-center justify-center text-xs font-bold">
                    {iniciales(medico.nombre_completo)}
                  </div>
                )}
                <div className="min-w-0">
                  <p className="font-semibold text-sm text-slate-800 truncate">{medico.nombre_completo}</p>
                  {medico.especialidad && <p className="text-xs text-slate-400 truncate">{medico.especialidad}</p>}
                </div>
              </div>

              {/* mensajes */}
              <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3 bg-slate-50/50">
                {loadingMsgs ? (
                  <div className="flex items-center justify-center py-10">
                    <Loader2 className="h-6 w-6 animate-spin text-sky-500" />
                  </div>
                ) : mensajes.length === 0 ? (
                  <div className="text-center py-12">
                    <MessageCircle className="h-12 w-12 text-slate-300 mx-auto mb-3" />
                    <p className="text-slate-500">Aún no hay mensajes</p>
                    <p className="text-sm text-slate-400">Envía un mensaje para iniciar la conversación</p>
                  </div>
                ) : (
                  mensajes.map((msg) => {
                    const esPaciente = msg.remitente === 'paciente'
                    return (
                      <div key={msg.id} className={`flex ${esPaciente ? 'justify-end' : 'justify-start'}`}>
                        <div
                          className={`max-w-[80%] rounded-2xl px-4 py-2.5 ${
                            esPaciente ? 'bg-sky-500 text-white rounded-br-md' : 'bg-slate-100 text-slate-700 rounded-bl-md'
                          }`}
                        >
                          <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{msg.mensaje}</p>
                          <p className={`text-xs mt-1 ${esPaciente ? 'text-sky-100' : 'text-slate-400'}`}>
                            {hora(msg.created_at)}
                            {esPaciente && <span className="ml-1">{msg.leido ? '· Leído' : '· Enviado'}</span>}
                          </p>
                        </div>
                      </div>
                    )
                  })
                )}
              </div>

              {/* input */}
              {error && (
                <div className="px-4 py-1.5 text-xs text-red-600 border-t bg-red-50">{error}</div>
              )}
              <form onSubmit={handleEnviar} className="flex items-center gap-2 p-3 border-t">
                <Input
                  value={texto}
                  onChange={(e) => setTexto(e.target.value)}
                  placeholder="Escribe un mensaje..."
                  disabled={enviando}
                />
                <Button type="submit" size="icon" className="bg-sky-500 hover:bg-sky-600 shrink-0" disabled={!texto.trim() || enviando}>
                  {enviando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </Button>
              </form>
            </>
          )}
        </Card>
      </div>
    </div>
  )
}
