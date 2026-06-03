import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { PacientePerfil } from '@/webapp/types/webapp.types'

export function useWebAppAuth() {
  const [user, setUser] = useState<any>(null)
  const [perfil, setPerfil] = useState<PacientePerfil | null>(null)
  const [loading, setLoading] = useState(true)
  const [notificacionesNoLeidas, setNotificacionesNoLeidas] = useState(0)

  const fetchPerfil = useCallback(async (userId: string) => {
    // Buscar paciente vinculado al usuario de auth
    const { data } = await supabase
      .from('pacientes')
      .select('*')
      .eq('auth_user_id', userId)
      .single()

    if (data) {
      setPerfil(data as PacientePerfil)
      // Contar notificaciones no leídas
      const { count } = await supabase
        .from('notificaciones_pacientes')
        .select('*', { count: 'exact', head: true })
        .eq('paciente_id', data.id)
        .eq('leida', false)
      setNotificacionesNoLeidas(count || 0)
    }
  }, [])

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user || null)
      if (session?.user) {
        fetchPerfil(session.user.id)
      } else {
        setPerfil(null)
      }
      setLoading(false)
    })

    // Check initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user || null)
      if (session?.user) {
        fetchPerfil(session.user.id)
      }
      setLoading(false)
    })

    return () => subscription.unsubscribe()
  }, [fetchPerfil])

  const login = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error }
  }

  const register = async (email: string, password: string, datos: Partial<PacientePerfil>) => {
    const { data, error } = await supabase.auth.signUp({ email, password })
    if (error || !data.user) return { error }

    // Crear perfil de paciente
    await supabase.from('pacientes').insert({
      auth_user_id: data.user.id,
      nombre: datos.nombre || '',
      apellido: datos.apellido || '',
      email,
      telefono: datos.telefono || null,
      fecha_nacimiento: datos.fecha_nacimiento || null,
      genero: datos.genero || null,
      activo: true
    })

    return { error: null }
  }

  const logout = async () => {
    await supabase.auth.signOut()
    setUser(null)
    setPerfil(null)
  }

  return { user, perfil, loading, login, register, logout, notificacionesNoLeidas }
}
