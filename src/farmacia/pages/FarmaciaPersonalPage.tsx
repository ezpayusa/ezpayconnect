import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from 'sonner'
import { ShieldCheck, Loader2, AlertTriangle, Users, UserPlus, Copy } from 'lucide-react'

interface Miembro {
  id: string
  nombre_completo: string
  email: string
  rol_en_empresa: string
  activo: boolean
}

export default function FarmaciaPersonalPage() {
  const { empresa, cuenta } = useProveedorAuth()
  const { tienePermiso, roles, rolesAsignables, soyAdmin, loading: permLoading } = useFarmaciaPermisos()
  const [miembros, setMiembros] = useState<Miembro[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState<string | null>(null)
  // Invitar (alta): crea la invitación; el invitado la acepta tras confirmar email + login.
  const [invNombre, setInvNombre] = useState('')
  const [invEmail, setInvEmail] = useState('')
  const [invRol, setInvRol] = useState('')
  const [invitando, setInvitando] = useState(false)
  const [linkInvitacion, setLinkInvitacion] = useState<string | null>(null)

  const etiqueta = (rol: string) => roles.find((r) => r.rol === rol)?.label ?? rol

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('id, nombre_completo, email, rol_en_empresa, activo')
      .eq('empresa_id', empresa.id)
      .order('nombre_completo')
    if (error) { toast.error('Error cargando el equipo'); console.error(error) }
    else setMiembros((data || []) as Miembro[])
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => { cargar() }, [cargar])

  // === CABLEADO DE SEGURIDAD: cambio de rol vía asignar_rol_miembro ===
  // La autorización (jerarquía, mismo-empresa, no-tocar-Admin, último-Admin) la
  // impone el RPC SECURITY DEFINER. Aquí solo se invoca y se muestran sus errores.
  // El filtro de opciones (rolesAsignables) es UX; el servidor es la barrera real.
  const cambiarRol = async (cuentaId: string, nuevoRol: string) => {
    setGuardando(cuentaId)
    const { error } = await supabase.rpc('asignar_rol_miembro', {
      p_target_id: cuentaId,
      p_nuevo_rol: nuevoRol,
    })
    setGuardando(null)
    if (error) { toast.error(error.message || 'No se pudo cambiar el rol'); return }
    toast.success('Rol actualizado')
    cargar()
  }

  // === CABLEADO DE SEGURIDAD: alta vía invitación (invitar_miembro_farmacia) ===
  // El RPC fija empresa (la del invitador) y rol, e impone la jerarquía. El alta
  // efectiva la hace el invitado al aceptar autenticado (aceptar_invitacion_proveedor).
  const invitar = async () => {
    if (!invNombre.trim() || !invEmail.trim() || !invRol) {
      toast.error('Completa nombre, email y rol'); return
    }
    setInvitando(true)
    const { data, error } = await supabase.rpc('invitar_miembro_farmacia', {
      p_email: invEmail.trim(),
      p_nombre: invNombre.trim(),
      p_nuevo_rol: invRol,
      p_telefono: null,
    })
    setInvitando(false)
    if (error) { toast.error(error.message || 'No se pudo crear la invitación'); return }
    setLinkInvitacion(`${window.location.origin}/proveedor/registro-visitador?token=${data}`)
    toast.success('Invitación creada. Comparte el link con la persona.')
    setInvNombre(''); setInvEmail(''); setInvRol('')
  }

  if (!permLoading && !tienePermiso('usuarios_roles')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo Admin o Gerente gestionan el personal y los roles.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><ShieldCheck className="w-6 h-6" /> Personal y Roles</h1>
        <p className="text-sm text-muted-foreground">
          Asigna a cada persona el rol que corresponde. {soyAdmin ? 'Como Admin, puedes asignar cualquier rol.' : 'Solo puedes asignar roles por debajo del tuyo.'}
        </p>
      </div>

      {/* Leyenda de roles (catálogo data-driven) */}
      <Card>
        <CardContent className="p-4">
          <p className="text-sm font-semibold mb-3 flex items-center gap-2"><Users className="w-4 h-4" /> Roles de farmacia</p>
          <div className="flex flex-wrap gap-2">
            {roles.map((r) => (
              <Badge key={r.rol} variant="outline" className="text-xs">{r.label ?? r.rol}{r.es_admin ? ' ★' : ''}</Badge>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Lista de miembros + cambio de rol */}
      {loading || permLoading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : (
        <div className="space-y-3">
          {miembros.map((m) => {
            const esYo = m.id === cuenta?.id
            // opciones: roles asignables + (el rol actual del miembro para que se muestre seleccionado)
            const opciones = rolesAsignables.some((r) => r.rol === m.rol_en_empresa)
              ? rolesAsignables
              : [...rolesAsignables, ...roles.filter((r) => r.rol === m.rol_en_empresa)]
            return (
              <Card key={m.id} className={m.activo ? '' : 'opacity-60'}>
                <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-semibold truncate">
                      {m.nombre_completo || '(sin nombre)'} {esYo && <span className="text-xs text-muted-foreground">(tú)</span>}
                    </p>
                    <p className="text-sm text-muted-foreground truncate">{m.email}</p>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-xs text-muted-foreground hidden sm:inline">Rol: <strong>{etiqueta(m.rol_en_empresa)}</strong></span>
                    <select
                      className="h-9 rounded-md border border-input bg-background px-3 text-sm disabled:opacity-50"
                      value={m.rol_en_empresa}
                      disabled={guardando === m.id}
                      onChange={(e) => { if (e.target.value && e.target.value !== m.rol_en_empresa) cambiarRol(m.id, e.target.value) }}
                    >
                      {!opciones.some((r) => r.rol === m.rol_en_empresa) && (
                        <option value={m.rol_en_empresa}>{etiqueta(m.rol_en_empresa)}</option>
                      )}
                      {opciones.map((r) => <option key={r.rol} value={r.rol}>{r.label ?? r.rol}</option>)}
                    </select>
                    {guardando === m.id && <Loader2 className="h-4 w-4 animate-spin" />}
                  </div>
                </CardContent>
              </Card>
            )
          })}
          {miembros.length === 0 && (
            <Card className="bg-gray-50 border-dashed"><CardContent className="p-8 text-center text-muted-foreground">
              <Users className="h-10 w-10 mx-auto mb-3 text-gray-300" /><p>Aún no hay personal.</p>
            </CardContent></Card>
          )}
        </div>
      )}

      {/* Alta de personal nuevo por invitación */}
      <Card>
        <CardContent className="p-4 space-y-3">
          <p className="text-sm font-semibold flex items-center gap-2"><UserPlus className="w-4 h-4" /> Invitar personal</p>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Input placeholder="Nombre completo" value={invNombre} onChange={(e) => setInvNombre(e.target.value)} />
            <Input type="email" placeholder="Email" value={invEmail} onChange={(e) => setInvEmail(e.target.value)} />
            <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={invRol} onChange={(e) => setInvRol(e.target.value)}>
              <option value="">Rol…</option>
              {rolesAsignables.map((r) => <option key={r.rol} value={r.rol}>{r.label ?? r.rol}</option>)}
            </select>
          </div>
          <Button onClick={invitar} disabled={invitando} className="bg-[#B45309] hover:bg-[#92400e]">
            {invitando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <UserPlus className="h-4 w-4 mr-2" />}
            Generar link de invitación
          </Button>
          <p className="text-xs text-muted-foreground">
            La persona abre el link, crea su cuenta con ESE email, lo confirma e inicia sesión: ahí se
            activa con el rol asignado. El rol y la empresa quedan fijados; no los puede cambiar.
          </p>
          {linkInvitacion && (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 space-y-2">
              <p className="text-sm font-medium text-amber-900">¡Invitación creada! Comparte este link:</p>
              <p className="text-xs break-all bg-white rounded p-2 border">{linkInvitacion}</p>
              <Button size="sm" variant="outline" onClick={() => { navigator.clipboard.writeText(linkInvitacion); toast.success('Link copiado') }}>
                <Copy className="h-3.5 w-3.5 mr-1" /> Copiar link
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
