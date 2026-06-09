export function formatMedicoNombre(nombre: string | null | undefined): string {
  if (!nombre || nombre === 'Médico por asignar' || nombre === 'Médico asignado') {
    return nombre || 'Médico'
  }
  if (/^Dr\.?\s|^Dra\.?\s/i.test(nombre)) {
    return nombre
  }
  return `Dr. ${nombre}`
}
