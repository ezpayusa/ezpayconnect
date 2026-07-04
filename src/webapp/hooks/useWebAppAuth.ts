import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { PacientePerfil } from '@/webapp/types/webapp.types'

// País por defecto (Guatemala) — mismo valor que src/hooks/useAuth.ts
const PAIS_DEFAULT = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'

export function useWebAppAuth() {
  const [user, setUser] = useState<any>(null)
  const [perfil, setPerfil] = useState<PacientePerfil | null>(null)
  const [loading, setLoading] = useState(true)
  const [notificacionesNoLeidas, setNotificacionesNoLeidas] = useState(0)

  const fetchPerfil = useCallback(async (userId: string, userEmail?: string) => {
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

    if (data) {
      setPerfil(data as PacientePerfil)
      // Contar notificaciones no leídas (ignorar error si tabla no existe)
      const { count } = await supabase
        .from('notificaciones_pacientes')
        .select('*', { count: 'exact', head: true })
        .eq('paciente_id', data.id)
        .eq('leida', false)
      setNotificacionesNoLeidas(count || 0)
    } else {
      setPerfil(null)
    }
  }, [])

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user || null)
      if (session?.user) {
        fetchPerfil(session.user.id, session.user.email || undefined)
      } else {
        setPerfil(null)
      }
      setLoading(false)
    })

    // Check initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user || null)
      if (session?.user) {
        fetchPerfil(session.user.id, session.user.email || undefined)
      }
      setLoading(false)
    })

    return () => subscription.unsubscribe()
  }, [fetchPerfil])

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
    setUser(null)
    setPerfil(null)
  }

  return { user, perfil, loading, login, register, logout, notificacionesNoLeidas }
}
