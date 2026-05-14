import type { Cita, Paciente } from '@/types'

export interface DashboardStats {
  citasPorDia: { dia: string; citas: number }[]
  estadoCitas: { estado: string; cantidad: number; color: string }[]
  ingresosPorSemana: { semana: string; ingresos: number }[]
  pacientesNuevos: { mes: string; nuevos: number; recurrentes: number }[]
  topPacientes: { nombre: string; citas: number; ultimaCita: string }[]
  diagnosticosFrecuentes: { diagnostico: string; cantidad: number }[]
}

// Genera estadísticas basadas en citas reales + datos mock de ingresos
export function generateStats(citas: Cita[], pacientes: Paciente[]): DashboardStats {
  const hoy = new Date()
  const diasSemana = ['Dom', 'Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab']

  // 1. Citas por día de la semana actual
  const inicioSemana = new Date(hoy)
  inicioSemana.setDate(hoy.getDate() - hoy.getDay())

  const citasPorDia = Array.from({ length: 7 }, (_, i) => {
    const fecha = new Date(inicioSemana)
    fecha.setDate(inicioSemana.getDate() + i)
    const fechaStr = fecha.toISOString().split('T')[0]
    const count = citas.filter(c => c.fecha === fechaStr).length
    return { dia: diasSemana[fecha.getDay()], citas: count }
  })

  // 2. Estado de citas
  const estados = ['agendada', 'completada', 'cancelada', 'no_show']
  const colores = ['#3A8ABF', '#22c55e', '#ef4444', '#f59e0b']
  const estadoCitas = estados.map((estado, i) => ({
    estado: estado === 'no_show' ? 'No asistió' : estado.charAt(0).toUpperCase() + estado.slice(1),
    cantidad: citas.filter(c => c.estado === estado).length,
    color: colores[i]
  })).filter(e => e.cantidad > 0)

  // Si no hay datos, mostrar ejemplo
  if (estadoCitas.length === 0) {
    estadoCitas.push(
      { estado: 'Agendada', cantidad: 3, color: '#3A8ABF' },
      { estado: 'Completada', cantidad: 5, color: '#22c55e' },
      { estado: 'Cancelada', cantidad: 1, color: '#ef4444' }
    )
  }

  // 3. Ingresos mock por semana (últimas 4 semanas)
  const semanas = ['Sem 1', 'Sem 2', 'Sem 3', 'Sem 4']
  const ingresosPorSemana = semanas.map((semana, i) => ({
    semana,
    ingresos: [2500, 3200, 2800, 4100][i] || 3000
  }))

  // 4. Pacientes nuevos vs recurrentes por mes
  const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May']
  const pacientesNuevos = meses.map((mes, i) => ({
    mes,
    nuevos: [2, 3, 1, 4, pacientes.length][i] || 2,
    recurrentes: [5, 7, 4, 8, 6][i] || 5
  }))

  // 5. Top pacientes frecuentes
  const pacienteCitasCount = new Map<number, number>()
  citas.forEach(c => {
    pacienteCitasCount.set(c.paciente_id, (pacienteCitasCount.get(c.paciente_id) || 0) + 1)
  })

  const topPacientes = Array.from(pacienteCitasCount.entries())
    .map(([pacienteId, count]) => {
      const paciente = pacientes.find(p => p.id === pacienteId)
      const ultimaCita = citas
        .filter(c => c.paciente_id === pacienteId)
        .sort((a, b) => new Date(b.fecha).getTime() - new Date(a.fecha).getTime())[0]
      return {
        nombre: paciente ? `${paciente.nombre} ${paciente.apellido}` : `Paciente #${pacienteId}`,
        citas: count,
        ultimaCita: ultimaCita?.fecha || 'N/A'
      }
    })
    .sort((a, b) => b.citas - a.citas)
    .slice(0, 5)

  // Si no hay datos, mostrar ejemplo
  if (topPacientes.length === 0) {
    topPacientes.push(
      { nombre: 'Juan Pérez', citas: 3, ultimaCita: '2026-05-10' },
      { nombre: 'María García', citas: 2, ultimaCita: '2026-05-08' },
      { nombre: 'Carlos López', citas: 1, ultimaCita: '2026-05-05' }
    )
  }

  // 6. Diagnósticos frecuentes mock
  const diagnosticosFrecuentes = [
    { diagnostico: 'Hipertensión', cantidad: 8 },
    { diagnostico: 'Diabetes Tipo 2', cantidad: 6 },
    { diagnostico: 'Gripe/Influenza', cantidad: 5 },
    { diagnostico: 'Dolor de espalda', cantidad: 4 },
    { diagnostico: 'Ansiedad', cantidad: 3 },
    { diagnostico: 'Infección respiratoria', cantidad: 3 },
  ]

  return {
    citasPorDia,
    estadoCitas,
    ingresosPorSemana,
    pacientesNuevos,
    topPacientes,
    diagnosticosFrecuentes
  }
}
