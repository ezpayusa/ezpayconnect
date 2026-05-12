import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Perfil } from '@/types'

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

  const register = useCallback(async (email: string, password: string, nombre_completo: string) => {
    const { data, error } = await supabase.auth.signUp({ email, password })
    if (!error && data.user) {
      await supabase.from('perfiles').insert({
        id: data.user.id,
        email,
        nombre_completo,
        rol: 'medico'
      })
    }
    return { data, error }
  }, [])

  const logout = useCallback(async () => {
    await supabase.auth.signOut()
    setUser(null)
    setPerfil(null)
  }, [])

  return { user, perfil, loading, login, register, logout }
}
