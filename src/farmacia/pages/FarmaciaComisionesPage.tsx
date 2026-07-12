// C5b — vista READ-ONLY de las liquidaciones de comisión de la farmacia logueada.
// La farmacia NO cierra ni marca cobrada (eso es admin). Lee liquidaciones_comision por
// PostgREST directo: la RLS (empresa_id = mi_empresa_proveedor()) ya la acota a su empresa,
// por eso NO se pasa empresa_id en el select.
import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { formatearPrecio } from '@/lib/planes-utils'
import { Receipt, Loader2, AlertTriangle } from 'lucide-react'

interface Liquidacion {
  id: string
  anio: number
  mes: number
  total_dispensado: number | string
  comision_total: number | string
  n_dispensaciones: number | string
  monto_sin_contrato: number | string
  estado: string
  metodo_pago: string | null
  referencia_pago: string | null
  cobrada_at: string | null
  cerrada_at: string
}

const MONEDA = 'GTQ'
const fmtQ = (v: number | string) => formatearPrecio(Number(v) || 0, MONEDA)
const MESES = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
const periodoLabel = (mes: number, anio: number) => `${MESES[mes] || mes} ${anio}`
const fmtFecha = (s: string | null) => (s ? new Date(s).toLocaleDateString('es-GT') : '—')
const estadoBadge = (e: string) =>
  e === 'cobrada' ? 'bg-emerald-100 text-emerald-700'
  : e === 'anulada' ? 'bg-gray-100 text-gray-700'
  : 'bg-amber-100 text-amber-700'

export default function FarmaciaComisionesPage() {
  const [liquidaciones, setLiquidaciones] = useState<Liquidacion[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('liquidaciones_comision')
      .select('*')
      .order('anio', { ascending: false })
      .order('mes', { ascending: false })
    if (error) {
      setError(error.message)
      setLiquidaciones([])
    } else {
      setLiquidaciones((data as Liquidacion[]) || [])
    }
    setLoading(false)
  }, [])

  useEffect(() => { cargar() }, [cargar])

  return (
    <div className="space-y-6">
      {/* Encabezado */}
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-lg bg-[#B45309]/10 flex items-center justify-center shrink-0">
          <Receipt className="h-5 w-5 text-[#B45309]" />
        </div>
        <div>
          <h1 className="text-xl font-bold text-[#1a2a3a]">Comisiones</h1>
          <p className="text-sm text-muted-foreground">
            Liquidaciones de comisión que EZPayConnect cerró para tu farmacia. El cobro lo gestiona EZPayConnect.
          </p>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><Loader2 className="h-8 w-8 animate-spin text-[#B45309]" /></div>
      ) : error ? (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          No se pudieron cargar las liquidaciones: {error}
        </div>
      ) : liquidaciones.length === 0 ? (
        <div className="rounded-xl border border-dashed bg-white py-16 text-center">
          <Receipt className="h-12 w-12 mx-auto mb-4 text-gray-300" />
          <p className="text-sm text-muted-foreground">Aún no hay liquidaciones cerradas para tu farmacia.</p>
        </div>
      ) : (
        <div className="rounded-xl border bg-white overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-4 py-3 font-medium">Período</th>
                <th className="px-4 py-3 font-medium">Total dispensado</th>
                <th className="px-4 py-3 font-medium">Comisión</th>
                <th className="px-4 py-3 font-medium">Nº disp.</th>
                <th className="px-4 py-3 font-medium">Estado</th>
                <th className="px-4 py-3 font-medium">Cobro</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {liquidaciones.map((l) => (
                <tr key={l.id} className="align-top">
                  <td className="px-4 py-3 font-medium">{periodoLabel(l.mes, l.anio)}</td>
                  <td className="px-4 py-3">{fmtQ(l.total_dispensado)}</td>
                  <td className="px-4 py-3 font-semibold text-[#B45309]">{fmtQ(l.comision_total)}</td>
                  <td className="px-4 py-3">{Number(l.n_dispensaciones)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-block text-[10px] font-medium px-2 py-0.5 rounded-full ${estadoBadge(l.estado)}`}>{l.estado}</span>
                    {Number(l.monto_sin_contrato) > 0 && (
                      <span className="mt-1 flex items-start gap-1 text-[10px] text-amber-700">
                        <AlertTriangle className="h-3 w-3 mt-0.5 shrink-0" />
                        Incluye ventas sin contrato vigente (no comisionadas): {fmtQ(l.monto_sin_contrato)}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs">
                    {l.estado === 'cobrada'
                      ? <span>{l.metodo_pago || '—'}{l.referencia_pago ? ` (${l.referencia_pago})` : ''} · {fmtFecha(l.cobrada_at)}</span>
                      : <span className="text-muted-foreground">Pendiente de cobro</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
