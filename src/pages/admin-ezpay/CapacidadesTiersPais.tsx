import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Layers, Package, Send, Check, X, Loader2, Inbox } from 'lucide-react'

// Front B admin_pais — sección "Capacidades y Tiers". Consume las 8 RPCs de la mig 227.
// admin_pais: solicitar + mis solicitudes + activo + techo (read-only). super_admin: bandeja de
// pendientes con editar-antes-de-aprobar/rechazar + techo editable. Contenido derivado por RPC (gate server-side).

interface Solicitud {
  id: string; tipo: string; pais_id: string; pais_nombre: string; solicitante: string | null;
  codigo: string; nombre: string; descripcion: string | null; orden: number; capacidades: string[] | null;
  estado: string; nota_revision: string | null; created_at: string;
}
interface CapItem { codigo: string; nombre: string; descripcion: string | null; orden: number; activo: boolean; es_global: boolean }
interface TierItem { id: string; codigo: string; nombre: string; descripcion: string | null; orden: number; activo: boolean; es_global: boolean; capacidades: string[] }

const estadoBadge = (e: string) =>
  e === 'aprobada' ? 'bg-emerald-100 text-emerald-700'
  : e === 'rechazada' ? 'bg-red-100 text-red-700'
  : 'bg-amber-100 text-amber-700'

