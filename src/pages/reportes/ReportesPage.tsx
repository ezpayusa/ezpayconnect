import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { TrendingUp, DollarSign, CalendarDays, Users, FileText, Pill, Download, ArrowLeft } from 'lucide-react'
import ReporteIngresos from './ReporteIngresos'
import ReporteCitas from './ReporteCitas'
import ReportePacientes from './ReportePacientes'
import ReporteRecetas from './ReporteRecetas'
import ReporteFacturacion from './ReporteFacturacion'

export default function ReportesPage() {
  const navigate = useNavigate()
  const [periodo, setPeriodo] = useState('mes')

  const periodos = [
    { value: 'hoy', label: 'Hoy' },
    { value: 'semana', label: 'Esta semana' },
    { value: 'mes', label: 'Este mes' },
    { value: 'trimestre', label: 'Este trimestre' },
    { value: 'año', label: 'Este año' },
  ]

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Button variant="ghost" size="sm" onClick={() => navigate('/dashboard')} className="text-[#8a9aaa]">
              <ArrowLeft className="h-4 w-4 mr-1" /> Dashboard
            </Button>
          </div>
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <TrendingUp className="h-8 w-8 text-[#1E5C8E]" />
            Centro de Reportes
          </h1>
          <p className="text-[#8a9aaa] mt-1">Análisis detallado y estadísticas completas</p>
        </div>
      </div>

      <Card className="bg-[#e8f0f8] border-none">
        <CardContent className="p-4">
          <div className="flex items-center gap-4 flex-wrap">
            <span className="text-sm font-medium text-[#1a2a3a]">Período:</span>
            <div className="flex bg-white rounded-lg p-1 shadow-sm">
              {periodos.map(p => (
                <button
                  key={p.value}
                  onClick={() => setPeriodo(p.value)}
                  className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${
                    periodo === p.value
                      ? 'bg-[#1E5C8E] text-white shadow-sm'
                      : 'text-[#8a9aaa] hover:text-[#1a2a3a]'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      <Tabs defaultValue="ingresos" className="space-y-6">
        <TabsList className="bg-[#e8f0f8] p-1 h-auto flex-wrap gap-1">
          <TabsTrigger value="ingresos" className="flex items-center gap-2 px-4 py-2 data-[state=active]:bg-[#1E5C8E] data-[state=active]:text-white">
            <DollarSign className="h-4 w-4" /> Ingresos
          </TabsTrigger>
          <TabsTrigger value="citas" className="flex items-center gap-2 px-4 py-2 data-[state=active]:bg-[#1E5C8E] data-[state=active]:text-white">
            <CalendarDays className="h-4 w-4" /> Citas
          </TabsTrigger>
          <TabsTrigger value="pacientes" className="flex items-center gap-2 px-4 py-2 data-[state=active]:bg-[#1E5C8E] data-[state=active]:text-white">
            <Users className="h-4 w-4" /> Pacientes
          </TabsTrigger>
          <TabsTrigger value="recetas" className="flex items-center gap-2 px-4 py-2 data-[state=active]:bg-[#1E5C8E] data-[state=active]:text-white">
            <Pill className="h-4 w-4" /> Recetas
          </TabsTrigger>
          <TabsTrigger value="facturacion" className="flex items-center gap-2 px-4 py-2 data-[state=active]:bg-[#1E5C8E] data-[state=active]:text-white">
            <FileText className="h-4 w-4" /> Facturación
          </TabsTrigger>
        </TabsList>

        <TabsContent value="ingresos" className="mt-0">
          <ReporteIngresos periodo={periodo} />
        </TabsContent>
        <TabsContent value="citas" className="mt-0">
          <ReporteCitas periodo={periodo} />
        </TabsContent>
        <TabsContent value="pacientes" className="mt-0">
          <ReportePacientes periodo={periodo} />
        </TabsContent>
        <TabsContent value="recetas" className="mt-0">
          <ReporteRecetas periodo={periodo} />
        </TabsContent>
        <TabsContent value="facturacion" className="mt-0">
          <ReporteFacturacion periodo={periodo} />
        </TabsContent>
      </Tabs>
    </div>
  )
}
