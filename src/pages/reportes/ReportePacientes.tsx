import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Download, Users, UserPlus, UserCheck, User } from 'lucide-react'

interface Props {
  periodo: string
}

export default function ReportePacientes({ periodo }: Props) {
  const datos = useMemo(() => {
    const base = {
      hoy: { total: 2, nuevos: 1, recurrentes: 1, porEdad: [{ rango: '18-30', cantidad: 1 }, { rango: '31-50', cantidad: 1 }] },
      semana: { total: 12, nuevos: 4, recurrentes: 8, porEdad: [{ rango: '0-17', cantidad: 2 }, { rango: '18-30', cantidad: 3 }, { rango: '31-50', cantidad: 4 }, { rango: '51+', cantidad: 3 }] },
      mes: { total: 45, nuevos: 15, recurrentes: 30, porEdad: [{ rango: '0-17', cantidad: 8 }, { rango: '18-30', cantidad: 12 }, { rango: '31-50', cantidad: 15 }, { rango: '51+', cantidad: 10 }] },
      trimestre: { total: 130, nuevos: 40, recurrentes: 90, porEdad: [{ rango: '0-17', cantidad: 25 }, { rango: '18-30', cantidad: 35 }, { rango: '31-50', cantidad: 42 }, { rango: '51+', cantidad: 28 }] },
      año: { total: 520, nuevos: 160, recurrentes: 360, porEdad: [{ rango: '0-17', cantidad: 100 }, { rango: '18-30', cantidad: 140 }, { rango: '31-50', cantidad: 170 }, { rango: '51+', cantidad: 110 }] },
    }
    return base[periodo as keyof typeof base] || base.mes
  }, [periodo])

  const exportarCSV = () => {
    const csv = [
      ['Rango de Edad', 'Cantidad'],
      ...datos.porEdad.map(d => [d.rango, d.cantidad]),
      ['TOTAL', datos.total]
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `reporte-pacientes-${periodo}.csv`
    a.click()
  }

  const maxEdad = Math.max(...datos.porEdad.map(d => d.cantidad), 1)

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Total Pacientes</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">{datos.total}</p>
              </div>
              <Users className="h-10 w-10 text-[#1E5C8E]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#3A8ABF]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Nuevos</p>
                <p className="text-3xl font-bold text-[#3A8ABF]">{datos.nuevos}</p>
              </div>
              <UserPlus className="h-10 w-10 text-[#3A8ABF]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#5BA8D1]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Recurrentes</p>
                <p className="text-3xl font-bold text-[#5BA8D1]">{datos.recurrentes}</p>
              </div>
              <UserCheck className="h-10 w-10 text-[#5BA8D1]" />
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <User className="h-5 w-5 text-[#1E5C8E]" />
            Pacientes por Rango de Edad
          </CardTitle>
          <Button variant="outline" size="sm" onClick={exportarCSV}>
            <Download className="h-4 w-4 mr-2" /> Exportar
          </Button>
        </CardHeader>
        <CardContent>
          <div className="flex items-end justify-between h-[200px] px-4 pb-2 gap-4">
            {datos.porEdad.map((d, i) => (
              <div key={i} className="flex flex-col items-center flex-1">
                <span className="text-xs text-[#1a2a3a] font-bold mb-1">{d.cantidad}</span>
                <div
                  className="w-full bg-gradient-to-t from-[#1E5C8E] to-[#3A8ABF] rounded-t-md transition-all duration-500"
                  style={{ height: `${(d.cantidad / maxEdad) * 160}px` }}
                />
                <span className="text-xs text-[#8a9aaa] mt-2">{d.rango}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
