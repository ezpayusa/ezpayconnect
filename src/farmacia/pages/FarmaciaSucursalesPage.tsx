import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from 'sonner'
import { Building2, Loader2, AlertTriangle, Plus, Pencil, Power, Users, Package, X } from 'lucide-react'

interface Sucursal {
  id: number
  nombre: string
  direccion: string | null
  telefono: string | null
  encargado: string | null
  horario: string | null
  activo: boolean
  staff_count: number
  inventario_count: number
}

const VACIA = { id: 0, nombre: '', direccion: '', telefono: '', encargado: '', horario: '' }

export default function FarmaciaSucursalesPage() {
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const [sucursales, setSucursales] = useState<Sucursal[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [editando, setEditando] = useState(false)        // hay form abierto
  const [esNueva, setEsNueva] = useState(true)
  const [form, setForm] = useState<typeof VACIA>({ ...VACIA })

  const puede = tienePermiso('sucursales_gestionar')

  const cargar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('listar_sucursales')
    if (error) { toast.error(error.message || 'Error cargando sucursales') }
    else setSucursales((data || []) as Sucursal[])
    setLoading(false)
  }, [])

  useEffect(() => { if (puede) cargar() }, [puede, cargar])

  const abrirNueva = () => { setForm({ ...VACIA }); setEsNueva(true); setEditando(true) }
  const abrirEditar = (s: Sucursal) => {
    setForm({ id: s.id, nombre: s.nombre, direccion: s.direccion || '', telefono: s.telefono || '', encargado: s.encargado || '', horario: s.horario || '' })
    setEsNueva(false); setEditando(true)
  }
  const cerrar = () => { setEditando(false); setForm({ ...VACIA }) }

  const errMsg = (error: any): string => {
    const code = error?.code
    if (code === '23505') return 'Ya existe una sucursal activa con ese nombre.'
    if (code === '42501') return 'No autorizado para esta sucursal.'
    if (code === 'P0001') return error.message  // bloqueo por staff: trae el conteo
    return error?.message || 'Operación no permitida'
  }

  const guardar = async () => {
    if (!form.nombre.trim() || !form.direccion.trim()) { toast.error('Nombre y dirección son requeridos'); return }
    setGuardando(true)
    const { error } = esNueva
      ? await supabase.rpc('crear_sucursal', {
          p_nombre: form.nombre.trim(), p_direccion: form.direccion.trim(),
          p_telefono: form.telefono.trim() || null, p_encargado: form.encargado.trim() || null, p_horario: form.horario.trim() || null,
        })
      : await supabase.rpc('editar_sucursal', {
          p_sucursal_id: form.id, p_nombre: form.nombre.trim(), p_direccion: form.direccion.trim(),
          p_telefono: form.telefono.trim() || null, p_encargado: form.encargado.trim() || null, p_horario: form.horario.trim() || null,
        })
    setGuardando(false)
    if (error) { toast.error(errMsg(error)); return }
    toast.success(esNueva ? 'Sucursal creada' : 'Sucursal actualizada')
    cerrar(); cargar()
  }

  const toggle = async (s: Sucursal) => {
    if (s.activo) {
      const msg = `¿Desactivar «${s.nombre}»? Su inventario (${s.inventario_count} ítem(s)) deja de ofrecerse para nuevas recetas; las recetas ya ruteadas siguen despachándose.`
        + (s.staff_count > 0 ? `\n\n⚠️ Tiene ${s.staff_count} persona(s) asignada(s): hay que reasignarlas primero.` : '')
      if (!window.confirm(msg)) return
    }
    setGuardando(true)
    const { error } = await supabase.rpc('desactivar_sucursal', { p_sucursal_id: s.id, p_activo: !s.activo })
    setGuardando(false)
    if (error) { toast.error(errMsg(error)); return }
    toast.success(s.activo ? 'Sucursal desactivada' : 'Sucursal reactivada')
    cargar()
  }

  if (!permLoading && !puede) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo Admin o Gerente de farmacia gestionan las sucursales.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><Building2 className="w-6 h-6" /> Sucursales</h1>
          <p className="text-sm text-muted-foreground">Gestioná las sucursales de tu empresa. El médico solo ve las activas al recetar.</p>
        </div>
        {!editando && (
          <Button onClick={abrirNueva} className="bg-[#B45309] hover:bg-[#92400e]"><Plus className="h-4 w-4 mr-2" /> Nueva sucursal</Button>
        )}
      </div>

      {/* Form crear/editar */}
      {editando && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold">{esNueva ? 'Nueva sucursal' : `Editar: ${form.nombre}`}</p>
              <Button size="icon" variant="ghost" onClick={cerrar}><X className="h-4 w-4" /></Button>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <Input placeholder="Nombre *" value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
              <Input placeholder="Dirección *" value={form.direccion} onChange={(e) => setForm({ ...form, direccion: e.target.value })} />
              <Input placeholder="Teléfono" value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} />
              <Input placeholder="Encargado" value={form.encargado} onChange={(e) => setForm({ ...form, encargado: e.target.value })} />
              <Input placeholder="Horario" value={form.horario} onChange={(e) => setForm({ ...form, horario: e.target.value })} />
            </div>
            <div className="flex gap-2">
              <Button onClick={guardar} disabled={guardando} className="bg-[#B45309] hover:bg-[#92400e]">
                {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}{esNueva ? 'Crear' : 'Guardar'}
              </Button>
              <Button variant="outline" onClick={cerrar}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Lista */}
      {loading || permLoading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : sucursales.length === 0 ? (
        <Card className="bg-gray-50 border-dashed"><CardContent className="p-8 text-center text-muted-foreground">
          <Building2 className="h-10 w-10 mx-auto mb-3 text-gray-300" /><p>Aún no hay sucursales. Creá la primera.</p>
        </CardContent></Card>
      ) : (
        <div className="space-y-3">
          {sucursales.map((s) => (
            <Card key={s.id} className={s.activo ? '' : 'opacity-60'}>
              <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-semibold truncate flex items-center gap-2">
                    {s.nombre}
                    {!s.activo && <Badge variant="outline" className="text-xs">Inactiva</Badge>}
                  </p>
                  <p className="text-sm text-muted-foreground truncate">{s.direccion || 'Sin dirección'}{s.encargado ? ` · ${s.encargado}` : ''}{s.telefono ? ` · ${s.telefono}` : ''}</p>
                  <p className="text-xs text-muted-foreground mt-1 flex items-center gap-3">
                    <span className="inline-flex items-center gap-1"><Users className="h-3 w-3" />{s.staff_count}</span>
                    <span className="inline-flex items-center gap-1"><Package className="h-3 w-3" />{s.inventario_count}</span>
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Button size="sm" variant="outline" onClick={() => abrirEditar(s)} disabled={guardando}><Pencil className="h-3.5 w-3.5 mr-1" /> Editar</Button>
                  <Button size="sm" variant={s.activo ? 'outline' : 'default'} onClick={() => toggle(s)} disabled={guardando}
                    className={s.activo ? 'text-red-600 border-red-200 hover:bg-red-50' : 'bg-emerald-600 hover:bg-emerald-700'}>
                    <Power className="h-3.5 w-3.5 mr-1" /> {s.activo ? 'Desactivar' : 'Reactivar'}
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
