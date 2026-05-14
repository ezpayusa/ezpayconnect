import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, TrendingUp, TrendingDown, DollarSign } from 'lucide-react'

interface Props {
  periodo: string
}

export default function ReporteIngresos({ periodo }: Props) {
  const datos = useMemo(() => {
    const base = {
      hoy: { total: 850, comparacion: -120, porcentaje: -12, detalle: [{ concepto: 'Consulta general', cantidad: 3, monto: 450 }, { concepto: 'Receta médica', cantidad: 2, monto: 200 }, { concepto: 'Exámenes', cantidad: 1, monto: 200 }] },
      semana: { total: 3200, comparacion: 800, porcentaje: 33, detalle: [{ concepto: 'Consulta general', cantidad: 12, monto: 1800 }, { concepto: 'Receta médica', cantidad: 8, monto: 800 }, { concepto: 'Exámenes', cantidad: 3, monto: 600 }] },
      mes: { total: 12450, comparacion: 2100, porcentaje: 20, detalle: [{ concepto: 'Consulta general', cantidad: 45, monto: 6750 }, { concepto: 'Receta médica', cantidad: 30, monto: 3000 }, { concepto: 'Exámenes', cantidad: 12, monto: 2700 }] },
      trimestre: { total: 35800, comparacion: 5200, porcentaje: 17, detalle: [{ concepto: 'Consulta general', cantidad: 135, monto: 20250 }, { concepto: 'Receta médica', cantidad: 85, monto: 8500 }, { concepto: 'Exámenes', cantidad: 38, monto: 7050 }] },
      año: { total: 142000, comparacion: 28000, porcentaje: 25, detalle: [{ concepto: 'Consulta general', cantidad: 520, monto: 78000 }, { concepto: 'Receta médica', cantidad: 340, monto: 34000 }, { concepto: 'Exámenes', cantidad: 150, monto: 30000 }] },
    }
    return base[periodo as keyof typeof base] || base.mes
  }, [periodo])

  const exportarCSV = () => {
    const csv = [
      ['Concepto', 'Cantidad', 'Monto (Q)'],
      ...datos.detalle.map(d => [d.concepto, d.cantidad, d.monto]),
      ['TOTAL', datos.detalle.reduce((s, d) => s + d.cantidad, 0), datos.total]
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `reporte-ingresos-${periodo}.csv`
    a.click()
  }

  const exportarPDF = () => {
    window.print()
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-[#22c55e]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Total Ingresos</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">Q{datos.total.toLocaleString()}</p>
              </div>
              <DollarSign className="h-10 w-10 text-[#22c55e]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">vs Período Anterior</p>
                <p className={`text-3xl font-bold ${datos.comparacion >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                  {datos.comparacion >= 0 ? '+' : ''}Q{datos.comparacion.toLocaleString()}
                </p>
              </div>
              {datos.comparacion >= 0 ? <TrendingUp className="h-10 w-10 text-green-600" /> : <TrendingDown className="h-10 w-10 text-red-600" />}
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#3A8ABF]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Crecimiento</p>
                <p className={`text-3xl font-bold ${datos.porcentaje >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                  {datos.porcentaje >= 0 ? '+' : ''}{datos.porcentaje}%
                </p>
              </div>
              <TrendingUp className="h-10 w-10 text-[#3A8ABF]" />
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-lg">Ingresos por Concepto</CardTitle>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={exportarCSV}>
              <Download className="h-4 w-4 mr-2" /> CSV
            </Button>
            <Button variant="outline" size="sm" onClick={exportarPDF}>
              <Download className="h-4 w-4 mr-2" /> PDF
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {datos.detalle.map((item, i) => {
              const max = Math.max(...datos.detalle.map(d => d.monto))
              return (
                <div key={i}>
                  <div className="flex justify-between mb-1">
                    <span className="text-sm font-medium text-[#1a2a3a]">{item.concepto}</span>
                    <span className="text-sm font-bold text-[#1E5C8E]">Q{item.monto.toLocaleString()} ({item.cantidad})</span>
                  </div>
                  <div className="w-full bg-[#e8f0f8] rounded-full h-4">
                    <div
                      className="bg-gradient-to-r from-[#1E5C8E] to-[#3A8ABF] h-4 rounded-full transition-all duration-500"
                      style={{ width: `${(item.monto / max) * 100}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
          <div className="mt-6 pt-4 border-t flex justify-between items-center">
            <span className="font-bold text-[#1a2a3a]">TOTAL</span>
            <span className="font-bold text-xl text-[#1E5C8E]">Q{datos.total.toLocaleString()}</span>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
