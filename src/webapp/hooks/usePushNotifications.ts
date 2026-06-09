import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { VAPID_PUBLIC_KEY } from '@/lib/push-config'
import { toast } from 'sonner'

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = window.atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

export function usePushNotifications() {
  const [soportado, setSoportado] = useState(false)
  const [permiso, setPermiso] = useState<NotificationPermission | null>(null)
  const [suscrito, setSuscrito] = useState(false)
  const [cargando, setCargando] = useState(false)

  useEffect(() => {
    const checkSupport = () => {
      const supported =
        'serviceWorker' in navigator &&
        'PushManager' in window &&
        'Notification' in window
      setSoportado(supported)
      if (supported) {
        setPermiso(Notification.permission)
      }
    }
    checkSupport()
  }, [])

  const verificarSuscripcion = useCallback(async () => {
    if (!soportado) return
    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()
      setSuscrito(!!subscription)
      if (subscription) {
        setPermiso(Notification.permission)
      }
    } catch (err) {
      console.error('Error verificando suscripción push:', err)
    }
  }, [soportado])

  useEffect(() => {
    verificarSuscripcion()
  }, [verificarSuscripcion])

  const solicitarPermiso = useCallback(async () => {
    if (!soportado) {
      toast.error('Tu navegador no soporta notificaciones push')
      return false
    }

    // Si ya está denegado, no intentar de nuevo
    if (Notification.permission === 'denied') {
      toast.error(
        'Las notificaciones están bloqueadas. Actívalas manualmente en la configuración del navegador (🔒 icono en la barra de direcciones) o usa una ventana normal (no incógnito).',
        { duration: 6000 }
      )
      return false
    }

    const result = await Notification.requestPermission()
    setPermiso(result)
    if (result === 'denied') {
      toast.error(
        'Permiso denegado. Para activar notificaciones: 1) Cierra modo incógnito, 2) Haz clic en el 🔒 de la barra de direcciones, 3) Permite notificaciones.',
        { duration: 8000 }
      )
      return false
    }
    return result === 'granted'
  }, [soportado])

  const suscribir = useCallback(async () => {
    if (!soportado) return
    setCargando(true)

    try {
      const registration = await navigator.serviceWorker.ready

      // Obtener suscripción existente o crear nueva
      let subscription = await registration.pushManager.getSubscription()
      if (!subscription) {
        // Verificar permiso antes de solicitar
        if (Notification.permission === 'denied') {
          toast.error(
            'Notificaciones bloqueadas. Usa una ventana normal (no incógnito) o activa el permiso manualmente en el navegador.',
            { duration: 6000 }
          )
          setCargando(false)
          return
        }

        const permissionGranted = await solicitarPermiso()
        if (!permissionGranted) {
          setCargando(false)
          return
        }

        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
        })
      }

      // Guardar en Supabase
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        toast.error('Debes iniciar sesión para recibir notificaciones')
        setCargando(false)
        return
      }

      // Convertir claves a base64 de forma segura
      const p256dhKey = subscription.getKey('p256dh')
      const authKey = subscription.getKey('auth')
      if (!p256dhKey || !authKey) {
        throw new Error('La suscripción no tiene las claves requeridas')
      }

      const p256dh = btoa(String.fromCharCode(...new Uint8Array(p256dhKey)))
      const auth = btoa(String.fromCharCode(...new Uint8Array(authKey)))

      console.log('[Push] Guardando suscripción:', {
        user_id: user.id,
        endpoint: subscription.endpoint.slice(0, 60) + '...',
        p256dh_len: p256dh.length,
        auth_len: auth.length,
      })

      // Eliminar suscripciones previas del usuario e insertar nueva
      const { error: delError } = await supabase
        .from('push_subscriptions')
        .delete()
        .eq('user_id', user.id)

      if (delError) {
        console.warn('[Push] Error eliminando suscripción previa:', delError)
      }

      const { error } = await supabase.from('push_subscriptions').insert({
        user_id: user.id,
        endpoint: subscription.endpoint,
        p256dh,
        auth,
      })

      if (error) {
        console.error('[Push] Error insertando suscripción:', error)
        throw error
      }

      console.log('[Push] Suscripción guardada exitosamente')

      setSuscrito(true)
      toast.success('Notificaciones push activadas')
    } catch (err: any) {
      console.error('Error suscribiendo a push:', err)
      toast.error('Error activando notificaciones: ' + (err.message || 'Desconocido'))
    } finally {
      setCargando(false)
    }
  }, [soportado, solicitarPermiso])

  const desuscribir = useCallback(async () => {
    if (!soportado) return
    setCargando(true)

    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()

      if (subscription) {
        await subscription.unsubscribe()
        // Eliminar de Supabase
        await supabase.from('push_subscriptions').delete().eq('endpoint', subscription.endpoint)
      }

      setSuscrito(false)
      toast.success('Notificaciones push desactivadas')
    } catch (err: any) {
      console.error('Error desuscribiendo:', err)
      toast.error('Error desactivando notificaciones')
    } finally {
      setCargando(false)
    }
  }, [soportado])

  return {
    soportado,
    permiso,
    suscrito,
    cargando,
    suscribir,
    desuscribir,
    solicitarPermiso,
    verificarSuscripcion,
  }
}
