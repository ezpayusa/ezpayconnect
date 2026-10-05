import { useEffect, useRef } from 'react'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'

let canalSeq = 0

/**
 * Cola en vivo del repartidor (mig 353). Escucha los INSERT de SUS notificaciones (public.notificaciones ya está en
 * supabase_realtime y su SELECT es auth.uid() = usuario_id: realtime solo le entrega sus propias filas) y, cuando
 * llega una de entregas, muestra el aviso y vuelve a pedir la cola. No se publica `entregas` en realtime.
 * Además refresca al volver a la app o a la red, por si el canal se cortó mientras tanto.
 */
export function useColaEnVivo(usuarioId: string | null | undefined, refrescar: () => void) {
  const refrescarRef = useRef(refrescar)
  refrescarRef.current = refrescar

  useEffect(() => {
    if (!usuarioId) return
    const canal = supabase
      .channel(`repartidor_cola_${usuarioId}_${++canalSeq}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notificaciones', filter: `usuario_id=eq.${usuarioId}` },
        (payload) => {
          const n = payload.new as { tipo?: string; titulo?: string | null; mensaje?: string | null }
          if (n.tipo === 'entrega_asignada') toast.success(n.titulo || 'Tienes entregas nuevas', { description: n.mensaje ?? undefined })
          else if (n.tipo === 'entrega_quitada') toast.info(n.titulo || 'Te quitaron una entrega', { description: n.mensaje ?? undefined })
          else return
          refrescarRef.current()
        },
      )
      .subscribe()

    const alVolver = () => { if (document.visibilityState === 'visible') refrescarRef.current() }
    const alReconectar = () => refrescarRef.current()
    document.addEventListener('visibilitychange', alVolver)
    window.addEventListener('online', alReconectar)
    return () => {
      document.removeEventListener('visibilitychange', alVolver)
      window.removeEventListener('online', alReconectar)
      supabase.removeChannel(canal).catch(() => {})
    }
  }, [usuarioId])
}
