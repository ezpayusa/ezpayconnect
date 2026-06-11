import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { ROLES_PROVEEDOR, etiquetaRol } from '@/proveedor/lib/permisos'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { ShieldCheck, Loader2, AlertTriangle, Users } from 'lucide-react'

interface Miembro {
  id: string
  nombre_completo: string
  email: string
  rol_en_empresa: string
  activo: boolean
}

export default function EquipoRolesPage() {
  const { empresa, cuenta, puede } = useProveedorAuth()
  const [miembros, setMiembros] = useState<Miembro[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('id, nombre_completo, email, rol_en_empresa, activo')
      .eq('empresa_id', empresa.id)
      .order('nombre_completo')
    if (error) {
      toast.error('Error cargando el equipo')
      console.error(error)
    } else {
      setMiembros((data || []) as Miembro[])
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    cargar()
  }, [cargar])

  const cambiarRol = async (cuentaId: string, nuevoRol: string) => {
    setGuardando(cuentaId)
    const { error } = await supabase.rpc('cambiar_rol_proveedor', {
      p_cuenta_id: cuentaId,
      p_rol: nuevoRol,
    })
    setGuardando(null)
    if (error) {
      toast.error(error.message || 'No se pudo cambiar el rol')
      return
    }
    toast.success('Rol actualizado')
    cargar()
  }

  if (!puede('usuarios.gestionar')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">
          Solo el administrador puede gestionar el equipo y los roles.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ShieldCheck className="w-6 h-6" />
          Equipo y Roles
        </h1>
        <p className="text-sm text-muted-foreground">
          Asigna a cada miembro el rol que corresponde a su trabajo. Cada rol ve y puede hacer
          únicamente lo de su área (confidencialidad y distribución de tareas).
        </p>
      </div>

      {/* Leyenda de roles */}
      <Card>
        <CardContent className="p-4">
          <p className="text-sm font-semibold mb-3 flex items-center gap-2">
            <Users className="w-4 h-4" /> Roles disponibles
          </p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {ROLES_PROVEEDOR.map((r) => (
              <div key={r.value} className="text-sm">
                <span className="font-medium text-[#1E5C8E]">{r.label}:</span>{' '}
                <span className="text-muted-foreground">{r.descripcion}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Lista de miembros */}
      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : (
        <div className="space-y-3">
          {miembros.map((m) => {
            const esYo = m.id === cuenta?.id
            return (
              <Card key={m.id} className={m.activo ? '' : 'opacity-60'}>
                <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center font-semibold text-primary shrink-0">
                      {(m.nombre_completo || m.email || '?').slice(0, 1).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <p className="font-semibold truncate">
                        {m.nombre_completo || '(sin nombre)'}{' '}
                        {esYo && <span className="text-xs text-muted-foreground">(tú)</span>}
                        {!m.activo && (
                          <Badge variant="outline" className="ml-2 text-xs">inactivo</Badge>
                        )}
                      </p>
                      <p className="text-sm text-muted-foreground truncate">{m.email}</p>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-xs text-muted-foreground hidden sm:inline">
                      Rol actual: <strong>{etiquetaRol(m.rol_en_empresa)}</strong>
                    </span>
                    <select
                      className="h-9 rounded-md border border-input bg-background px-3 text-sm disabled:opacity-50"
                      value={ROLES_PROVEEDOR.some((r) => r.value === m.rol_en_empresa) ? m.rol_en_empresa : ''}
                      disabled={guardando === m.id}
                      onChange={(e) => {
                        if (e.target.value && e.target.value !== m.rol_en_empresa) {
                          cambiarRol(m.id, e.target.value)
                        }
                      }}
                    >
                      {!ROLES_PROVEEDOR.some((r) => r.value === m.rol_en_empresa) && (
                        <option value="">{etiquetaRol(m.rol_en_empresa)} (legacy)</option>
                      )}
                      {ROLES_PROVEEDOR.map((r) => (
                        <option key={r.value} value={r.value}>
                          {r.label}
                        </option>
                      ))}
                    </select>
                    {guardando === m.id && <Loader2 className="h-4 w-4 animate-spin" />}
                  </div>
                </CardContent>
              </Card>
            )
          })}

          {miembros.length === 0 && (
            <Card className="bg-gray-50 border-dashed">
              <CardContent className="p-8 text-center text-muted-foreground">
                <Users className="h-10 w-10 mx-auto mb-3 text-gray-300" />
                <p>Aún no hay miembros en el equipo.</p>
                <p className="text-sm mt-1">
                  Invita visitadores desde la sección "Visitadores".
                </p>
              </CardContent>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
