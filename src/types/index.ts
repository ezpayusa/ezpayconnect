export interface Perfil {
  id: string
  rol: 'medico' | 'secretaria' | 'admin_clinica' | 'paciente' | 'ezpay_admin'
  nombre_completo: string
  email: string
  telefono: string | null
  avatar_url: string | null
  pais_id: string | null
  activo: boolean
  created_at: string
}

export interface Paciente {
  id: number
  medico_id: string
  clinica_id: string | null
  nombre: string
  apellido: string
  fecha_nacimiento: string | null
  genero: string | null
  telefono: string | null
  email: string | null
  direccion: string | null
  emergencia_nombre: string | null
  emergencia_telefono: string | null
  alergias: string | null
  notas: string | null
  tipo_sangre: string | null
  antecedentes_personales: string | null
  antecedentes_familiares: string | null
  medicamentos_en_uso: string | null
  foto_path: string | null
  activo: boolean
  created_at: string
}

export interface Cita {
  id: number
  medico_id: string
  paciente_id: number
  clinica_id: string | null
  fecha: string
  hora_inicio: string
  hora_fin: string | null
  motivo: string | null
  estado: 'agendada' | 'confirmada' | 'en_curso' | 'completada' | 'cancelada' | 'no_show' | 'solicitada'
  notas: string | null
  created_at: string
}

export interface Medicamento {
  id: number
  nombre_generico: string
  nombre_comercial: string | null
  laboratorio: string | null
  presentacion: string | null
  concentracion: string | null
  via_administracion: string | null
  precio_referencia: number | null
  requiere_receta: boolean
  activo: boolean
}

export interface Receta {
  id: number
  medico_id: string
  paciente_id: number
  paciente_nombre?: string
  cita_id: number | null
  estado: 'activa' | 'completada' | 'vencida' | 'cancelada'
  instrucciones_generales: string | null
  pdf_url: string | null
  codigo_qr: string | null
  created_at: string
}

export interface RecetaItem {
  id: number
  receta_id: number
  medicamento_id: number | null
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  duracion: string | null
  instrucciones: string | null
  cantidad: number
  farmacia_id: number | null
  precio_unitario: number | null
  stock_actual: number | null
}
export interface ExpedienteNota {
  id: number
  cita_id: number | null
  paciente_id: number
  medico_id: string
  nota: string
  diagnostico: string | null
  motivo_consulta: string | null
  subjetivo: string | null
  objetivo: string | null
  analisis: string | null
  plan: string | null
  presion_arterial: string | null
  frecuencia_cardiaca: number | null
  frecuencia_respiratoria: number | null
  temperatura: number | null
  peso_kg: number | null
  talla_cm: number | null
  imc: number | null
  saturacion_o2: number | null
  glucosa: number | null
  signos_vitales: Record<string, any> | null
  created_at: string
}

export interface SignosVitales {
  id: number
  paciente_id: number
  medico_id: string | null
  consulta_id: number | null
  presion_arterial: string | null
  frecuencia_cardiaca: number | null
  frecuencia_respiratoria: number | null
  temperatura: number | null
  peso_kg: number | null
  talla_cm: number | null
  imc: number | null
  saturacion_o2: number | null
  glucosa: number | null
  notas: string | null
  fecha_toma: string
  created_at: string
}

// Re-export de tipos que viven en types-con-factura.ts pero que el código consume
// desde este barrel (@/types). Antes: TS2305 (no exportados acá).
// Nota: HistorialMedico también está definido, IDÉNTICO campo por campo, en
// types-index.ts; se re-exporta el de types-con-factura.ts (mismo archivo que
// Factura) y se descarta el duplicado de types-index.ts para evitar ambigüedad.
export type { Factura, HistorialMedico } from './types-con-factura';
