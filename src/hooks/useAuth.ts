import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Perfil } from '@/types'

// País default (Guatemala) para registros sin país explícito
const PAIS_DEFAULT = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'

export function useAuth() {
  const [user, setUser] = useState<any>(null)
  const [perfil, setPerfil] = useState<Perfil | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const getSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setUser(session?.user ?? null)
      if (session?.user) {
        const { data } = await supabase
          .from('perfiles')
          .select('*')
          .eq('id', session.user.id)
          .single()
        setPerfil(data)
      }
      setLoading(false)
    }
    getSession()

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
      if (session?.user) {
        supabase.from('perfiles').select('*').eq('id', session.user.id).single()
          .then(({ data }) => setPerfil(data))
      } else {
        setPerfil(null)
      }
    })

    return () => listener.subscription.unsubscribe()
  }, [])

  const login = useCallback(async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    return { data, error }
  }, [])

  const register = useCallback(async (email: string, password: string, nombre_completo: string, rol: string = 'medico', pais_id?: string) => {
    const { data, error } = await supabase.auth.signUp({ email, password })
    if (error) return { data, error }
    if (data.user) {
      const { error: perfilError } = await supabase.from('perfiles').insert({
        id: data.user.id,
        email,
        nombre_completo,
        rol: rol || 'medico',
        pais_id: pais_id || PAIS_DEFAULT,
      })
      if (perfilError) {
        console.error('Error creando perfil:', perfilError)
        return { data, error: { message: `Cuenta creada pero error al crear perfil: ${perfilError.message}` } }
      }
    }
    return { data, error }
  }, [])

  const logout = useCallback(async () => {
    await supabase.auth.signOut()
    setUser(null)
    setPerfil(null)
  }, [])

  // Función para verificar si tiene permiso
  const hasRole = useCallback((roles: string[]) => {
    return roles.includes(perfil?.rol || '')
  }, [perfil])

  const isAdmin = useCallback(() => perfil?.rol === 'admin', [perfil])
  const isMedico = useCallback(() => perfil?.rol === 'medico', [perfil])
  const isAsistente = useCallback(() => perfil?.rol === 'asistente', [perfil])

  return { user, perfil, loading, login, register, logout, hasRole, isAdmin, isMedico, isAsistente }
}