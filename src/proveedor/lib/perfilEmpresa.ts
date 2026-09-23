import type { EmpresaProveedora } from '@/proveedor/types/proveedor.types'

// Whitelist EXPLÍCITA de columnas de PERFIL editables por el proveedor desde /perfil.
// - `tipo` NO está: es columna PRIVILEGIADA (el guard de la mig 322 la bloquea con 42501). El front
//   tampoco debe mandarla.
// - logo_url / colores tampoco: viven en el flujo de personalización (solicitar/aprobar), no acá.
export const CAMPOS_PERFIL = [
  'nombre_empresa',
  'ruc_nit',
  'ciudad',
  'direccion',
  'email_contacto',
  'telefono',
] as const

export type CampoPerfil = (typeof CAMPOS_PERFIL)[number]
export type FormPerfil = Record<CampoPerfil, string>

const norm = (v: unknown): string => (v == null ? '' : String(v))

// Devuelve SOLO los campos del perfil que cambiaron respecto de `empresa` (diff con whitelist).
//
// CRITERIO (documentado) para el caso "form vacío":
//   Un campo VACÍO en el form NUNCA sobrescribe un valor existente en `empresa`. Ese estado —form ''
//   con empresa con valor— es exactamente el bug que estamos arreglando (form inicializado antes de
//   que `empresa` cargara) y, mirando un solo snapshot, es indistinguible de un "borrado a propósito".
//   Elegimos SEGURIDAD: no blanquear datos existentes. En consecuencia, vaciar un campo ya cargado NO
//   se propaga por este formulario (para eso haría falta una señal explícita de "campo tocado", fuera
//   del alcance de este arreglo).
//   SÍ se incluye en el diff: (1) un valor nuevo NO vacío y distinto del actual, y (2) llenar un campo
//   que en `empresa` estaba vacío/null.
export function camposPerfilCambiados(
  empresa: Partial<EmpresaProveedora> | null | undefined,
  form: FormPerfil,
): Partial<FormPerfil> {
  const cambios: Partial<FormPerfil> = {}
  for (const k of CAMPOS_PERFIL) {
    const prev = norm(empresa?.[k])
    const next = norm(form[k])
    if (next === prev) continue // sin cambio
    if (next === '' && prev !== '') continue // no blanquear un valor existente
    cambios[k] = next
  }
  return cambios
}
