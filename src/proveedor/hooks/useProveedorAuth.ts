import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { CuentaProveedor, EmpresaProveedora } from '@/proveedor/types/proveedor.types'
import { toast } from 'sonner'

export function useProveedorAuth() {
  const [user, setUser] = useState<any>(null)
  const [cuenta, setCuenta] = useState<CuentaProveedor | null>(null)
  const [empresa, setEmpresa] = useState<EmpresaProveedora | null>(null)
  const [loading, setLoading] = useState(true)

  const fetchCuenta = useCallback(async (userId: string) => {
    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('*, empresa:empresa_id(*)')
      .eq('id', userId)
      .single()

    if (error || !data) {
      console.error('[useProveedorAuth] Error obteniendo cuenta:', error)
      setCuenta(null)
      setEmpresa(null)
      return
    }

    setCuenta(data as CuentaProveedor)
    setEmpresa(data.empresa as EmpresaProveedora)
  }, [])

  useEffect(() => {
    const init = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setUser(session?.user ?? null)
      if (session?.user) {
        await fetchCuenta(session.user.id)
      }
      setLoading(false)
    }

    init()

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
      if (session?.user) {
        fetchCuenta(session.user.id)
      } else {
        setCuenta(null)
        setEmpresa(null)
      }
    })

    return () => listener.subscription.unsubscribe()
  }, [fetchCuenta])

  const login = useCallback(async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    return { data, error }
  }, [])

  const register = useCallback(async (
    email: string,
    password: string,
    nombre_completo: string,
    empresa: Partial<EmpresaProveedora>
  ) => {
    // 1. Crear usuario en auth
    const { data: authData, error: authError } = await supabase.auth.signUp({ email, password })
    if (authError) {
      const msg = authError.message || ''
      if (msg.toLowerCase().includes('already registered') || msg.toLowerCase().includes('already exists') || authError.status === 422) {
        return { data: authData, error: { message: 'Este correo ya está registrado. Usa otro email o inicia sesión.' } }
      }
      return { data: authData, error: authError }
    }
    if (!authData.user) {
      return { data: authData, error: { message: 'No se pudo crear el usuario. Intenta de nuevo.' } }
    }

    // 2. Llamar función RPC con SECURITY DEFINER (evita problemas de RLS)
    const { data: empresaId, error: rpcError } = await supabase.rpc('registrar_proveedor', {
      p_nombre_empresa: empresa.nombre_empresa || '',
      p_tipo: empresa.tipo || 'farmacia',
      p_ruc_nit: empresa.ruc_nit || null,
      p_pais_id: empresa.pais_id || null,
      p_ciudad: empresa.ciudad || null,
      p_direccion: empresa.direccion || null,
      p_email_contacto: empresa.email_contacto || email,
      p_telefono: empresa.telefono || null,
      p_nombre_completo: nombre_completo,
      p_email: email,
    })

    if (rpcError) {
      console.error('Error RPC registrar_proveedor:', rpcError)
      // Si la RPC falló, el usuario auth ya existe pero no tiene empresa.
      // Limpiamos la sesión para no dejarlo en estado inconsistente.
      await supabase.auth.signOut()
      return { data: authData, error: { message: `Error al crear la empresa: ${rpcError.message}` } }
    }

    return { data: authData, error: null }
  }, [])

  const logout = useCallback(async () => {
    await supabase.auth.signOut()
    setUser(null)
    setCuenta(null)
    setEmpresa(null)
  }, [])

  const actualizarEmpresa = useCallback(async (data: Partial<EmpresaProveedora>): Promise<boolean> => {
    if (!empresa?.id) {
      toast.error('No hay empresa vinculada')
      return false
    }
    const { error } = await supabase
      .from('empresas_proveedoras')
      .update(data)
      .eq('id', empresa.id)

    if (error) {
      toast.error('Error actualizando empresa')
      console.error(error)
      return false
    }

    setEmpresa((prev) => (prev ? { ...prev, ...data } : null))
    toast.success('Empresa actualizada')
    return true
  }, [empresa?.id])

  const actualizarCuenta = useCallback(async (data: Partial<CuentaProveedor>): Promise<boolean> => {
    if (!cuenta?.id) {
      toast.error('No hay cuenta vinculada')
      return false
    }
    const { error } = await supabase
      .from('cuentas_proveedor')
      .update(data)
      .eq('id', cuenta.id)

    if (error) {
      toast.error('Error actualizando cuenta')
      console.error(error)
      return false
    }

    setCuenta((prev) => (prev ? { ...prev, ...data } : null))
    toast.success('Cuenta actualizada')
    return true
  }, [cuenta?.id])

  const isAdmin = cuenta?.rol_en_empresa === 'admin'
  const isEditor = cuenta?.rol_en_empresa === 'editor' || isAdmin

  return {
    user,
    cuenta,
    empresa,
    loading,
    login,
    register,
    logout,
    actualizarEmpresa,
    actualizarCuenta,
    isAdmin,
    isEditor,
  }
}
