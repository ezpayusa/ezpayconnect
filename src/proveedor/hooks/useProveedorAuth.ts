import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { CuentaProveedor, EmpresaProveedora } from '@/proveedor/types/proveedor.types'
import { permisosDeRol, puedeRol, type PermisoProveedor } from '@/proveedor/lib/permisos'
import { toast } from 'sonner'
import { aceptarInvitacionPendiente } from '@/lib/invitacionProveedor'
import { APP_URL } from '@/lib/app-url'
import {
  completarRegistroPendiente,
  loginDePortal,
  mensajeErrorRegistroEmpresa,
  type RegistroEmpresa,
} from '@/proveedor/lib/registroDiferido'

export function useProveedorAuth() {
  const [user, setUser] = useState<any>(null)
  const [cuenta, setCuenta] = useState<CuentaProveedor | null>(null)
  const [empresa, setEmpresa] = useState<EmpresaProveedora | null>(null)
  const [loading, setLoading] = useState(true)

  const fetchCuenta = useCallback(async (userId: string) => {
    // maybeSingle: si el usuario no es proveedor devuelve data=null sin error 406.
    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('*, empresa:empresa_id(*)')
      .eq('id', userId)
      .maybeSingle()

    if (error) {
      console.error('[useProveedorAuth] Error obteniendo cuenta:', error)
    }
    // Sin cuenta o cuenta dada de baja (activo=false) => sin acceso.
    if (error || !data || (data as any).activo === false) {
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
    if (error) return { data, error }
    const userId = data.user!.id

    const buscarCuenta = async () => {
      const { data: c } = await supabase
        .from('cuentas_proveedor')
        .select('id, activo')
        .eq('id', userId)
        .maybeSingle()
      return c
    }

    // Verificar que la cuenta sea de proveedor; si no, cerrar sesión y avisar claro
    // (evita el rebote silencioso al usar una cuenta de admin/médico/paciente aquí).
    let cuentaData = await buscarCuenta()

    // Sin cuenta todavía: antes de rechazar, una invitación pendiente (visitador invitado) o un alta diferida
    // (mig 373: la empresa quedó en la metadata del signUp porque con Confirm email ON no había sesión).
    if (!cuentaData && (await aceptarInvitacionPendiente())) {
      cuentaData = await buscarCuenta()
    }
    if (!cuentaData) {
      const r = await completarRegistroPendiente()
      if ('error' in r) {
        await supabase.auth.signOut()
        const message = r.error.code === 'RP003'
          ? 'Esta cuenta no es de un proveedor. Usa el portal que corresponde a tu cuenta.'
          : mensajeErrorRegistroEmpresa(r.error)
        return { data, error: { message } }
      }
      cuentaData = await buscarCuenta()
      await fetchCuenta(userId)
    }

    if (!cuentaData) {
      await supabase.auth.signOut()
      return {
        data,
        error: { message: 'Esta cuenta no es de un proveedor. Usa el portal que corresponde a tu cuenta.' },
      }
    }
    if (!cuentaData.activo) {
      await supabase.auth.signOut()
      return {
        data,
        error: { message: 'Tu cuenta fue desactivada. Contacta al administrador de tu empresa.' },
      }
    }
    return { data, error: null }
  }, [fetchCuenta])

  const register = useCallback(async (
    email: string,
    password: string,
    nombre_completo: string,
    empresa: Partial<EmpresaProveedora>
  ) => {
    // Alta diferida (mig 373): con Confirm email ON el signUp no da sesión, así que los datos de la empresa viajan en
    // la metadata (registro_empresa) y la empresa se crea con completar_registro_proveedor al primer login.
    const tipo = empresa.tipo || 'farmacia'
    const registro_empresa: RegistroEmpresa = {
      nombre_empresa: empresa.nombre_empresa || '',
      tipo,
      ruc_nit: empresa.ruc_nit || null,
      pais_id: empresa.pais_id || null,
      ciudad: empresa.ciudad || null,
      direccion: empresa.direccion || null,
      email_contacto: empresa.email_contacto || email,
      telefono: empresa.telefono || null,
      nombre_completo,
    }

    // 1. Crear usuario en auth
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { registro_empresa },
        emailRedirectTo: `${APP_URL}${loginDePortal(tipo)}`,
      },
    })
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
    // Con Confirm email ON, un correo ya registrado no da error: vuelve un usuario sin identidades.
    if (Array.isArray(authData.user.identities) && authData.user.identities.length === 0) {
      return { data: authData, error: { message: 'Este correo ya está registrado. Usa otro email o inicia sesión.' } }
    }

    // userId: uid del usuario recién creado, para atar a él la aceptación de textos legales del alta (GL-02).
    // 2a. Sin sesión (correo por confirmar): la empresa se crea en el primer login.
    if (!authData.session) {
      return { data: authData, error: null, userId: authData.user.id, pendienteConfirmacion: true }
    }

    // 2b. Con sesión (Confirm email OFF): se completa ya.
    const r = await completarRegistroPendiente()
    if ('error' in r) {
      // El usuario auth ya existe pero no tiene empresa: cerrar la sesión para no dejarlo a medias.
      await supabase.auth.signOut()
      return { data: authData, error: { message: mensajeErrorRegistroEmpresa(r.error) } }
    }
    return { data: authData, error: null, userId: authData.user.id, pendienteConfirmacion: false }
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
    // logo_url y colores NO se editan por acá: viven en el flujo de personalización
    // (solicitar_personalizacion / aprobar_personalizacion). El guard de BD (mig 205) bloquea
    // su UPDATE directo, así que se excluyen del payload de este hook.
    const { logo_url: _omitLogo, color_primario: _omitC1, color_secundario: _omitC2, color_fondo: _omitC3, ...datosEmpresa } = data as Partial<EmpresaProveedora> & Record<string, unknown>
    const { error } = await supabase
      .from('empresas_proveedoras')
      .update(datosEmpresa)
      .eq('id', empresa.id)

    if (error) {
      toast.error('Error actualizando empresa')
      console.error(error)
      return false
    }

    setEmpresa((prev) => (prev ? { ...prev, ...datosEmpresa } : null))
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

  const rol = cuenta?.rol_en_empresa ?? null
  const isAdmin = rol === 'admin'
  const isEditor = rol === 'editor' || isAdmin
  const permisos = permisosDeRol(rol)
  const puede = (permiso: PermisoProveedor) => puedeRol(rol, permiso)

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
    rol,
    permisos,
    puede,
  }
}
