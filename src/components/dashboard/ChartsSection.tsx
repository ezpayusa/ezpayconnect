import { useMemo } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, LineChart, Line, Legend, AreaChart, Area
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { generateStats } from '@/data/mockStats'
import type { Cita, Paciente } from '@/types'
import { TrendingUp, Users, CalendarCheck, Stethoscope } from 'lucide-react'

interface ChartsSectionProps {
  citas: Cita[]
  pacientes: Paciente[]
}

export default function ChartsSection({ citas, pacientes }: ChartsSectionProps) {
  const stats = useMemo(() => generateStats(citas, pacientes), [citas, pacientes])

  // Formato de moneda para Quetzales
  const formatQ = (value: number) => `Q${value.toLocaleString()}`

  return (
    <div className="space-y-6">
      {/* Fila 1: Citas por día + Estado de citas */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Gráfico de barras: Citas por día */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <CalendarCheck className="h-5 w-5 text-[#1E5C8E]" />
              Citas esta semana
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={stats.citasPorDia}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e8f0f8" />
                <XAxis dataKey="dia" tick={{ fill: '#8a9aaa', fontSize: 12 }} />
                <YAxis tick={{ fill: '#8a9aaa', fontSize: 12 }} allowDecimals={false} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#fff', border: '1px solid #e8f0f8', borderRadius: '8px' }}
                  formatter={(value: number) => [`${value} citas`, 'Citas']}
                />
                <Bar dataKey="citas" fill="#1E5C8E" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        {/* Gráfico de pastel: Estado de citas */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <TrendingUp className="h-5 w-5 text-[#1E5C8E]" />
              Estado de citas
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie
                  data={stats.estadoCitas}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={90}
                  paddingAngle={4}
                  dataKey="cantidad"
                >
                  {stats.estadoCitas.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{ backgroundColor: '#fff', border: '1px solid #e8f0f8', borderRadius: '8px' }}
                  formatter={(value: number, name: string) => [`${value}`, name]}
                />
                <Legend
                  verticalAlign="bottom"
                  height={36}
                  iconType="circle"
                  formatter={(value: string) => <span style={{ color: '#1a2a3a', fontSize: '12px' }}>{value}</span>}
                />
              </PieChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      {/* Fila 2: Ingresos del mes */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <TrendingUp className="h-5 w-5 text-[#22c55e]" />
            Ingresos por semana (Q)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={stats.ingresosPorSemana}>
              <defs>
                <linearGradient id="colorIngresos" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#22c55e" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#e8f0f8" />
              <XAxis dataKey="semana" tick={{ fill: '#8a9aaa', fontSize: 12 }} />
              <YAxis tick={{ fill: '#8a9aaa', fontSize: 12 }} tickFormatter={formatQ} />
              <Tooltip
                contentStyle={{ backgroundColor: '#fff', border: '1px solid #e8f0f8', borderRadius: '8px' }}
                formatter={(value: number) => [formatQ(value), 'Ingresos']}
              />
              <Area
                type="monotone"
                dataKey="ingresos"
                stroke="#22c55e"
                strokeWidth={2}
                fillOpacity={1}
                fill="url(#colorIngresos)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      {/* Fila 3: Pacientes nuevos vs recurrentes + Top pacientes */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Gráfico de barras agrupadas: Pacientes nuevos vs recurrentes */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Users className="h-5 w-5 text-[#3A8ABF]" />
              Pacientes nuevos vs recurrentes
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={stats.pacientesNuevos}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e8f0f8" />
                <XAxis dataKey="mes" tick={{ fill: '#8a9aaa', fontSize: 12 }} />
                <YAxis tick={{ fill: '#8a9aaa', fontSize: 12 }} allowDecimals={false} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#fff', border: '1px solid #e8f0f8', borderRadius: '8px' }}
                />
                <Legend
                  formatter={(value: string) => <span style={{ color: '#1a2a3a', fontSize: '12px' }}>{value}</span>}
                />
                <Bar dataKey="nuevos" fill="#1E5C8E" radius={[4, 4, 0, 0]} name="Nuevos" />
                <Bar dataKey="recurrentes" fill="#5BA8D1" radius={[4, 4, 0, 0]} name="Recurrentes" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        {/* Tabla: Top pacientes frecuentes */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Users className="h-5 w-5 text-[#1E5C8E]" />
              Pacientes más frecuentes
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {stats.topPacientes.map((paciente, index) => (
                <div
                  key={index}
                  className="flex items-center justify-between p-3 rounded-lg bg-[#e8f0f8] hover:bg-[#d4e4f0] transition-colors"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-[#1E5C8E] text-white flex items-center justify-center text-sm font-bold">
                      {index + 1}
                    </div>
                    <div>
                      <p className="font-medium text-sm text-[#1a2a3a]">{paciente.nombre}</p>
                      <p className="text-xs text-[#8a9aaa]">Última: {paciente.ultimaCita}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="font-bold text-[#1E5C8E]">{paciente.citas}</p>
                    <p className="text-xs text-[#8a9aaa]">citas</p>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Fila 4: Diagnósticos frecuentes */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <Stethoscope className="h-5 w-5 text-[#ef4444]" />
            Diagnósticos más frecuentes
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
            {stats.diagnosticosFrecuentes.map((diag, index) => (
              <div
                key={index}
                className="p-4 rounded-lg bg-gradient-to-br from-[#1E5C8E] to-[#3A8ABF] text-white text-center"
              >
                <p className="text-2xl font-bold">{diag.cantidad}</p>
                <p className="text-xs mt-1 opacity-90">{diag.diagnostico}</p>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