export function CapacidadesTiersPais({ paisId, esSuper }: { paisId: string | null; esSuper: boolean }) {
  const [solicitudes, setSolicitudes] = useState<Solicitud[]>([])
  const [capacidades, setCapacidades] = useState<CapItem[]>([])
  const [tiers, setTiers] = useState<TierItem[]>([])
  const [techo, setTecho] = useState<number | null>(null)
  const [paisNombre, setPaisNombre] = useState('')
  const [loading, setLoading] = useState(true)

  // admin_pais: formulario de solicitud
  const [form, setForm] = useState<{ tipo: 'capacidad' | 'tier'; codigo: string; nombre: string; descripcion: string; orden: number; capacidades: string[] }>(
    { tipo: 'capacidad', codigo: '', nombre: '', descripcion: '', orden: 100, capacidades: [] })
  const [enviando, setEnviando] = useState(false)

  // super_admin: revisar/editar solicitud
  const [revisar, setRevisar] = useState<Solicitud | null>(null)
  const [edit, setEdit] = useState<{ codigo: string; nombre: string; descripcion: string; orden: number; capacidades: string[] }>(
    { codigo: '', nombre: '', descripcion: '', orden: 100, capacidades: [] })
  const [nota, setNota] = useState('')
  const [resolviendo, setResolviendo] = useState(false)

  // super_admin: techo editable
  const [techoEdit, setTechoEdit] = useState('')
  const [guardandoTecho, setGuardandoTecho] = useState(false)

  const cargar = useCallback(async () => {
    setLoading(true)
    try {
      const { data: sol } = await supabase.rpc('listar_solicitudes_capacidades_pais', { p_pais_id: paisId })
      setSolicitudes((sol as Solicitud[]) || [])
      if (paisId) {
        const [caps, trs, res] = await Promise.all([
          supabase.rpc('listar_capacidades_pais', { p_pais_id: paisId }),
          supabase.rpc('listar_tiers_pais', { p_pais_id: paisId }),
          supabase.rpc('obtener_resumen_pais', { p_pais_id: paisId }),
        ])
        setCapacidades((caps.data as CapItem[]) || [])
        setTiers((trs.data as TierItem[]) || [])
        const techoVal = (res.data as any)?.techo_cortesia_visitas ?? null
        setTecho(techoVal)
        setPaisNombre((res.data as any)?.nombre || '')
        setTechoEdit(techoVal != null ? String(techoVal) : '')
      } else {
        setCapacidades([]); setTiers([]); setTecho(null); setPaisNombre('')
      }
    } catch (e: any) {
      toast.error('Error cargando capacidades: ' + (e.message || ''))
    } finally {
      setLoading(false)
    }
  }, [paisId])

  useEffect(() => { cargar() }, [cargar])

  const enviarSolicitud = async () => {
    if (!paisId) { toast.error('Selecciona un país'); return }
    if (!form.codigo.trim() || !form.nombre.trim()) { toast.error('Código y nombre son obligatorios'); return }
    setEnviando(true)
    const rpc = form.tipo === 'capacidad' ? 'solicitar_capacidad_pais' : 'solicitar_tier_pais'
    const params: any = { p_pais_id: paisId, p_codigo: form.codigo.trim(), p_nombre: form.nombre.trim(), p_descripcion: form.descripcion.trim() || null, p_orden: form.orden }
    if (form.tipo === 'tier') params.p_capacidades = form.capacidades.length ? form.capacidades : null
    const { error } = await supabase.rpc(rpc, params)
    setEnviando(false)
    if (error) { toast.error('Error: ' + error.message); return }
    toast.success('Solicitud enviada. El administrador maestro la revisará.')
    setForm({ tipo: 'capacidad', codigo: '', nombre: '', descripcion: '', orden: 100, capacidades: [] })
    cargar()
  }

  const abrirRevisar = (s: Solicitud) => {
    setRevisar(s)
    setEdit({ codigo: s.codigo, nombre: s.nombre, descripcion: s.descripcion || '', orden: s.orden, capacidades: s.capacidades || [] })
    setNota('')
  }

  const resolver = async (aprobar: boolean) => {
    if (!revisar) return
    setResolviendo(true)
    // Solo mandamos campos_editados en aprobación (el maestro pudo cambiarlos). En rechazo no aplica.
    let campos: any = null
    if (aprobar) {
      campos = { codigo: edit.codigo.trim(), nombre: edit.nombre.trim(), descripcion: edit.descripcion.trim() || null, orden: edit.orden }
      if (revisar.tipo === 'tier') campos.capacidades = edit.capacidades
    }
    const { data, error } = await supabase.rpc('resolver_solicitud_capacidad_pais', {
      p_solicitud_id: revisar.id, p_aprobar: aprobar, p_campos_editados: campos, p_nota: nota.trim() || null,
    })
    setResolviendo(false)
    if (error) { toast.error('Error: ' + error.message); return }
    if ((data as any)?.error) { toast.error((data as any).error); return } // ej. código duplicado → sigue pendiente
    toast.success(aprobar ? 'Solicitud aprobada y creada.' : 'Solicitud rechazada.')
    setRevisar(null); cargar()
  }

  const guardarTecho = async () => {
    if (!paisId) return
    setGuardandoTecho(true)
    const val = techoEdit.trim() === '' ? null : parseInt(techoEdit.trim(), 10)
    const { data, error } = await supabase.rpc('actualizar_techo_cortesia_pais', { p_pais_id: paisId, p_valor: val })
    setGuardandoTecho(false)
    if (error) { toast.error('Error: ' + error.message); return }
    if ((data as any)?.error) { toast.error((data as any).error); return }
    toast.success('Techo de cortesía actualizado.')
    cargar()
  }

  const toggleCap = (arr: string[], cod: string, set: (v: string[]) => void) =>
    set(arr.includes(cod) ? arr.filter((c) => c !== cod) : [...arr, cod])

  if (loading) return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>

  const pendientes = solicitudes.filter((s) => s.estado === 'pendiente')

  return (
    <div className="space-y-6">
      {/* ===== TECHO DE CORTESÍA ===== */}
      {paisId && (
        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Techo de cortesía de visitas{paisNombre ? ` · ${paisNombre}` : ''}</CardTitle></CardHeader>
          <CardContent>
            {esSuper ? (
              <div className="flex items-end gap-3">
                <div className="w-40">
                  <Label className="text-xs">Techo (vacío = sin tope)</Label>
                  <Input type="number" min={1} value={techoEdit} onChange={(e) => setTechoEdit(e.target.value)} placeholder="Sin configurar" />
                </div>
                <Button onClick={guardarTecho} disabled={guardandoTecho} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  {guardandoTecho ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Guardar techo'}
                </Button>
              </div>
            ) : (
              <p className="text-sm">Techo actual: <strong>{techo != null ? `${techo} visitas` : 'sin configurar'}</strong> <span className="text-muted-foreground">(lo define el administrador maestro)</span></p>
            )}
          </CardContent>
        </Card>
      )}

      {/* ===== ADMIN_PAIS: FORMULARIO DE SOLICITUD ===== */}
      {!esSuper && paisId && (
        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Solicitar capacidad o tier</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <Label className="text-xs">Tipo</Label>
                <Select value={form.tipo} onValueChange={(v) => setForm({ ...form, tipo: v as 'capacidad' | 'tier' })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="capacidad">Capacidad</SelectItem>
                    <SelectItem value="tier">Tier</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div><Label className="text-xs">Orden</Label><Input type="number" value={form.orden} onChange={(e) => setForm({ ...form, orden: parseInt(e.target.value || '100', 10) })} /></div>
              <div><Label className="text-xs">Código *</Label><Input value={form.codigo} onChange={(e) => setForm({ ...form, codigo: e.target.value })} placeholder="ej. cap_reportes" /></div>
              <div><Label className="text-xs">Nombre *</Label><Input value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="ej. Reportes avanzados" /></div>
            </div>
            <div><Label className="text-xs">Descripción</Label><Input value={form.descripcion} onChange={(e) => setForm({ ...form, descripcion: e.target.value })} /></div>
            {form.tipo === 'tier' && (
              <div>
                <Label className="text-xs">Capacidades a incluir (de tu país o globales)</Label>
                <div className="flex flex-wrap gap-2 mt-1">
                  {capacidades.length === 0 && <span className="text-xs text-muted-foreground">No hay capacidades activas todavía.</span>}
                  {capacidades.map((c) => (
                    <button key={c.codigo} type="button" onClick={() => toggleCap(form.capacidades, c.codigo, (v) => setForm({ ...form, capacidades: v }))}
                      className={`text-xs px-2 py-1 rounded border ${form.capacidades.includes(c.codigo) ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]' : 'bg-gray-50 border-gray-200'}`}>
                      {c.codigo}{c.es_global ? ' (global)' : ''}
                    </button>
                  ))}
                </div>
              </div>
            )}
            <div className="flex justify-end">
              <Button onClick={enviarSolicitud} disabled={enviando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                {enviando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Send className="h-4 w-4 mr-1" />} Enviar solicitud
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ===== SOLICITUDES (super: bandeja pendientes + historial | admin_pais: mis solicitudes) ===== */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <Inbox className="h-4 w-4" /> {esSuper ? `Solicitudes pendientes (${pendientes.length})` : 'Mis solicitudes'}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {(esSuper ? solicitudes : solicitudes).length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">No hay solicitudes.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Tipo</TableHead><TableHead>Código</TableHead><TableHead>Nombre</TableHead>
                  {esSuper && <TableHead>País</TableHead>}<TableHead>Estado</TableHead>
                  {esSuper && <TableHead className="text-right">Acción</TableHead>}
                </TableRow></TableHeader>
                <TableBody>
                  {solicitudes.map((s) => (
                    <TableRow key={s.id}>
                      <TableCell><Badge variant="outline" className="text-[10px]">{s.tipo === 'tier' ? <Layers className="h-3 w-3 mr-1" /> : <Package className="h-3 w-3 mr-1" />}{s.tipo}</Badge></TableCell>
                      <TableCell className="font-mono text-xs">{s.codigo}</TableCell>
                      <TableCell className="text-sm">{s.nombre}</TableCell>
                      {esSuper && <TableCell className="text-sm">{s.pais_nombre}</TableCell>}
                      <TableCell><Badge className={`text-[10px] ${estadoBadge(s.estado)}`}>{s.estado}</Badge>{s.nota_revision && <span className="block text-[10px] text-muted-foreground mt-0.5">{s.nota_revision}</span>}</TableCell>
                      {esSuper && <TableCell className="text-right">{s.estado === 'pendiente' && <Button size="sm" variant="outline" onClick={() => abrirRevisar(s)}>Revisar</Button>}</TableCell>}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ===== ACTIVO EN EL PAÍS (capacidades + tiers ya creados) ===== */}
      {paisId && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <Card>
            <CardHeader className="pb-3"><CardTitle className="text-base">Capacidades activas</CardTitle></CardHeader>
            <CardContent>
              {capacidades.length === 0 ? <p className="text-sm text-muted-foreground">Ninguna.</p> : (
                <ul className="space-y-1 text-sm">
                  {capacidades.map((c) => <li key={c.codigo} className="flex items-center justify-between"><span><span className="font-mono text-xs">{c.codigo}</span> · {c.nombre}</span>{c.es_global && <Badge variant="outline" className="text-[10px]">global</Badge>}</li>)}
                </ul>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-3"><CardTitle className="text-base">Tiers activos</CardTitle></CardHeader>
            <CardContent>
              {tiers.length === 0 ? <p className="text-sm text-muted-foreground">Ninguno.</p> : (
                <ul className="space-y-1 text-sm">
                  {tiers.map((t) => <li key={t.id}><span className="font-mono text-xs">{t.codigo}</span> · {t.nombre} {t.es_global && <Badge variant="outline" className="text-[10px]">global</Badge>}{t.capacidades.length > 0 && <span className="block text-[10px] text-muted-foreground">caps: {t.capacidades.join(', ')}</span>}</li>)}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* ===== SUPER: DIÁLOGO DE REVISIÓN (editar antes de aprobar/rechazar) ===== */}
      <Dialog open={!!revisar} onOpenChange={() => setRevisar(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Revisar solicitud de {revisar?.tipo}</DialogTitle></DialogHeader>
          {revisar && (
            <div className="space-y-3">
              <p className="text-xs text-muted-foreground">País: {revisar.pais_nombre} · Solicitó: {revisar.solicitante || '—'}. Podés editar los campos antes de aprobar.</p>
              <div className="grid grid-cols-2 gap-3">
                <div><Label className="text-xs">Código</Label><Input value={edit.codigo} onChange={(e) => setEdit({ ...edit, codigo: e.target.value })} /></div>
                <div><Label className="text-xs">Orden</Label><Input type="number" value={edit.orden} onChange={(e) => setEdit({ ...edit, orden: parseInt(e.target.value || '100', 10) })} /></div>
              </div>
              <div><Label className="text-xs">Nombre</Label><Input value={edit.nombre} onChange={(e) => setEdit({ ...edit, nombre: e.target.value })} /></div>
              <div><Label className="text-xs">Descripción</Label><Input value={edit.descripcion} onChange={(e) => setEdit({ ...edit, descripcion: e.target.value })} /></div>
              {revisar.tipo === 'tier' && (
                <div>
                  <Label className="text-xs">Capacidades del tier</Label>
                  <div className="flex flex-wrap gap-2 mt-1">
                    {capacidades.map((c) => (
                      <button key={c.codigo} type="button" onClick={() => toggleCap(edit.capacidades, c.codigo, (v) => setEdit({ ...edit, capacidades: v }))}
                        className={`text-xs px-2 py-1 rounded border ${edit.capacidades.includes(c.codigo) ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]' : 'bg-gray-50 border-gray-200'}`}>{c.codigo}</button>
                    ))}
                  </div>
                </div>
              )}
              <div><Label className="text-xs">Nota de revisión (opcional)</Label><Input value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Motivo del rechazo o comentario" /></div>
              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => resolver(false)} disabled={resolviendo} className="text-red-600">
                  <X className="h-4 w-4 mr-1" /> Rechazar
                </Button>
                <Button onClick={() => resolver(true)} disabled={resolviendo} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  {resolviendo ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Check className="h-4 w-4 mr-1" />} Aprobar y crear
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
