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
import { formatearPrecio } from '@/lib/planes-utils'
import { DollarSign, Calculator, AlertTriangle, Loader2, Receipt, Lock, CheckCircle2 } from 'lucide-react'

// UI de la pieza B+C — tab "Estado de Cuenta". Cálculo en vivo (liquidar_comision) +
// capa de liquidación: cerrar mes (cerrar_liquidacion), listar (listar_liquidaciones) y
// marcar cobrada (marcar_liquidacion_cobrada). Solo admin (las RPCs lo restringen server-side).

interface FarmaciaOpt { id: string; nombre_empresa: string }
interface Resumen {
  total_dispensado_periodo: number | string
  comision_total: number | string
  n_dispensaciones: number | string
  n_sin_contrato: number | string
  monto_sin_contrato: number | string
}
interface Liquidacion {
  id: string; empresa_id: string; empresa_nombre: string; pais_id: string; pais_nombre: string
  anio: number; mes: number; total_dispensado: number | string; comision_total: number | string
  n_dispensaciones: number | string; monto_sin_contrato: number | string; estado: string
  metodo_pago: string | null; referencia_pago: string | null; cobrada_at: string | null; cerrada_at: string
}

// La liquidación es país-scoped; Guatemala usa GTQ (ver formatearPrecio para el resto).
const MONEDA = 'GTQ'
const fmtQ = (v: number | string) => formatearPrecio(Number(v) || 0, MONEDA)
const fmtFecha = (d: Date) => d.toISOString().slice(0, 10)
const MESES = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
const periodoLabel = (mes: number, anio: number) => `${MESES[mes] || mes} ${anio}`
const estadoBadge = (e: string) =>
  e === 'cobrada' ? 'bg-emerald-100 text-emerald-700'
  : e === 'anulada' ? 'bg-gray-100 text-gray-700'
  : 'bg-amber-100 text-amber-700'

