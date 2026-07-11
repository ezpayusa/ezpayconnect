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
import { Send, Check, X, Loader2, Inbox, DollarSign } from 'lucide-react'

// Front comisión (pieza A) — tab "Contratos de Comisión". Consume las 3 RPCs de A2/A2.5:
// admin_pais: solicitar_contrato_comision + mis contratos (listar_contratos_comision).
// super_admin: bandeja de pendientes con editar-antes-de-aprobar/rechazar (resolver_solicitud_contrato_comision).
// contratos_comision no tiene policy SELECT para admin → todo por RPC DEFINER (gate server-side).

interface Contrato {
  id: string; empresa_id: string; empresa_nombre: string; pais_id: string; pais_nombre: string
  porcentaje_base: number; vigencia_desde: string; vigencia_hasta: string | null; estado: string
  solicitado_por: string; solicitante: string | null; nota_revision: string | null
  resuelto_por: string | null; resuelto_at: string | null; created_at: string
}
// Farmacias del país para el selector. Se cargan por RPC DEFINER (listar_farmacias_pais):
// empresas_proveedoras no da SELECT a admin_pais por RLS → RPC acotada por rol/país.
interface FarmaciaOpt { id: string; nombre_empresa: string }

const estadoBadge = (e: string) =>
  e === 'aprobada' ? 'bg-emerald-100 text-emerald-700'
  : e === 'rechazada' ? 'bg-red-100 text-red-700'
  : 'bg-amber-100 text-amber-700'

const vigenciaTexto = (desde: string, hasta: string | null) => `${desde} → ${hasta ?? '(abierta)'}`

