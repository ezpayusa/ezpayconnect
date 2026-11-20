import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import type { PacientePerfil } from '@/webapp/types/webapp.types'

// País por defecto (Guatemala) — mismo valor que src/hooks/useAuth.ts
const PAIS_DEFAULT = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'

export function useWebAppAuth() {
  const [user, setUser] = useState<any>(null)
  const [perfil, setPerfil] = useState<PacientePerfil | null>(null)
  const [loading, setLoading] = useState(true)
  const [notificacionesNoLeidas, setNotificacionesNoLeidas] = useState(0)

  // Número de la carga vigente: una respuesta de una carga anterior (otra sesión) se descarta.
  const cargaRef = useRef(0)
  // Usuario de la sesión ya cargada o cargándose. `undefined` = todavía no se procesó ninguna sesión.
  const uidRef = useRef<string | null | undefined>(undefined)

  // Lee la ficha del paciente y sus notificaciones no leídas. No toca el estado: lo aplica el llamador
  // solo si su carga sigue vigente.
  const leerPerfil = useCallback(async (userId: string, userEmail?: string) => {
    // 1. Intentar buscar por auth_user_id (después de migración)
    let { data, error } = await supabase
      .from('pacientes')
      .select('*')
      .eq('auth_user_id', userId)
      .maybeSingle()

    // 2. Fallback: buscar por email si auth_user_id no existe o no hay match
    if ((!data || error) && userEmail) {
      const { data: dataByEmail } = await supabase
        .from('pacientes')
        .select('*')
        .eq('email', userEmail)
        .maybeSingle()
      data = dataByEmail
    }

    if (!data) return { perfil: null, noLeidas: 0 }
    // Contar notificaciones no leídas (ignorar error si tabla no existe)
    const { count } = await supabase
      .from('notificaciones_pacientes')
      .select('*', { count: 'exact', head: true })
      .eq('paciente_id', data.id)
      .eq('leida', false)
    return { perfil: data as PacientePerfil, noLeidas: count || 0 }
  }, [])

  // `loading` queda en true hasta que termina la lectura de la ficha (también si falla o si no hay
  // sesión): la ruta privada no decide con perfil null a medio cargar, así que un paciente válido no ve
  // «Acceso restringido». La misma sesión otra vez (INITIAL_SESSION + getSession, TOKEN_REFRESHED) no
  // relee ni vuelve a mostrar el spinner.
  const procesarSesion = useCallback((sessionUser: any) => {
    const uid: string | null = sessionUser?.id ?? null
    setUser(sessionUser ?? null)
    if (uid === uidRef.current) return
    uidRef.current = uid
    const carga = ++cargaRef.current
    if (!uid) {
      setPerfil(null)
      setNotificacionesNoLeidas(0)
      setLoading(false)
      return
    }
    setLoading(true)
    setPerfil(null)
    leerPerfil(uid, sessionUser.email || undefined)
      .then(({ perfil: p, noLeidas }) => {
        if (carga !== cargaRef.current) return
        setPerfil(p)
        setNotificacionesNoLeidas(noLeidas)
      })
      .catch((err: any) => {
        if (carga !== cargaRef.current) return
        console.error('[WebApp auth] no se pudo leer la ficha del paciente:', err?.message ?? err?.code)
        setPerfil(null)
      })
      .finally(() => {
        if (carga === cargaRef.current) setLoading(false)
      })
  }, [leerPerfil])

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      procesarSesion(session?.user)
    })

    // Check initial session
    supabase.auth.getSession()
      .then(({ data: { session } }) => procesarSesion(session?.user))
      .catch(() => procesarSesion(null))

    return () => subscription.unsubscribe()
  }, [procesarSesion])

  // Re-lee el perfil desde la base (tras un guardado). No confiar en el estado local: el guardado
  // pudo aplicar solo parte del diff (o normalizar valores), así que la fuente de verdad es la base.
  // No toca `loading` (la pantalla no se desmonta) y se descarta si cambió la sesión mientras tanto.
  const refetchPerfil = useCallback(async () => {
    const carga = cargaRef.current
    const { data: { user } } = await supabase.auth.getUser()
    if (!user || carga !== cargaRef.current) return
    const { perfil: p, noLeidas } = await leerPerfil(user.id, user.email || undefined)
    if (carga !== cargaRef.current) return
    setPerfil(p)
    setNotificacionesNoLeidas(noLeidas)
  }, [leerPerfil])

  const login = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error }
  }

  const register = async (email: string, password: string, datos: Partial<PacientePerfil> & { pais_id?: string }) => {
    // La fila de `pacientes` la crea el trigger server-side handle_new_paciente (mig 230),
    // leyendo esta metadata desde raw_user_meta_data. El marcador tipo:'paciente' gatea el
    // trigger (los signups de médico/proveedor/visitador NO lo setean → no crean paciente).
    // Se pasa aquí porque con email-confirm ON no hay sesión y el insert client-side quedaba
    // bloqueado por RLS (auth.uid() null). Se eliminó ese insert; el trigger es el único camino.
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          tipo: 'paciente',
          nombre: datos.nombre || '',
          apellido: datos.apellido || '',
          telefono: datos.telefono || null,
          fecha_nacimiento: datos.fecha_nacimiento || null,
          genero: datos.genero || null,
          pais_id: datos.pais_id || PAIS_DEFAULT,
        },
      },
    })
    if (error) {
      console.error('[WebApp register] signUp falló:', error)
      return { error }
    }
    if (!data.user) {
      console.error('[WebApp register] signUp no devolvió user')
      return { error: { message: 'No se pudo crear el usuario. Intenta de nuevo.' } }
    }

    return { error: null }
  }

  const logout = async () => {
    await supabase.auth.signOut()
    // Sin sesión: invalida cualquier carga en curso y apaga el loading (el SIGNED_OUT que llega
    // después es la misma sesión nula y no hace nada).
    procesarSesion(null)
  }

  return { user, perfil, loading, login, register, logout, notificacionesNoLeidas, refetchPerfil }
}
