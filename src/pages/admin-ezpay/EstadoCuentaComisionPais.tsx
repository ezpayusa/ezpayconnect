import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { formatearPrecio } from '@/lib/planes-utils'
import { DollarSign, Calculator, AlertTriangle, Loader2, Receipt } from 'lucide-react'

// UI de la pieza B — tab "Estado de Cuenta". Llama la RPC read-only liquidar_comision
// (super_admin cualquiera / admin_pais solo su país; la RPC lo restringe server-side).
// El selector de farmacia se puebla por listar_farmacias_pais (mismo patrón que Contratos).

interface FarmaciaOpt { id: string; nombre_empresa: string }
interface Resumen {
  total_dispensado_periodo: number | string
  comision_total: number | string
  n_dispensaciones: number | string
  n_sin_contrato: number | string
  monto_sin_contrato: number | string
}

// La liquidación es país-scoped; Guatemala usa GTQ (ver formatearPrecio para el resto).
const MONEDA = 'GTQ'
const fmtQ = (v: number | string) => formatearPrecio(Number(v) || 0, MONEDA)
const fmtFecha = (d: Date) => d.toISOString().slice(0, 10)

export function EstadoCuentaComisionPais({ paisId, esSuper }: { paisId: string | null; esSuper: boolean }) {
  const [farmacias, setFarmacias] = useState<FarmaciaOpt[]>([])
  const [empresaId, setEmpresaId] = useState('')
  // Período por default: primer día del mes actual → hoy.
  const hoy = new Date()
  const [desde, setDesde] = useState(fmtFecha(new Date(hoy.getFullYear(), hoy.getMonth(), 1)))
  const [hasta, setHasta] = useState(fmtFecha(hoy))
  const [resumen, setResumen] = useState<Resumen | null>(null)
  const [calculando, setCalculando] = useState(false)

  const cargarFarmacias = useCallback(async () => {
    const { data } = await supabase.rpc('listar_farmacias_pais', { p_pais_id: paisId })
    setFarmacias((data as FarmaciaOpt[]) || [])
  }, [paisId])

  useEffect(() => { cargarFarmacias() }, [cargarFarmacias])

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

      {/* ===== Resultado ===== */}
      {!resumen ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            Seleccioná una farmacia y un período, y presioná <strong>Calcular</strong>.
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Resumen del período</CardTitle></CardHeader>
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
          </CardContent>
        </Card>
      )}
    </div>
  )
}
