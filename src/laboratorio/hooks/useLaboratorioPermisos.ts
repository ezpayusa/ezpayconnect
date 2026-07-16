import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// Permisos data-driven del laboratorio. La UI gatea leyendo los catálogos
// (roles_empresa_catalogo + permisos_empresa_rol, legibles por authenticated).
// IMPORTANTE: esto es SOLO para mostrar/ocultar; la autorización real la impone
// la RLS y los RPC SECURITY DEFINER del Frente A. No es una barrera de seguridad.
export interface RolProveedor {
  rol: string
  nivel: number
  es_admin: boolean
  label: string | null
}

export function useLaboratorioPermisos() {
  const { empresa, rol } = useProveedorAuth()
  const tipo = empresa?.tipo ?? null
  const [acciones, setAcciones] = useState<string[]>([])
  const [roles, setRoles] = useState<RolProveedor[]>([])
  const [loading, setLoading] = useState(true)

  const cargar = useCallback(async () => {
    if (!tipo) { setLoading(false); return }
    setLoading(true)
    const [{ data: perms }, { data: cat }] = await Promise.all([
      rol
        ? supabase.from('permisos_empresa_rol').select('accion').eq('tipo_empresa', tipo).eq('rol', rol)
        : Promise.resolve({ data: [] as { accion: string }[] }),
      supabase.from('roles_empresa_catalogo').select('rol, nivel, es_admin, label').eq('tipo_empresa', tipo).order('nivel', { ascending: false }),
    ])
    setAcciones(((perms || []) as { accion: string }[]).map((p) => p.accion))
    setRoles((cat || []) as RolProveedor[])
    setLoading(false)
  }, [tipo, rol])

  useEffect(() => { cargar() }, [cargar])

  const tienePermiso = useCallback((accion: string) => acciones.includes(accion), [acciones])

  const miRol = roles.find((r) => r.rol === rol) || null
  const soyAdmin = !!miRol?.es_admin

  // Roles que ESTE usuario puede asignar/dar de alta (espejo de la jerarquía del
  // RPC, solo para no mostrar opciones que el servidor rechazaría):
  // Admin → cualquiera; no-Admin → estrictamente inferior a su nivel.
  const rolesAsignables = roles.filter((r) =>
    soyAdmin ? true : (miRol != null && r.nivel < miRol.nivel)
  )

  return { acciones, tienePermiso, roles, rolesAsignables, miRol, soyAdmin, loading, recargar: cargar }
}
