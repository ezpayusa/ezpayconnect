import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, CalendarDays, CheckCircle, XCircle, Clock } from 'lucide-react'

interface Props {
  periodo: string
}

export default function ReporteCitas({ periodo }: Props) {
  const datos = useMemo(() => {
    const base = {
      hoy: { total: 8, atendidas: 5, canceladas: 1, pendientes: 2, porDoctor: [{ doctor: 'Dr. Principal', atendidas: 5, canceladas: 1 }] },
      semana: { total: 35, atendidas: 28, canceladas: 4, pendientes: 3, porDoctor: [{ doctor: 'Dr. Principal', atendidas: 28, canceladas: 4 }] },
      mes: { total: 142, atendidas: 118, canceladas: 12, pendientes: 12, porDoctor: [{ doctor: 'Dr. Principal', atendidas: 118, canceladas: 12 }] },
      trimestre: { total: 420, atendidas: 350, canceladas: 35, pendientes: 35, porDoctor: [{ doctor: 'Dr. Principal', atendidas: 350, canceladas: 35 }] },
      año: { total: 1680, atendidas: 1400, canceladas: 140, pendientes: 140, porDoctor: [{ doctor: 'Dr. Principal', atendidas: 1400, canceladas: 140 }] },
    }
    return base[periodo as keyof typeof base] || base.mes
  }, [periodo])

  const exportarCSV = () => {
    const csv = [
      ['Métrica', 'Cantidad'],
      ['Total Citas', datos.total],
      ['Atendidas', datos.atendidas],
      ['Canceladas', datos.canceladas],
      ['Pendientes', datos.pendientes],
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `reporte-citas-${periodo}.csv`
    a.click()
  }

  const tasaAsistencia = ((datos.atendidas / datos.total) * 100).toFixed(1)

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Total Citas</p>
            <p className="text-2xl font-bold text-[#1a2a3a]">{datos.total}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-green-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Atendidas</p>
            <p className="text-2xl font-bold text-green-600">{datos.atendidas}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-red-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Canceladas</p>
            <p className="text-2xl font-bold text-red-600">{datos.canceladas}</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-yellow-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Tasa Asistencia</p>
            <p className="text-2xl font-bold text-yellow-600">{tasaAsistencia}%</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <CalendarDays className="h-5 w-5 text-[#1E5C8E]" />
            Distribución de Citas
          </CardTitle>
          <Button variant="outline" size="sm" onClick={exportarCSV}>
            <Download className="h-4 w-4 mr-2" /> Exportar
          </Button>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-[250px]">
            <div className="relative w-[180px] h-[180px] rounded-full"
              style={{
                background: `conic-gradient(
                  #22c55e ${(datos.atendidas / datos.total) * 360}deg,
                  #ef4444 ${(datos.atendidas / datos.total) * 360}deg ${((datos.atendidas + datos.canceladas) / datos.total) * 360}deg,
                  #f59e0b ${((datos.atendidas + datos.canceladas) / datos.total) * 360}deg
                )`
              }}
            >
              <div className="absolute inset-6 bg-white rounded-full flex flex-col items-center justify-center">
                <span className="text-3xl font-bold text-[#1a2a3a]">{datos.total}</span>
                <span className="text-xs text-[#8a9aaa]">citas</span>
              </div>
            </div>
            <div className="ml-8 space-y-3">
              <div className="flex items-center gap-2">
                <CheckCircle className="h-5 w-5 text-green-500" />
                <span className="text-sm">Atendidas: {datos.atendidas}</span>
              </div>
              <div className="flex items-center gap-2">
                <XCircle className="h-5 w-5 text-red-500" />
                <span className="text-sm">Canceladas: {datos.canceladas}</span>
              </div>
              <div className="flex items-center gap-2">
                <Clock className="h-5 w-5 text-yellow-500" />
                <span className="text-sm">Pendientes: {datos.pendientes}</span>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
