import type { PacientePerfil } from '@/webapp/types/webapp.types'

// Whitelist EXPLÍCITA de las columnas editables por el PACIENTE desde /perfil.
// NO incluye `email` ni ninguna columna PRIVILEGIADA (medico_id, medico_primario_id,
// clinica_primaria_id, pais_id, activo, auth_user_id, id, foto_path, created_at): esas las bloquea
// el guard de la mig 325 con 42501 y el front tampoco debe mandarlas. `PacientePerfil` ni siquiera
// las expone, así que no pueden colarse por accidente.
export const CAMPOS_OBLIGATORIOS = ['nombre', 'apellido'] as const
export const CAMPOS_OPCIONALES = [
  'telefono',
  'fecha_nacimiento',
  'genero',
  'direccion',
  'alergias',
  'notas',
  'emergencia_nombre',
  'emergencia_telefono',
] as const
export const CAMPOS_PACIENTE = [...CAMPOS_OBLIGATORIOS, ...CAMPOS_OPCIONALES] as const

export type CampoPaciente = (typeof CAMPOS_PACIENTE)[number]
export type FormPaciente = Record<CampoPaciente, string>

const OBLIGATORIOS: readonly string[] = CAMPOS_OBLIGATORIOS

const norm = (v: unknown): string => (v == null ? '' : String(v))

export const formVacioPaciente: FormPaciente = {
  nombre: '',
  apellido: '',
  telefono: '',
  fecha_nacimiento: '',
  genero: '',
  direccion: '',
  alergias: '',
  notas: '',
  emergencia_nombre: '',
  emergencia_telefono: '',
}

// Snapshot del perfil → form (strings; null/undefined → ''). Fuente única de la hidratación.
export function snapshotPaciente(p: Partial<PacientePerfil> | null | undefined): FormPaciente {
  const out = {} as FormPaciente
  for (const k of CAMPOS_PACIENTE) out[k] = norm(p?.[k])
  return out
}

export function mismoFormPaciente(a: FormPaciente, b: FormPaciente): boolean {
  return (Object.keys(a) as CampoPaciente[]).every((k) => a[k] === b[k])
}

// Validación de obligatorios: nombre y apellido no pueden quedar vacíos.
// Devuelve el mensaje de error, o null si está OK.
export function validarPaciente(form: FormPaciente): string | null {
  if (!form.nombre.trim()) return 'El nombre es obligatorio'
  if (!form.apellido.trim()) return 'El apellido es obligatorio'
  return null
}

// Diff con whitelist. SOLO los campos que cambiaron respecto de `original`.
//
// A diferencia de camposPerfilCambiados (proveedor, mig 322), que por seguridad NUNCA blanquea un
// valor existente, acá el form ya viene HIDRATADO desde `original` (useEffect con guard !editando),
// así que un campo opcional vaciado ES intención del usuario → se envía `null`.
// nombre/apellido NUNCA se mandan null (son NOT NULL; la validación previa impide vaciarlos, y acá
// se ignoran defensivamente si llegaran vacíos).
export function camposPacienteCambiados(
  original: Partial<PacientePerfil> | null | undefined,
  form: FormPaciente,
): Partial<Record<CampoPaciente, string | null>> {
  const cambios: Partial<Record<CampoPaciente, string | null>> = {}
  for (const k of CAMPOS_PACIENTE) {
    const prev = norm(original?.[k])
    const next = norm(form[k])
    if (next === prev) continue
    if (next === '') {
      if (OBLIGATORIOS.includes(k)) continue // obligatorio vacío: nunca se manda (lo ataja validarPaciente)
      cambios[k] = null // opcional vaciado a propósito
    } else {
      cambios[k] = next
    }
  }
  return cambios
}
