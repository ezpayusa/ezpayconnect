import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { ROLES_PROVEEDOR, etiquetaRol } from '@/proveedor/lib/permisos'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from 'sonner'
import { ShieldCheck, Loader2, AlertTriangle, Users, UserPlus, Copy, UserX, UserCheck, Eye } from 'lucide-react'

interface Miembro {
  id: string
  nombre_completo: string
  email: string
  rol_en_empresa: string
  activo: boolean
  audita_chat: boolean
}

export default function EquipoRolesPage() {
  const { empresa, cuenta, puede } = useProveedorAuth()
  const [miembros, setMiembros] = useState<Miembro[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState<string | null>(null)
  // Invitar miembro
  const [invNombre, setInvNombre] = useState('')
  const [invEmail, setInvEmail] = useState('')
  const [invTelefono, setInvTelefono] = useState('')
  const [invRol, setInvRol] = useState('visitador_medico')
  const [invitando, setInvitando] = useState(false)
  const [linkInvitacion, setLinkInvitacion] = useState<string | null>(null)
  const [pendientes, setPendientes] = useState<
    { id: string; nombre_completo: string; email: string; rol: string; token: string; expires_at: string }[]
  >([])

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('id, nombre_completo, email, rol_en_empresa, activo, audita_chat')
      .eq('empresa_id', empresa.id)
      .order('nombre_completo')
    if (error) {
      toast.error('Error cargando el equipo')
      console.error(error)
    } else {
      setMiembros((data || []) as Miembro[])
    }

    const { data: invs } = await supabase
      .from('invitaciones_visitador')
      .select('id, nombre_completo, email, rol, token, expires_at')
      .eq('empresa_id', empresa.id)
      .eq('estado', 'pendiente')
      .order('created_at', { ascending: false })
    setPendientes((invs || []) as typeof pendientes)

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

  const cambiarEstado = async (id: string, activar: boolean, nombre: string) => {
    if (!activar && !window.confirm(`¿Dar de baja a ${nombre}? Perderá el acceso al panel de inmediato.`)) return
    setGuardando(id)
    const { error } = await supabase.rpc('cambiar_estado_miembro_proveedor', { p_id: id, p_activo: activar })
    setGuardando(null)
    if (error) { toast.error(error.message || 'No se pudo actualizar'); return }
    toast.success(activar ? 'Miembro reactivado' : 'Miembro dado de baja')
    cargar()
  }

  const cambiarAuditoria = async (id: string, activar: boolean) => {
    setGuardando(id)
    const { error } = await supabase.rpc('cambiar_auditoria_chat', { p_id: id, p_activo: activar })
    setGuardando(null)
    if (error) { toast.error(error.message || 'No se pudo actualizar'); return }
    toast.success(activar ? 'Auditoría de chat concedida' : 'Auditoría de chat retirada')
    cargar()
  }

  const invitar = async () => {
    if (!invNombre.trim() || !invEmail.trim()) {
      toast.error('Completa nombre y email')
      return
    }
    setInvitando(true)
    const { data, error } = await supabase.rpc('invitar_miembro_proveedor', {
      p_email: invEmail.trim(),
      p_nombre: invNombre.trim(),
      p_rol: invRol,
      p_telefono: invTelefono.trim() || null,
    })
    setInvitando(false)
    if (error) {
      toast.error(error.message || 'No se pudo crear la invitación')
      return
    }
    const url = `${window.location.origin}/proveedor/registro-visitador?token=${data}`
    setLinkInvitacion(url)
    toast.success('Invitación creada. Comparte el link con la persona.')
    setInvNombre('')
    setInvEmail('')
    setInvTelefono('')
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
          Personal y Roles
        </h1>
        <p className="text-sm text-muted-foreground">
          Invita a tu personal y asigna a cada uno el rol que corresponde a su trabajo. Cada rol ve
          y puede hacer únicamente lo de su área (confidencialidad y distribución de tareas).
        </p>
      </div>

      {/* Invitar miembro */}
      <Card>
        <CardContent className="p-4 space-y-3">
          <p className="text-sm font-semibold flex items-center gap-2">
            <UserPlus className="w-4 h-4" /> Invitar personal
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input placeholder="Nombre completo" value={invNombre} onChange={(e) => setInvNombre(e.target.value)} />
            <Input type="email" placeholder="Email" value={invEmail} onChange={(e) => setInvEmail(e.target.value)} />
            <Input placeholder="Teléfono (opcional)" value={invTelefono} onChange={(e) => setInvTelefono(e.target.value)} />
            <select
              className="h-10 rounded-md border border-input bg-background px-3 text-sm"
              value={invRol}
              onChange={(e) => setInvRol(e.target.value)}
            >
              {ROLES_PROVEEDOR.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>
          <Button onClick={invitar} disabled={invitando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
            {invitando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <UserPlus className="h-4 w-4 mr-2" />}
            Generar link de invitación
          </Button>
          {linkInvitacion && (
            <div className="bg-emerald-50 border border-emerald-200 rounded-lg p-3 space-y-2">
              <p className="text-sm font-medium text-emerald-800">¡Invitación creada! Comparte este link:</p>
              <p className="text-xs break-all bg-white rounded p-2 border">{linkInvitacion}</p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    navigator.clipboard.writeText(linkInvitacion)
                    toast.success('Link copiado')
                  }}
                >
                  <Copy className="h-3.5 w-3.5 mr-1" /> Copiar link
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() =>
                    window.open(
                      `https://wa.me/?text=${encodeURIComponent('¡Hola! Te invitamos a unirte al portal de EzPayConnect. Completa tu registro aquí: ' + linkInvitacion)}`,
                      '_blank'
                    )
                  }
                >
                  Enviar por WhatsApp
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

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
                    {!esYo && (
                      <Button
                        size="sm"
                        variant="ghost"
                        className={m.audita_chat ? 'text-indigo-600' : 'text-muted-foreground'}
                        disabled={guardando === m.id}
                        title="Acceso de auditoría de chat (solo lectura de conversaciones de operación)"
                        onClick={() => cambiarAuditoria(m.id, !m.audita_chat)}
                      >
                        <Eye className="h-3.5 w-3.5 mr-1" /> {m.audita_chat ? 'Auditoría ON' : 'Auditoría'}
                      </Button>
                    )}
                    {!esYo && (
                      <Button
                        size="sm"
                        variant="outline"
                        className={m.activo ? 'text-red-600 hover:bg-red-50' : 'text-emerald-600 hover:bg-emerald-50'}
                        disabled={guardando === m.id}
                        onClick={() => cambiarEstado(m.id, !m.activo, m.nombre_completo || m.email)}
                      >
                        {m.activo
                          ? <><UserX className="h-3.5 w-3.5 mr-1" /> Dar de baja</>
                          : <><UserCheck className="h-3.5 w-3.5 mr-1" /> Reactivar</>}
                      </Button>
                    )}
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
                <p className="text-sm mt-1">Usa "Invitar personal" arriba para sumar a tu equipo.</p>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Invitaciones pendientes */}
      {pendientes.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-lg font-semibold">Invitaciones pendientes ({pendientes.length})</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {pendientes.map((inv) => {
              const url = `${window.location.origin}/proveedor/registro-visitador?token=${inv.token}`
              const expirada = new Date(inv.expires_at) < new Date()
              return (
                <Card key={inv.id} className={expirada ? 'opacity-60' : ''}>
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0">
                        <p className="font-medium text-sm truncate">{inv.nombre_completo || '(sin nombre)'}</p>
                        <p className="text-xs text-muted-foreground truncate">{inv.email}</p>
                      </div>
                      <Badge variant="outline" className="text-xs shrink-0">{etiquetaRol(inv.rol)}</Badge>
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs text-muted-foreground">{expirada ? 'Expirada' : 'Pendiente'}</span>
                      {!expirada && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => { navigator.clipboard.writeText(url); toast.success('Link copiado') }}
                        >
                          <Copy className="h-3.5 w-3.5 mr-1" /> Copiar link
                        </Button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
