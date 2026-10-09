import { supabase } from '@/lib/supabase'

// Alta diferida de empresas (mig 373). En prod "Confirm email" está ON: el signUp del autorregistro no devuelve
// sesión, así que la empresa no se puede crear en el momento. El alta guarda los datos en la metadata de auth
// (raw_user_meta_data -> 'registro_empresa', con las claves de RegistroEmpresa) y, al primer login con el correo
// confirmado, el front llama a public.completar_registro_proveedor(), que valida esos datos y crea la empresa con la
// sesión del usuario.
// El servidor es la barrera: valida todo y es idempotente (si la cuenta ya es de proveedor, devuelve su empresa).
// Limpiar la metadata después del alta es best-effort: si falla, la RPC igual devuelve la misma empresa la próxima vez.
// Errores: RP001-RP004 de la RPC traen un mensaje escrito para el usuario final; 42501 y 22023 los propaga desde
// registrar_proveedor con texto de Postgres, por eso van con texto propio. Logs sin datos del usuario: solo el código.

/** Datos de la empresa que el alta guarda en raw_user_meta_data -> 'registro_empresa' (las claves que lee la mig 373). */
export type RegistroEmpresa = {
  nombre_empresa: string
  tipo: 'farmacia' | 'laboratorio_clinico' | 'laboratorio_farmaceutico' | 'empresa_afin'
  ruc_nit: string | null
  pais_id: string | null
  ciudad: string | null
  direccion: string | null
  email_contacto: string
  telefono: string | null
  nombre_completo: string
}

export interface ErrorRegistroEmpresa {
  code: string | null
  message: string | null
}

export type ResultadoCompletarRegistro =
  | { ok: true; empresaId: string }
  | { ok: false; error: ErrorRegistroEmpresa }

/** Login del portal que corresponde al tipo de empresa. */
export function loginDePortal(tipo: RegistroEmpresa['tipo']): string {
  if (tipo === 'farmacia') return '/farmacia/login'
  if (tipo === 'laboratorio_clinico') return '/laboratorio/login'
  return '/proveedor/login'
}

export async function completarRegistroPendiente(): Promise<ResultadoCompletarRegistro> {
  try {
    const { data, error } = await supabase.rpc('completar_registro_proveedor')
    if (error) {
      console.error('[registroDiferido] completar_registro_proveedor falló', error.code ?? null)
      return { ok: false, error: { code: error.code ?? null, message: error.message ?? null } }
    }
    // Best-effort: la empresa ya existe; si no se puede limpiar la metadata, la RPC sigue siendo idempotente.
    try {
      const { error: errLimpieza } = await supabase.auth.updateUser({ data: { registro_empresa: null } })
      if (errLimpieza) console.error('[registroDiferido] no se pudo limpiar registro_empresa', errLimpieza.code ?? null)
    } catch (err) {
      console.error('[registroDiferido] no se pudo limpiar registro_empresa', (err as { code?: string } | null)?.code ?? null)
    }
    return { ok: true, empresaId: data as string }
  } catch (err) {
    console.error('[registroDiferido] completar_registro_proveedor lanzó', (err as { code?: string } | null)?.code ?? null)
    return { ok: false, error: { code: null, message: null } }
  }
}

const CODIGOS_CON_MENSAJE = new Set(['RP001', 'RP002', 'RP003', 'RP004'])

export const MENSAJE_IDENTIDAD_PREVIA =
  'Esta cuenta ya tiene otro tipo de acceso en la plataforma. Usa el portal que corresponde a tu cuenta.'
export const MENSAJE_PAIS_NO_VALIDO = 'El país elegido no está disponible para el registro. Escríbenos a soporte.'
export const MENSAJE_GENERICO_REGISTRO = 'No pudimos completar el registro de tu empresa. Inténtalo de nuevo.'
/** Alta sin sesión (Confirm email ON): la empresa se crea en el primer login, después de confirmar el correo. */
export const MENSAJE_CONFIRMA_CORREO =
  'Te enviamos un correo para confirmar tu cuenta. Después de confirmarlo, inicia sesión para terminar el registro de tu empresa.'

export function mensajeErrorRegistroEmpresa(error: { code?: string | null; message?: string | null } | null | undefined): string {
  if (error?.code && CODIGOS_CON_MENSAJE.has(error.code) && error.message) return error.message
  if (error?.code === '42501') return MENSAJE_IDENTIDAD_PREVIA
  if (error?.code === '22023') return MENSAJE_PAIS_NO_VALIDO
  return MENSAJE_GENERICO_REGISTRO
}
