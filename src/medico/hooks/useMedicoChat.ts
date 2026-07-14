import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { extractPath } from '@/lib/signedUrl'

const BUCKET_FOTOS = 'pacientes-fotos'

export interface HiloChat {
  paciente_id: number
  nombre: string
  apellido: string
  foto_path: string | null
  foto_url: string | null      // signed URL (o null si no hay foto / falló la firma)
  ultimo_mensaje: string
  ultimo_at: string
  no_leidos: number
}

export interface MensajeChat {
  id: number
  remitente: string            // 'paciente' | 'medico'
  mensaje: string
  leido: boolean
  created_at: string
}

/**
 * Chat del lado MÉDICO. Todo pasa por RPCs DEFINER (backend mig 257):
 *   listar_hilos_chat_medico() · leer_hilo_chat_medico(pid) · enviar_mensaje_chat_medico(pid, texto)
 * Realtime: la policy SELECT del médico (mig 257) permite que reciba SUS filas de chat_mensajes.
 * Las fotos vienen como path CRUDO (bucket privado) → se firman con createSignedUrl (TTL 120s).
 */
export function useMedicoChat() {
  const [hilos, setHilos] = useState<HiloChat[]>([])
  const [loadingHilos, setLoadingHilos] = useState(true)
  const [errorHilos, setErrorHilos] = useState<string | null>(null)

  const [hiloActivo, setHiloActivo] = useState<number | null>(null)
  const [mensajes, setMensajes] = useState<MensajeChat[]>([])
  const [loadingMensajes, setLoadingMensajes] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const hiloActivoRef = useRef<number | null>(null)
  const uidRef = useRef<string | null>(null)
  hiloActivoRef.current = hiloActivo

  // ── Listar hilos + firmar avatares ──────────────────────────────────────────
  const refetchHilos = useCallback(async () => {
    try {
      setErrorHilos(null)
      const { data, error: err } = await supabase.rpc('listar_hilos_chat_medico')
      if (err) throw err

      const firmados: HiloChat[] = await Promise.all(
        (data || []).map(async (h: any) => {
          let foto_url: string | null = null
          if (h.paciente_foto_path) {
            const { data: sd } = await supabase.storage
              .from(BUCKET_FOTOS)
              .createSignedUrl(extractPath(BUCKET_FOTOS, h.paciente_foto_path), 120)
            foto_url = sd?.signedUrl ?? null  // firma fallida → null, NO rompe la lista
          }
          return {
            paciente_id: h.paciente_id,
            nombre: h.paciente_nombre,
            apellido: h.paciente_apellido,
            foto_path: h.paciente_foto_path ?? null,
            foto_url,
            ultimo_mensaje: h.ultimo_mensaje,
            ultimo_at: h.ultimo_at,
            no_leidos: Number(h.no_leidos ?? 0),
          }
        })
      )
      setHilos(firmados)
    } catch (err: any) {
      console.error('Error listando hilos de chat:', err?.message ?? err)
      setErrorHilos(err?.message ?? 'No se pudieron cargar las conversaciones')
    } finally {
      setLoadingHilos(false)
    }
  }, [])

  // ── Leer un hilo (la RPC marca leídos server-side) ──────────────────────────
  const cargarMensajes = useCallback(async (pid: number) => {
    try {
      setLoadingMensajes(true)
      setError(null)
      const { data, error: err } = await supabase.rpc('leer_hilo_chat_medico', { p_paciente_id: pid })
      if (err) throw err
      const mapped: MensajeChat[] = (data || []).map((m: any) => ({
        id: m.id,
        remitente: m.remitente,
        mensaje: m.mensaje,
        leido: m.leido,
        created_at: m.created_at,
      }))
      setMensajes(mapped)
      // la RPC ya marcó leídos los del paciente → refrescar la lista para bajar el badge
      refetchHilos()
    } catch (err: any) {
      console.error('Error leyendo hilo:', err?.message ?? err)
      setError(err?.message ?? 'No se pudo cargar la conversación')
    } finally {
      setLoadingMensajes(false)
    }
  }, [refetchHilos])

  // ── Enviar mensaje del médico ───────────────────────────────────────────────
  const enviarMensaje = useCallback(async (texto: string) => {
    const pid = hiloActivoRef.current
    if (!pid || !texto.trim()) return
    try {
      setEnviando(true)
      setError(null)
      const { data: nuevoId, error: err } = await supabase.rpc('enviar_mensaje_chat_medico', {
        p_paciente_id: pid,
        p_mensaje: texto.trim(),
      })
      if (err) throw err

      // notificar al paciente, best-effort (no rompe el envío si falla)
      if (nuevoId) {
        try {
          await supabase.rpc('notificar_chat', { p_mensaje_id: nuevoId })
        } catch (notifErr) {
          console.error('Error notificar_chat:', notifErr)
        }
      }

      await cargarMensajes(pid)
    } catch (err: any) {
      console.error('Error enviando mensaje:', err?.message ?? err)
      setError(err?.message ?? 'No se pudo enviar el mensaje')
    } finally {
      setEnviando(false)
    }
  }, [cargarMensajes])

  // Carga inicial de hilos
  useEffect(() => {
    refetchHilos()
  }, [refetchHilos])

  // Al cambiar el hilo activo, cargar sus mensajes
  useEffect(() => {
    if (hiloActivo != null) {
      cargarMensajes(hiloActivo)
    } else {
      setMensajes([])
    }
  }, [hiloActivo, cargarMensajes])

  // ── Realtime: INSERT en chat_mensajes (la RLS ya limita a las filas del médico) ──
  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null
    let cancelado = false

    ;(async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user || cancelado) return
      uidRef.current = user.id

      channel = supabase
        .channel(`chat_medico_${user.id}`)
        .on(
          'postgres_changes',
          { event: 'INSERT', schema: 'public', table: 'chat_mensajes' },
          (payload) => {
            const nuevo = payload.new as any
            // defensivo: solo filas de este médico (la RLS ya filtra, pero por si acaso)
            if (uidRef.current && nuevo.medico_id !== uidRef.current) return

            // si el hilo del mensaje está abierto, appendear evitando duplicados por id
            if (hiloActivoRef.current != null && nuevo.paciente_id === hiloActivoRef.current) {
              setMensajes((prev) =>
                prev.some((m) => m.id === nuevo.id)
                  ? prev
                  : [...prev, {
                      id: nuevo.id,
                      remitente: nuevo.remitente,
                      mensaje: nuevo.mensaje,
                      leido: nuevo.leido,
                      created_at: nuevo.created_at,
                    }]
              )
            }
            // siempre refrescar la lista (último mensaje + no-leídos)
            refetchHilos()
          }
        )
        .subscribe()
    })()

    return () => {
      cancelado = true
      if (channel) channel.unsubscribe()
    }
  }, [refetchHilos])

  return {
    hilos,
    loadingHilos,
    errorHilos,
    hiloActivo,
    setHiloActivo,
    mensajes,
    loadingMensajes,
    enviando,
    error,
    enviarMensaje,
    refetchHilos,
  }
}