export function ContratosComisionPais({ paisId, esSuper }: { paisId: string | null; esSuper: boolean }) {
  const [contratos, setContratos] = useState<Contrato[]>([])
  const [farmacias, setFarmacias] = useState<FarmaciaOpt[]>([])
  const [loading, setLoading] = useState(true)

  // admin_pais: formulario de solicitud
  const [form, setForm] = useState<{ empresa_id: string; porcentaje: string; vigencia_desde: string; vigencia_hasta: string }>(
    { empresa_id: '', porcentaje: '', vigencia_desde: '', vigencia_hasta: '' })
  const [enviando, setEnviando] = useState(false)

  // super_admin: revisar/editar contrato antes de aprobar
  const [revisar, setRevisar] = useState<Contrato | null>(null)
  const [edit, setEdit] = useState<{ porcentaje_base: string; vigencia_desde: string; vigencia_hasta: string }>(
    { porcentaje_base: '', vigencia_desde: '', vigencia_hasta: '' })
  const [nota, setNota] = useState('')
  const [resolviendo, setResolviendo] = useState(false)

  const cargar = useCallback(async () => {
    setLoading(true)
    try {
      const { data } = await supabase.rpc('listar_contratos_comision', { p_pais_id: paisId })
      setContratos((data as Contrato[]) || [])
      // Selector de farmacias: RPC DEFINER acotada por rol/país (no PostgREST directo).
      const { data: farm } = await supabase.rpc('listar_farmacias_pais', { p_pais_id: paisId })
      setFarmacias((farm as FarmaciaOpt[]) || [])
    } catch (e: any) {
      toast.error('Error cargando contratos: ' + (e.message || ''))
    } finally {
      setLoading(false)
    }
  }, [paisId])

  useEffect(() => { cargar() }, [cargar])

  const enviarSolicitud = async () => {
    if (!form.empresa_id) { toast.error('Selecciona una farmacia'); return }
    const pct = parseFloat(form.porcentaje)
    if (form.porcentaje.trim() === '' || Number.isNaN(pct)) { toast.error('El porcentaje es obligatorio'); return }
    if (pct < 0 || pct > 100) { toast.error('El porcentaje debe estar entre 0 y 100'); return }
    if (!form.vigencia_desde) { toast.error('La vigencia desde es obligatoria'); return }
    setEnviando(true)
    const { error } = await supabase.rpc('solicitar_contrato_comision', {
      p_empresa_id: form.empresa_id,
      p_porcentaje: pct,
      p_vigencia_desde: form.vigencia_desde,
      p_vigencia_hasta: form.vigencia_hasta || null,
    })
    setEnviando(false)
    if (error) { toast.error('Error: ' + error.message); return }
    toast.success('Solicitud enviada. El administrador maestro la revisará.')
    setForm({ empresa_id: '', porcentaje: '', vigencia_desde: '', vigencia_hasta: '' })
    cargar()
  }

  const abrirRevisar = (c: Contrato) => {
    setRevisar(c)
    setEdit({ porcentaje_base: String(c.porcentaje_base), vigencia_desde: c.vigencia_desde, vigencia_hasta: c.vigencia_hasta || '' })
    setNota('')
  }

  const resolver = async (aprobar: boolean) => {
    if (!revisar) return
    // Solo mandamos campos_editados en aprobación (el maestro pudo cambiarlos). En rechazo no aplica.
    let campos: any = null
    if (aprobar) {
      const pct = parseFloat(edit.porcentaje_base)
      if (Number.isNaN(pct) || pct < 0 || pct > 100) { toast.error('El porcentaje debe estar entre 0 y 100'); return }
      if (!edit.vigencia_desde) { toast.error('La vigencia desde es obligatoria'); return }
      campos = { porcentaje_base: pct, vigencia_desde: edit.vigencia_desde, vigencia_hasta: edit.vigencia_hasta || null }
    }
    setResolviendo(true)
    const { data, error } = await supabase.rpc('resolver_solicitud_contrato_comision', {
      p_contrato_id: revisar.id, p_aprobar: aprobar, p_campos_editados: campos, p_nota: nota.trim() || null,
    })
    setResolviendo(false)
    if (error) { toast.error('Error: ' + error.message); return }
    if ((data as any)?.error) { toast.error((data as any).error); return }
    toast.success(aprobar ? 'Contrato aprobado.' : 'Contrato rechazado.')
    setRevisar(null); cargar()
  }

  if (loading) return <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>

  const pendientes = contratos.filter((c) => c.estado === 'pendiente')

  return (
    <div className="space-y-6">
      {/* ===== ADMIN_PAIS: FORMULARIO DE SOLICITUD ===== */}
      {!esSuper && paisId && (
        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base flex items-center gap-2"><DollarSign className="h-4 w-4" /> Solicitar contrato de comisión</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <Label className="text-xs">Farmacia *</Label>
                <Select value={form.empresa_id} onValueChange={(v) => setForm({ ...form, empresa_id: v })}>
                  <SelectTrigger><SelectValue placeholder="Selecciona una farmacia" /></SelectTrigger>
                  <SelectContent>
                    {farmacias.length === 0 && <div className="px-2 py-1.5 text-xs text-muted-foreground">No hay farmacias en este país.</div>}
                    {farmacias.map((f) => <SelectItem key={f.id} value={f.id}>{f.nombre_empresa}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div><Label className="text-xs">Porcentaje base (%) *</Label><Input type="number" min={0} max={100} step="0.01" value={form.porcentaje} onChange={(e) => setForm({ ...form, porcentaje: e.target.value })} placeholder="ej. 5" /></div>
              <div><Label className="text-xs">Vigencia desde *</Label><Input type="date" value={form.vigencia_desde} onChange={(e) => setForm({ ...form, vigencia_desde: e.target.value })} /></div>
              <div><Label className="text-xs">Vigencia hasta (opcional)</Label><Input type="date" value={form.vigencia_hasta} onChange={(e) => setForm({ ...form, vigencia_hasta: e.target.value })} /></div>
            </div>
            <div className="flex justify-end">
              <Button onClick={enviarSolicitud} disabled={enviando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                {enviando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Send className="h-4 w-4 mr-1" />} Enviar solicitud
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ===== CONTRATOS (super: bandeja pendientes + historial | admin_pais: mis contratos) ===== */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <Inbox className="h-4 w-4" /> {esSuper ? `Contratos pendientes (${pendientes.length})` : 'Mis contratos'}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {contratos.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">No hay contratos.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Farmacia</TableHead>
                  {esSuper && <TableHead>País</TableHead>}
                  <TableHead>Porcentaje</TableHead><TableHead>Vigencia</TableHead><TableHead>Estado</TableHead>
                  {esSuper && <TableHead>Solicitante</TableHead>}
                  {esSuper && <TableHead className="text-right">Acción</TableHead>}
                </TableRow></TableHeader>
                <TableBody>
                  {contratos.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell className="text-sm font-medium">{c.empresa_nombre}</TableCell>
                      {esSuper && <TableCell className="text-sm">{c.pais_nombre}</TableCell>}
                      <TableCell className="text-sm">{c.porcentaje_base}%</TableCell>
                      <TableCell className="text-xs">{vigenciaTexto(c.vigencia_desde, c.vigencia_hasta)}</TableCell>
                      <TableCell><Badge className={`text-[10px] ${estadoBadge(c.estado)}`}>{c.estado}</Badge>{c.nota_revision && <span className="block text-[10px] text-muted-foreground mt-0.5">{c.nota_revision}</span>}</TableCell>
                      {esSuper && <TableCell className="text-sm">{c.solicitante || '—'}</TableCell>}
                      {esSuper && <TableCell className="text-right">{c.estado === 'pendiente' && <Button size="sm" variant="outline" onClick={() => abrirRevisar(c)}>Revisar</Button>}</TableCell>}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ===== SUPER: DIÁLOGO DE REVISIÓN (editar antes de aprobar/rechazar) ===== */}
      <Dialog open={!!revisar} onOpenChange={() => setRevisar(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Revisar contrato de comisión</DialogTitle></DialogHeader>
          {revisar && (
            <div className="space-y-3">
              <p className="text-xs text-muted-foreground">Farmacia: {revisar.empresa_nombre} · País: {revisar.pais_nombre} · Solicitó: {revisar.solicitante || '—'}. Podés editar los campos antes de aprobar.</p>
              <div className="grid grid-cols-2 gap-3">
                <div><Label className="text-xs">Porcentaje base (%)</Label><Input type="number" min={0} max={100} step="0.01" value={edit.porcentaje_base} onChange={(e) => setEdit({ ...edit, porcentaje_base: e.target.value })} /></div>
                <div><Label className="text-xs">Vigencia desde</Label><Input type="date" value={edit.vigencia_desde} onChange={(e) => setEdit({ ...edit, vigencia_desde: e.target.value })} /></div>
              </div>
              <div><Label className="text-xs">Vigencia hasta (opcional)</Label><Input type="date" value={edit.vigencia_hasta} onChange={(e) => setEdit({ ...edit, vigencia_hasta: e.target.value })} /></div>
              <div><Label className="text-xs">Nota de revisión (opcional)</Label><Input value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Motivo del rechazo o comentario" /></div>
              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => resolver(false)} disabled={resolviendo} className="text-red-600">
                  <X className="h-4 w-4 mr-1" /> Rechazar
                </Button>
                <Button onClick={() => resolver(true)} disabled={resolviendo} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  {resolviendo ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Check className="h-4 w-4 mr-1" />} Aprobar
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
