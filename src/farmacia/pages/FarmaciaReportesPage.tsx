import { useState, useCallback, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { BarChart3, DollarSign, Pill, Loader2, AlertCircle } from 'lucide-react'

// Reportes por sucursal (Frente C.1). Consume los RPC SECURITY DEFINER
// stats_finanzas_sucursal / stats_recetas_sucursal: aislados por empresa,
// sucursal-aware y agregados (finanzas) / k-anónimos (recetas) en el servidor.
// El gating por permiso aquí es SOLO cosmético: cada RPC RAISE si falta el permiso.

interface FinanzasRow {
  sucursal_id: number
  sucursal: string
  dispensaciones: number
  total_dispensado: number
  items: number
}
interface RecetasRow {
  sucursal_id: number
  sucursal: string
  medicamento: string
  veces_dispensado: number
  cantidad_total: number
}

function isoHaceDias(dias: number): string {
  const d = new Date()
  d.setDate(d.getDate() - dias)
  return d.toISOString().split('T')[0]
}
const hoyIso = () => new Date().toISOString().split('T')[0]

const nf = new Intl.NumberFormat('es-GT')

export default function FarmaciaReportesPage() {
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const verFinanzas = tienePermiso('finanzas_reportes')
  const verRecetas = tienePermiso('recetas_reportes')

  const [desde, setDesde] = useState(isoHaceDias(30))
  const [hasta, setHasta] = useState(hoyIso())
  const [finanzas, setFinanzas] = useState<FinanzasRow[]>([])
  const [recetas, setRecetas] = useState<RecetasRow[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    if (!verFinanzas && !verRecetas) return
    setLoading(true)
    setError(null)
    try {
      const tareas: Promise<unknown>[] = []
      if (verFinanzas) {
        tareas.push(
          supabase
            .rpc('stats_finanzas_sucursal', { p_desde: desde, p_hasta: hasta, p_sucursal_id: null })
            .then(({ data, error }) => {
              if (error) throw error
              setFinanzas((data as FinanzasRow[]) || [])
            }),
        )
      }
      if (verRecetas) {
        tareas.push(
          supabase
            .rpc('stats_recetas_sucursal', { p_desde: desde, p_hasta: hasta, p_sucursal_id: null })
            .then(({ data, error }) => {
              if (error) throw error
              setRecetas((data as RecetasRow[]) || [])
            }),
        )
      }
      await Promise.all(tareas)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los reportes')
    } finally {
      setLoading(false)
    }
  }, [desde, hasta, verFinanzas, verRecetas])

  useEffect(() => {
    if (!permLoading) cargar()
  }, [permLoading, cargar])

  if (permLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-[#B45309]" />
      </div>
    )
  }

  if (!verFinanzas && !verRecetas) {
    return (
      <Card>
        <CardContent className="p-8 text-center text-muted-foreground">
          <AlertCircle className="h-10 w-10 mx-auto mb-3 text-gray-300" />
          <p>Tu rol no tiene acceso a reportes.</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-2">
        <BarChart3 className="h-6 w-6 text-[#B45309]" />
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Reportes por sucursal</h1>
          <p className="text-sm text-muted-foreground">Agregados por sucursal en el rango seleccionado.</p>
        </div>
      </div>

      {/* Rango de fechas */}
      <Card>
        <CardContent className="p-4 flex flex-wrap items-end gap-4">
          <div className="flex flex-col">
            <label className="text-xs text-muted-foreground mb-1">Desde</label>
            <input
              type="date"
              value={desde}
              max={hasta}
              onChange={(e) => setDesde(e.target.value)}
              className="border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div className="flex flex-col">
            <label className="text-xs text-muted-foreground mb-1">Hasta</label>
            <input
              type="date"
              value={hasta}
              min={desde}
              max={hoyIso()}
              onChange={(e) => setHasta(e.target.value)}
              className="border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <Button onClick={cargar} disabled={loading} className="bg-[#B45309] hover:bg-[#92400e]">
            {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Actualizar'}
          </Button>
        </CardContent>
      </Card>

      {error && (
        <Card>
          <CardContent className="p-4 flex items-center gap-2 text-sm text-red-600">
            <AlertCircle className="h-4 w-4 shrink-0" />
            {error}
          </CardContent>
        </Card>
      )}

      {/* Finanzas */}
      {verFinanzas && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <DollarSign className="h-5 w-5 text-emerald-600" />
              Dispensaciones y montos
            </CardTitle>
          </CardHeader>
          <CardContent>
            {finanzas.length === 0 ? (
              <p className="text-sm text-muted-foreground py-4 text-center">Sin dispensaciones completadas en el rango.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-muted-foreground border-b">
                      <th className="py-2 pr-4">Sucursal</th>
                      <th className="py-2 pr-4 text-right">Dispensaciones</th>
                      <th className="py-2 pr-4 text-right">Ítems</th>
                      <th className="py-2 text-right">Total dispensado</th>
                    </tr>
                  </thead>
                  <tbody>
                    {finanzas.map((r) => (
                      <tr key={r.sucursal_id} className="border-b last:border-0">
                        <td className="py-2 pr-4 font-medium">{r.sucursal}</td>
                        <td className="py-2 pr-4 text-right">{nf.format(r.dispensaciones)}</td>
                        <td className="py-2 pr-4 text-right">{nf.format(r.items)}</td>
                        <td className="py-2 text-right">{nf.format(r.total_dispensado)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Recetas / medicamentos */}
      {verRecetas && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <Pill className="h-5 w-5 text-sky-600" />
              Medicamentos dispensados
            </CardTitle>
          </CardHeader>
          <CardContent>
            {recetas.length === 0 ? (
              <p className="text-sm text-muted-foreground py-4 text-center">Sin medicamentos dispensados en el rango.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-muted-foreground border-b">
                      <th className="py-2 pr-4">Sucursal</th>
                      <th className="py-2 pr-4">Medicamento</th>
                      <th className="py-2 pr-4 text-right">Veces</th>
                      <th className="py-2 text-right">Cantidad total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {recetas.map((r, i) => (
                      <tr key={`${r.sucursal_id}-${r.medicamento}-${i}`} className="border-b last:border-0">
                        <td className="py-2 pr-4 font-medium">{r.sucursal}</td>
                        <td className="py-2 pr-4">{r.medicamento}</td>
                        <td className="py-2 pr-4 text-right">{nf.format(r.veces_dispensado)}</td>
                        <td className="py-2 text-right">{nf.format(r.cantidad_total)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="text-[11px] text-muted-foreground mt-3">
                  Las celdas con menos de 5 dispensaciones se agrupan como «(otros)» para proteger la privacidad.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
