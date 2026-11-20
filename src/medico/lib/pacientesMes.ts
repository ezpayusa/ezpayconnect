// «Pacientes (mes)» del dashboard del médico: pacientes DISTINTOS que en el mes tienen una cita
// atendida (en_curso o completada) O una receta emitida por el médico. Un paciente con cita y receta
// cuenta una sola vez; las filas sin paciente_id no cuentan.
export const ESTADOS_CITA_ATENDIDA = ['en_curso', 'completada'] as const

type ConPaciente = { paciente_id: number | string | null }

export function contarPacientesDistintos(...listas: ConPaciente[][]): number {
  const ids = new Set<string>()
  for (const lista of listas) {
    for (const fila of lista) {
      if (fila.paciente_id !== null && fila.paciente_id !== undefined) ids.add(String(fila.paciente_id))
    }
  }
  return ids.size
}
