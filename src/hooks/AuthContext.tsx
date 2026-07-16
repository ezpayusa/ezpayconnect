import { createContext, useContext, useState, useEffect, useCallback, useMemo, useRef, type ReactNode } from 'react'
import { supabase } from '@/lib/supabase'
import type { Perfil } from '@/types'

// País default (Guatemala) para registros sin país explícito
const PAIS_DEFAULT = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'

type AuthContextValue = {
  user: any
  perfil: Perfil | null
  loading: boolean
  login: (email: string, password: string) => Promise<any>
  register: (email: string, password: string, nombre_completo: string, rol?: string, pais_id?: string) => Promise<any>
  logout: () => Promise<void>
  hasRole: (roles: string[]) => boolean
  isAdmin: () => boolean
  isMedico: () => boolean
  isAsistente: () => boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null)
  const [perfil, setPerfil] = useState<Perfil | null>(null)
  const [loading, setLoading] = useState(true)
  const loadedForUserId = useRef<string | null>(null)

  const fetchPerfil = useCallback(async (userId: string) => {
    // Intentar via RPC primero (bypass PostgREST schema cache)
    const { data: perfilRpc } = await supabase
      .rpc('obtener_perfil', { p_user_id: userId })
      .maybeSingle()
    if (perfilRpc) {
      setPerfil(perfilRpc as any)
      loadedForUserId.current = userId
      return
    }
    // Fallback a query directa
    const { data } = await supabase
      .from('perfiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle()
    setPerfil(data)
    loadedForUserId.current = userId
  }, [])

  useEffect(() => {
    let active = true

    const init = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (!active) return
      setUser(session?.user ?? null)
      if (session?.user && loadedForUserId.current !== session.user.id) {
        await fetchPerfil(session.user.id)
      }
      if (active) setLoading(false)
    }
    init()

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!active) return
      const nextUser = session?.user ?? null
      setUser(nextUser)
      if (nextUser) {
        if (loadedForUserId.current !== nextUser.id) fetchPerfil(nextUser.id)
      } else {
        setPerfil(null)
        loadedForUserId.current = null
      }
    })

    return () => {
      active = false
      listener.subscription.unsubscribe()
    }
  }, [fetchPerfil])

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
    loadedForUserId.current = null
  }, [])

  const hasRole = useCallback((roles: string[]) => roles.includes(perfil?.rol || ''), [perfil])
  const isAdmin = useCallback(() => ['super_admin','admin_clinica'].includes(perfil?.rol ?? ''), [perfil])
  const isMedico = useCallback(() => perfil?.rol === 'medico', [perfil])
  const isAsistente = useCallback(() => ['gerente','soporte'].includes(perfil?.rol ?? ''), [perfil])

  const value = useMemo(() => ({
    user, perfil, loading, login, register, logout, hasRole, isAdmin, isMedico, isAsistente
  }), [user, perfil, loading, login, register, logout, hasRole, isAdmin, isMedico, isAsistente])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth debe usarse dentro de <AuthProvider>')
  return ctx
}
