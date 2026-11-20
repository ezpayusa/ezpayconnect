import { nombreMedicoConPrefijo } from '@/lib/nombreMedico'

// Delegado al helper único (src/lib/nombreMedico.ts); conserva los textos de «sin médico» tal cual.
export function formatMedicoNombre(nombre: string | null | undefined): string {
  if (!nombre || nombre === 'Médico por asignar' || nombre === 'Médico asignado') {
    return nombre || 'Médico'
  }
  return nombreMedicoConPrefijo(nombre)
}
