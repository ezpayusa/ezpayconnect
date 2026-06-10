import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, FileText, DollarSign, CreditCard, CheckCircle, Loader2 } from 'lucide-react'

interface Props {
  periodo: string
}

interface MetodoAgg {
  metodo: string
  cantidad: number
  monto: number
}

interface Datos {
  total: number
  pagadas: number
  pendientes: number
  canceladas: number
  porMetodo: MetodoAgg[]
}

const VACIO: Datos = { total: 0, pagadas: 0, pendientes: 0, canceladas: 0, porMetodo: [] }

// Calcula la fecha de inicio (YYYY-MM-DD) según el período
function fechaInicio(periodo: string): string {
  const hoy = new Date()
  const d = new Date(hoy)
  switch (periodo) {
    case 'hoy': break
    case 'semana': d.setDate(hoy.getDate() - 6); break
    case 'mes': d.setDate(1); break
    case 'trimestre': d.setDate(hoy.getDate() - 89); break
    case 'año': d.setMonth(0, 1); break
    default: d.setDate(1) // mes por defecto
  }
  return d.toISOString().slice(0, 10)
}

const cap = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : 'Sin método')

export default function ReporteFacturacion({ periodo }: Props) {
  const [datos, setDatos] = useState<Datos>(VACIO)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelado = false
    const cargar = async () => {
      setLoading(true)
      try {
        const desde = fechaInicio(periodo)
        const { data, error } = await supabase
          .from('facturas')
          .select('estado, metodo_pago, total')
          .gte('fecha_emision', desde)

        if (error) throw error
        const filas = (data || []) as { estado: string | null; metodo_pago: string | null; total: number | null }[]

        const agg: Record<string, MetodoAgg> = {}
        let pagadas = 0, pendientes = 0, canceladas = 0
        for (const f of filas) {
          if (f.estado === 'pagada') pagadas++
          else if (f.estado === 'cancelada') canceladas++
          else pendientes++ // 'pendiente' o null

          const label = cap(f.metodo_pago || '')
          if (!agg[label]) agg[label] = { metodo: label, cantidad: 0, monto: 0 }
          agg[label].cantidad++
          agg[label].monto += Number(f.total) || 0
        }

        if (!cancelado) {
          setDatos({
            total: filas.length,
            pagadas,
            pendientes,
            canceladas,
            porMetodo: Object.values(agg).sort((a, b) => b.monto - a.monto),
          })
        }
      } catch (err) {
        console.error('Error cargando facturación:', err)
        if (!cancelado) setDatos(VACIO)
      } finally {
        if (!cancelado) setLoading(false)
      }
    }
    cargar()
    return () => { cancelado = true }
  }, [periodo])

  const exportarCSV = () => {
    const csv = [
      ['Método de Pago', 'Cantidad', 'Monto (Q)'],
      ...datos.porMetodo.map(d => [d.metodo, d.cantidad, d.monto]),
      ['TOTAL', datos.total, datos.porMetodo.reduce((s, d) => s + d.monto, 0)]
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `reporte-facturacion-${periodo}.csv`
    a.click()
  }

  const totalMonto = datos.porMetodo.reduce((s, d) => s + d.monto, 0)
  const maxMetodo = Math.max(...datos.porMetodo.map(d => d.monto), 1)

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Total Facturas</p>
            <p className="text-2xl font-bold text-[#1a2a3a]">{datos.total}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-green-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Pagadas</p>
            <p className="text-2xl font-bold text-green-600">{datos.pagadas}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-yellow-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Pendientes</p>
            <p className="text-2xl font-bold text-yellow-600">{datos.pendientes}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#22c55e]">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Monto Total</p>
            <p className="text-2xl font-bold text-[#22c55e]">Q{totalMonto.toLocaleString()}</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <CreditCard className="h-5 w-5 text-[#1E5C8E]" />
            Facturación por Método de Pago
          </CardTitle>
          <Button variant="outline" size="sm" onClick={exportarCSV} disabled={datos.porMetodo.length === 0}>
            <Download className="h-4 w-4 mr-2" /> Exportar
          </Button>
        </CardHeader>
        <CardContent>
          {datos.porMetodo.length === 0 ? (
            <p className="text-center text-[#8a9aaa] py-8">No hay facturas en este período</p>
          ) : (
            <>
              <div className="space-y-4">
                {datos.porMetodo.map((metodo, i) => (
                  <div key={i}>
                    <div className="flex justify-between mb-1">
                      <span className="text-sm font-medium text-[#1a2a3a] flex items-center gap-2">
                        {metodo.metodo === 'Efectivo' && <DollarSign className="h-4 w-4 text-green-600" />}
                        {metodo.metodo === 'Tarjeta' && <CreditCard className="h-4 w-4 text-blue-600" />}
                        {metodo.metodo === 'Transferencia' && <FileText className="h-4 w-4 text-purple-600" />}
                        {metodo.metodo === 'Seguro' && <CheckCircle className="h-4 w-4 text-orange-600" />}
                        {metodo.metodo}
                      </span>
                      <span className="text-sm font-bold text-[#1E5C8E]">Q{metodo.monto.toLocaleString()} ({metodo.cantidad})</span>
                    </div>
                    <div className="w-full bg-[#e8f0f8] rounded-full h-4">
                      <div
                        className="bg-gradient-to-r from-[#1E5C8E] to-[#3A8ABF] h-4 rounded-full transition-all duration-500"
                        style={{ width: `${(metodo.monto / maxMetodo) * 100}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-6 pt-4 border-t flex justify-between items-center">
                <span className="font-bold text-[#1a2a3a]">TOTAL</span>
                <span className="font-bold text-xl text-[#1E5C8E]">Q{totalMonto.toLocaleString()}</span>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
