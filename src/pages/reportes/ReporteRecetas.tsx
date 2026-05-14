import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, Pill, TrendingUp } from 'lucide-react'

interface Props {
  periodo: string
}

export default function ReporteRecetas({ periodo }: Props) {
  const datos = useMemo(() => {
    const base = {
      hoy: { total: 5, medicamentosTop: [{ nombre: 'Paracetamol', cantidad: 3 }, { nombre: 'Amoxicilina', cantidad: 2 }, { nombre: 'Ibuprofeno', cantidad: 2 }] },
      semana: { total: 22, medicamentosTop: [{ nombre: 'Paracetamol', cantidad: 12 }, { nombre: 'Amoxicilina', cantidad: 8 }, { nombre: 'Ibuprofeno', cantidad: 7 }, { nombre: 'Omeprazol', cantidad: 5 }] },
      mes: { total: 85, medicamentosTop: [{ nombre: 'Paracetamol', cantidad: 45 }, { nombre: 'Amoxicilina', cantidad: 32 }, { nombre: 'Ibuprofeno', cantidad: 28 }, { nombre: 'Omeprazol', cantidad: 20 }, { nombre: 'Loratadina', cantidad: 18 }] },
      trimestre: { total: 250, medicamentosTop: [{ nombre: 'Paracetamol', cantidad: 130 }, { nombre: 'Amoxicilina', cantidad: 95 }, { nombre: 'Ibuprofeno', cantidad: 82 }, { nombre: 'Omeprazol', cantidad: 60 }, { nombre: 'Loratadina', cantidad: 55 }] },
      año: { total: 980, medicamentosTop: [{ nombre: 'Paracetamol', cantidad: 520 }, { nombre: 'Amoxicilina', cantidad: 380 }, { nombre: 'Ibuprofeno', cantidad: 320 }, { nombre: 'Omeprazol', cantidad: 240 }, { nombre: 'Loratadina', cantidad: 210 }] },
    }
    return base[periodo as keyof typeof base] || base.mes
  }, [periodo])

  const exportarCSV = () => {
    const csv = [
      ['Medicamento', 'Cantidad Recetada'],
      ...datos.medicamentosTop.map(d => [d.nombre, d.cantidad]),
      ['TOTAL RECETAS', datos.total]
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `reporte-recetas-${periodo}.csv`
    a.click()
  }

  const maxMed = Math.max(...datos.medicamentosTop.map(d => d.cantidad), 1)

  return (
    <div className="space-y-6">
      <Card className="border-l-4 border-l-[#5BA8D1]">
        <CardContent className="p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-[#8a9aaa]">Total Recetas</p>
              <p className="text-3xl font-bold text-[#1a2a3a]">{datos.total}</p>
            </div>
            <Pill className="h-10 w-10 text-[#5BA8D1]" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <TrendingUp className="h-5 w-5 text-[#1E5C8E]" />
            Medicamentos Más Recetados
          </CardTitle>
          <Button variant="outline" size="sm" onClick={exportarCSV}>
            <Download className="h-4 w-4 mr-2" /> Exportar
          </Button>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {datos.medicamentosTop.map((med, i) => (
              <div key={i}>
                <div className="flex justify-between mb-1">
                  <span className="text-sm font-medium text-[#1a2a3a] flex items-center gap-2">
                    <span className="w-6 h-6 rounded-full bg-[#1E5C8E] text-white text-xs flex items-center justify-center">{i + 1}</span>
                    {med.nombre}
                  </span>
                  <span className="text-sm font-bold text-[#1E5C8E]">{med.cantidad} recetas</span>
                </div>
                <div className="w-full bg-[#e8f0f8] rounded-full h-3">
                  <div
                    className="bg-gradient-to-r from-[#1E5C8E] to-[#5BA8D1] h-3 rounded-full transition-all duration-500"
                    style={{ width: `${(med.cantidad / maxMed) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
