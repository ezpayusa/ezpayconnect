import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, FileText, DollarSign, CreditCard, CheckCircle } from 'lucide-react'

interface Props {
  periodo: string
}

export default function ReporteFacturacion({ periodo }: Props) {
  const datos = useMemo(() => {
    const base = {
      hoy: { total: 3, pagadas: 2, pendientes: 1, canceladas: 0, porMetodo: [{ metodo: 'Efectivo', cantidad: 2, monto: 600 }, { metodo: 'Tarjeta', cantidad: 1, monto: 250 }] },
      semana: { total: 15, pagadas: 12, pendientes: 2, canceladas: 1, porMetodo: [{ metodo: 'Efectivo', cantidad: 8, monto: 2400 }, { metodo: 'Tarjeta', cantidad: 4, monto: 1200 }, { metodo: 'Transferencia', cantidad: 3, monto: 950 }] },
      mes: { total: 58, pagadas: 48, pendientes: 8, canceladas: 2, porMetodo: [{ metodo: 'Efectivo', cantidad: 30, monto: 9000 }, { metodo: 'Tarjeta', cantidad: 15, monto: 4500 }, { metodo: 'Transferencia', cantidad: 10, monto: 3200 }, { metodo: 'Seguro', cantidad: 3, monto: 750 }] },
      trimestre: { total: 175, pagadas: 145, pendientes: 22, canceladas: 8, porMetodo: [{ metodo: 'Efectivo', cantidad: 90, monto: 27000 }, { metodo: 'Tarjeta', cantidad: 45, monto: 13500 }, { metodo: 'Transferencia', cantidad: 30, monto: 9600 }, { metodo: 'Seguro', cantidad: 10, monto: 2500 }] },
      año: { total: 700, pagadas: 580, pendientes: 90, canceladas: 30, porMetodo: [{ metodo: 'Efectivo', cantidad: 350, monto: 105000 }, { metodo: 'Tarjeta', cantidad: 180, monto: 54000 }, { metodo: 'Transferencia', cantidad: 120, monto: 38400 }, { metodo: 'Seguro', cantidad: 50, monto: 12500 }] },
    }
    return base[periodo as keyof typeof base] || base.mes
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
          <Button variant="outline" size="sm" onClick={exportarCSV}>
            <Download className="h-4 w-4 mr-2" /> Exportar
          </Button>
        </CardHeader>
        <CardContent>
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
        </CardContent>
      </Card>
    </div>
  )
}
