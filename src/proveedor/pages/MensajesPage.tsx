import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { Send, Plus, Users, Shield, MessageSquare, Eye, Loader2, X } from 'lucide-react'

interface Conv {
  id: string
  tipo: string
  nombre: string | null
  equipo_id: string | null
  ultimo: string | null
  ultimo_at: string | null
  no_leidos: number
  es_auditoria: boolean
}
interface Msg { id: string; autor_id: string; autor_nombre: string; cuerpo: string; created_at: string; eliminado: boolean }
interface Contacto { id: string; nombre_completo: string; rol_en_empresa: string }

const tipoLabel = (c: Conv) =>
  c.tipo === 'administracion' ? 'Administración' : c.tipo === 'equipo' ? (c.nombre || 'Equipo') : (c.nombre || 'Directo')
const tipoIcon = (t: string) => (t === 'administracion' ? Shield : t === 'equipo' ? Users : MessageSquare)

export default function MensajesPage() {
  const { cuenta } = useProveedorAuth()
  const [convs, setConvs] = useState<Conv[]>([])
  const [activa, setActiva] = useState<Conv | null>(null)
  const [mensajes, setMensajes] = useState<Msg[]>([])
  const [texto, setTexto] = useState('')
  const [contactos, setContactos] = useState<Contacto[]>([])
  const [mostrarNuevo, setMostrarNuevo] = useState(false)
  const [loading, setLoading] = useState(true)
  const [enviando, setEnviando] = useState(false)
  const finRef = useRef<HTMLDivElement>(null)
  const activaRef = useRef<string | null>(null)
  activaRef.current = activa?.id ?? null

  const cargarConvs = useCallback(async () => {
    const { data } = await supabase.rpc('mis_conversaciones')
    setConvs((data || []) as Conv[])
  }, [])

  const cargarMensajes = useCallback(async (convId: string) => {
    const { data, error } = await supabase.rpc('mensajes_conversacion', { p_conv: convId })
    if (error) { toast.error('No se pudo abrir la conversación'); return }
    setMensajes((data || []) as Msg[])
    await supabase.rpc('marcar_leido_chat', { p_conv: convId })
  }, [])

  // Carga inicial: crear canales que correspondan + listar
  useEffect(() => {
    (async () => {
      setLoading(true)
      await supabase.rpc('sincronizar_mis_canales')
      const [{ data: cs }] = await Promise.all([
        supabase.rpc('mis_conversaciones'),
        supabase.rpc('contactos_chat').then((r) => setContactos((r.data || []) as Contacto[])),
      ])
      setConvs((cs || []) as Conv[])
      setLoading(false)
    })()
  }, [])

  // Realtime: cualquier mensaje nuevo refresca la lista; si es de la conv activa, recarga el hilo
  useEffect(() => {
    const ch = supabase
      .channel('chat-interno')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_mensajes_internos' }, (payload: any) => {
        const convId = payload.new?.conversacion_id
        cargarConvs()
        if (convId && convId === activaRef.current) cargarMensajes(convId)
      })
      .subscribe()
    return () => { supabase.removeChannel(ch) }
  }, [cargarConvs, cargarMensajes])

  useEffect(() => { finRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [mensajes])

  const abrir = async (c: Conv) => {
    setActiva(c)
    await cargarMensajes(c.id)
    cargarConvs()
  }

  const enviar = async () => {
    if (!texto.trim() || !activa || activa.es_auditoria) return
    setEnviando(true)
    const cuerpo = texto.trim()
    setTexto('')
    const { error } = await supabase.rpc('enviar_mensaje_chat', { p_conv: activa.id, p_cuerpo: cuerpo })
    setEnviando(false)
    if (error) { toast.error(error.message || 'No se pudo enviar'); setTexto(cuerpo); return }
    cargarMensajes(activa.id)
    cargarConvs()
  }

  const iniciarDirecto = async (c: Contacto) => {
    const { data, error } = await supabase.rpc('abrir_directo', { p_otro: c.id })
    if (error) { toast.error(error.message || 'No se pudo iniciar el chat'); return }
    setMostrarNuevo(false)
    await cargarConvs()
    const { data: cs } = await supabase.rpc('mis_conversaciones')
    const lista = (cs || []) as Conv[]
    setConvs(lista)
    const nueva = lista.find((x) => x.id === data) || { id: data, tipo: 'directo', nombre: c.nombre_completo, equipo_id: null, ultimo: null, ultimo_at: null, no_leidos: 0, es_auditoria: false }
    abrir(nueva as Conv)
  }

  return (
    <div className="h-[calc(100vh-7rem)] flex border rounded-lg overflow-hidden bg-white">
      {/* Lista de conversaciones */}
      <aside className="w-72 border-r flex flex-col shrink-0">
        <div className="p-3 border-b flex items-center justify-between">
          <h2 className="font-semibold">Mensajes</h2>
          <Button size="sm" variant="outline" onClick={() => setMostrarNuevo(true)}>
            <Plus className="h-4 w-4 mr-1" /> Nuevo
          </Button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
          ) : convs.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center p-6">Sin conversaciones todavía.</p>
          ) : convs.map((c) => {
            const Icon = tipoIcon(c.tipo)
            return (
              <button
                key={c.id}
                onClick={() => abrir(c)}
                className={`w-full text-left p-3 border-b hover:bg-slate-50 transition ${activa?.id === c.id ? 'bg-slate-100' : ''}`}
              >
                <div className="flex items-center gap-2">
                  <Icon className="h-4 w-4 text-muted-foreground shrink-0" />
                  <span className="font-medium text-sm truncate flex-1">{tipoLabel(c)}</span>
                  {c.es_auditoria && <Badge variant="outline" className="text-[10px]"><Eye className="h-3 w-3 mr-0.5" />Auditoría</Badge>}
                  {c.no_leidos > 0 && <span className="bg-[#1E5C8E] text-white text-xs rounded-full px-1.5 min-w-5 text-center">{c.no_leidos}</span>}
                </div>
                {c.ultimo && <p className="text-xs text-muted-foreground truncate mt-1 pl-6">{c.ultimo}</p>}
              </button>
            )
          })}
        </div>
      </aside>

      {/* Hilo */}
      <section className="flex-1 flex flex-col min-w-0">
        {!activa ? (
          <div className="flex-1 flex items-center justify-center text-muted-foreground">
            <div className="text-center">
              <MessageSquare className="h-10 w-10 mx-auto mb-2 text-slate-300" />
              <p>Elige una conversación</p>
            </div>
          </div>
        ) : (
          <>
            <div className="p-3 border-b flex items-center gap-2">
              <span className="font-semibold">{tipoLabel(activa)}</span>
              {activa.es_auditoria && <Badge variant="outline" className="text-xs"><Eye className="h-3 w-3 mr-1" />Solo lectura (auditoría)</Badge>}
            </div>
            <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-slate-50">
              {mensajes.map((m) => {
                const mio = m.autor_id === cuenta?.id
                return (
                  <div key={m.id} className={`flex ${mio ? 'justify-end' : 'justify-start'}`}>
                    <div className={`max-w-[75%] rounded-lg px-3 py-2 ${mio ? 'bg-[#1E5C8E] text-white' : 'bg-white border'}`}>
                      {!mio && <p className="text-[11px] font-semibold text-[#1E5C8E] mb-0.5">{m.autor_nombre}</p>}
                      <p className="text-sm whitespace-pre-wrap break-words">{m.cuerpo}</p>
                      <p className={`text-[10px] mt-1 ${mio ? 'text-white/70' : 'text-muted-foreground'}`}>
                        {new Date(m.created_at).toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' })}
                      </p>
                    </div>
                  </div>
                )
              })}
              <div ref={finRef} />
            </div>
            {activa.es_auditoria ? (
              <div className="p-3 border-t text-center text-xs text-muted-foreground">
                Estás viendo esta conversación en modo auditoría (solo lectura).
              </div>
            ) : (
              <div className="p-3 border-t flex items-center gap-2">
                <Input
                  value={texto}
                  onChange={(e) => setTexto(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar() } }}
                  placeholder="Escribe un mensaje…"
                />
                <Button onClick={enviar} disabled={enviando || !texto.trim()} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  {enviando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </Button>
              </div>
            )}
          </>
        )}
      </section>

      {/* Modal nuevo mensaje */}
      {mostrarNuevo && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={() => setMostrarNuevo(false)}>
          <div className="bg-white rounded-lg shadow-xl w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
            <div className="p-4 border-b flex items-center justify-between">
              <h3 className="font-semibold">Nuevo mensaje directo</h3>
              <button onClick={() => setMostrarNuevo(false)}><X className="h-4 w-4" /></button>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {contactos.length === 0 ? (
                <p className="text-sm text-muted-foreground p-6 text-center">No tienes contactos disponibles.</p>
              ) : contactos.map((c) => (
                <button key={c.id} onClick={() => iniciarDirecto(c)} className="w-full text-left p-3 border-b hover:bg-slate-50 flex items-center gap-3">
                  <div className="h-8 w-8 rounded-full bg-primary/10 flex items-center justify-center text-primary text-xs font-bold">
                    {(c.nombre_completo || '?').slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <p className="text-sm font-medium">{c.nombre_completo}</p>
                    <p className="text-xs text-muted-foreground">{c.rol_en_empresa}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