export function EstadoCuentaComisionPais({ paisId, esSuper }: { paisId: string | null; esSuper: boolean }) {
  const [farmacias, setFarmacias] = useState<FarmaciaOpt[]>([])
  const [empresaId, setEmpresaId] = useState('')
  // Período por default: primer día del mes actual → hoy.
  const hoy = new Date()
  const [desde, setDesde] = useState(fmtFecha(new Date(hoy.getFullYear(), hoy.getMonth(), 1)))
  const [hasta, setHasta] = useState(fmtFecha(hoy))
  const [resumen, setResumen] = useState<Resumen | null>(null)
  const [calculando, setCalculando] = useState(false)

  // Capa de liquidación
  const [liquidaciones, setLiquidaciones] = useState<Liquidacion[]>([])
  const [loadingLiq, setLoadingLiq] = useState(false)
  const [confirmCerrar, setConfirmCerrar] = useState(false)
  const [cerrando, setCerrando] = useState(false)
  const [cobrar, setCobrar] = useState<Liquidacion | null>(null)
  const [cobroMetodo, setCobroMetodo] = useState('')
  const [cobroRef, setCobroRef] = useState('')
  const [cobrando, setCobrando] = useState(false)

  // El mes a cerrar sale del "desde" (solo tiene sentido cerrar un mes completo).
  const anioSel = Number(desde.slice(0, 4))
  const mesSel = Number(desde.slice(5, 7))
  const mesLabel = periodoLabel(mesSel, anioSel)

  const cargarFarmacias = useCallback(async () => {
    const { data } = await supabase.rpc('listar_farmacias_pais', { p_pais_id: paisId })
    setFarmacias((data as FarmaciaOpt[]) || [])
  }, [paisId])

  const cargarLiquidaciones = useCallback(async () => {
    setLoadingLiq(true)
    const { data } = await supabase.rpc('listar_liquidaciones', { p_pais_id: paisId, p_empresa_id: empresaId || null })
    setLiquidaciones((data as Liquidacion[]) || [])
    setLoadingLiq(false)
  }, [paisId, empresaId])

  useEffect(() => { cargarFarmacias() }, [cargarFarmacias])
  useEffect(() => { cargarLiquidaciones() }, [cargarLiquidaciones])

  const calcular = async () => {
    if (!empresaId) { toast.error('Selecciona una farmacia'); return }
    if (!desde || !hasta) { toast.error('Selecciona el período (desde / hasta)'); return }
    if (desde > hasta) { toast.error('El "desde" no puede ser posterior al "hasta"'); return }
    setCalculando(true)
    const { data, error } = await supabase.rpc('liquidar_comision', {
      p_empresa_id: empresaId, p_desde: desde, p_hasta: hasta,
    })
    setCalculando(false)
    if (error) { toast.error('Error: ' + error.message); return }
    const fila = (data as Resumen[])?.[0] || null
    setResumen(fila)
  }

  const cerrarPeriodo = async () => {
    if (!empresaId) { toast.error('Selecciona una farmacia'); return }
    setCerrando(true)
    const { error } = await supabase.rpc('cerrar_liquidacion', { p_empresa_id: empresaId, p_anio: anioSel, p_mes: mesSel })
    setCerrando(false)
    setConfirmCerrar(false)
    if (error) { toast.error('No se pudo cerrar: ' + error.message); return }
    toast.success(`Liquidación de ${mesLabel} cerrada.`)
    cargarLiquidaciones()
  }

  const confirmarCobro = async () => {
    if (!cobrar) return
    if (!cobroMetodo.trim()) { toast.error('El método de pago es obligatorio'); return }
    setCobrando(true)
    const { error } = await supabase.rpc('marcar_liquidacion_cobrada', {
      p_liquidacion_id: cobrar.id, p_metodo_pago: cobroMetodo.trim(), p_referencia: cobroRef.trim() || null,
    })
    setCobrando(false)
    if (error) { toast.error('Error: ' + error.message); return }
    toast.success('Liquidación marcada como cobrada.')
    setCobrar(null); setCobroMetodo(''); setCobroRef('')
    cargarLiquidaciones()
  }

  const nSinContrato = Number(resumen?.n_sin_contrato ?? 0)

  return (
    <div className="space-y-6">
      {/* ===== Selectores ===== */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2"><Receipt className="h-4 w-4" /> Estado de cuenta de comisión</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <Label className="text-xs">Farmacia</Label>
              <Select value={empresaId} onValueChange={setEmpresaId}>
                <SelectTrigger><SelectValue placeholder="Selecciona una farmacia" /></SelectTrigger>
                <SelectContent>
                  {farmacias.length === 0 && <div className="px-2 py-1.5 text-xs text-muted-foreground">No hay farmacias en este país.</div>}
                  {farmacias.map((f) => <SelectItem key={f.id} value={f.id}>{f.nombre_empresa}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div><Label className="text-xs">Desde</Label><Input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></div>
            <div><Label className="text-xs">Hasta</Label><Input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></div>
          </div>
          <div className="flex justify-end">
            <Button onClick={calcular} disabled={calculando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              {calculando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Calculator className="h-4 w-4 mr-1" />} Calcular
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* ===== Resultado del cálculo en vivo ===== */}
      {!resumen ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            Seleccioná una farmacia y un período, y presioná <strong>Calcular</strong>.
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Resumen del período (en vivo)</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            {/* Comisión total — destacado (lo que la farmacia debe) */}
            <div className="rounded-lg border bg-[#1E5C8E]/5 p-4 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <DollarSign className="h-5 w-5 text-[#1E5C8E]" />
                <span className="text-sm font-medium">Comisión a cobrar</span>
              </div>
              <span className="text-2xl font-bold text-[#1E5C8E]">{fmtQ(resumen.comision_total)}</span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="bg-slate-50 p-3 rounded-lg text-center">
                <p className="text-xs text-muted-foreground">Total dispensado</p>
                <p className="text-lg font-bold">{fmtQ(resumen.total_dispensado_periodo)}</p>
              </div>
              <div className="bg-slate-50 p-3 rounded-lg text-center">
                <p className="text-xs text-muted-foreground">Dispensaciones</p>
                <p className="text-lg font-bold">{Number(resumen.n_dispensaciones)}</p>
              </div>
              <div className="bg-slate-50 p-3 rounded-lg text-center">
                <p className="text-xs text-muted-foreground">Sin contrato</p>
                <p className="text-lg font-bold">{nSinContrato}</p>
              </div>
            </div>

            {/* Transparencia (pieza B): ventas sin contrato vigente en el período — no se esconden */}
            {nSinContrato > 0 && (
              <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                <span>
                  {nSinContrato} dispensaci{nSinContrato === 1 ? 'ón' : 'ones'} ({fmtQ(resumen.monto_sin_contrato)}) sin
                  contrato vigente en el período — no comisionadas.
                </span>
              </div>
            )}

            {/* Cerrar período: congela el mes del "desde" */}
            <div className="flex items-center justify-between pt-3 border-t">
              <span className="text-xs text-muted-foreground">Cerrar congela la comisión del mes del «desde» ({mesLabel}).</span>
              <Button variant="outline" onClick={() => setConfirmCerrar(true)} disabled={!empresaId}>
                <Lock className="h-4 w-4 mr-1" /> Cerrar {mesLabel}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ===== Tabla de liquidaciones cerradas ===== */}
      <Card>
        <CardHeader className="pb-3"><CardTitle className="text-base">Liquidaciones cerradas</CardTitle></CardHeader>
        <CardContent>
          {loadingLiq ? (
            <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
          ) : liquidaciones.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">No hay liquidaciones cerradas todavía.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Período</TableHead><TableHead>Total dispensado</TableHead><TableHead>Comisión</TableHead>
                  <TableHead>Nº disp.</TableHead><TableHead>Estado</TableHead><TableHead>Método</TableHead>
                  <TableHead>Cobrada</TableHead><TableHead className="text-right">Acción</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {liquidaciones.map((l) => (
                    <TableRow key={l.id}>
                      <TableCell className="text-sm font-medium">{periodoLabel(l.mes, l.anio)}</TableCell>
                      <TableCell className="text-sm">{fmtQ(l.total_dispensado)}</TableCell>
                      <TableCell className="text-sm font-semibold">{fmtQ(l.comision_total)}</TableCell>
                      <TableCell className="text-sm">{Number(l.n_dispensaciones)}</TableCell>
                      <TableCell><Badge className={`text-[10px] ${estadoBadge(l.estado)}`}>{l.estado}</Badge></TableCell>
                      <TableCell className="text-xs">{l.metodo_pago || '—'}{l.referencia_pago ? ` (${l.referencia_pago})` : ''}</TableCell>
                      <TableCell className="text-xs">{l.cobrada_at ? new Date(l.cobrada_at).toLocaleDateString('es-GT') : '—'}</TableCell>
                      <TableCell className="text-right">
                        {l.estado === 'pendiente' && (
                          <Button size="sm" variant="outline" onClick={() => { setCobrar(l); setCobroMetodo(''); setCobroRef('') }}>
                            <CheckCircle2 className="h-4 w-4 mr-1" /> Marcar cobrada
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ===== Dialog confirmar cierre ===== */}
      <Dialog open={confirmCerrar} onOpenChange={setConfirmCerrar}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>¿Cerrar {mesLabel}?</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">Esto congela la comisión del mes y no se puede recalcular.</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setConfirmCerrar(false)}>Cancelar</Button>
            <Button onClick={cerrarPeriodo} disabled={cerrando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              {cerrando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Lock className="h-4 w-4 mr-1" />} Cerrar
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ===== Dialog marcar cobrada ===== */}
      <Dialog open={!!cobrar} onOpenChange={() => setCobrar(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Marcar cobrada — {cobrar ? periodoLabel(cobrar.mes, cobrar.anio) : ''}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            {cobrar && <p className="text-xs text-muted-foreground">{cobrar.empresa_nombre} · comisión {fmtQ(cobrar.comision_total)}</p>}
            <div><Label className="text-xs">Método de pago *</Label><Input value={cobroMetodo} onChange={(e) => setCobroMetodo(e.target.value)} placeholder="cheque / transferencia / depósito" /></div>
            <div><Label className="text-xs">Referencia (opcional)</Label><Input value={cobroRef} onChange={(e) => setCobroRef(e.target.value)} placeholder="Nº cheque / referencia de depósito" /></div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setCobrar(null)}>Cancelar</Button>
              <Button onClick={confirmarCobro} disabled={cobrando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                {cobrando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />} Confirmar cobro
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
