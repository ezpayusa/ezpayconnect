import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

// Clave estable en sessionStorage (vive lo que dure la pestaña; sobrevive al registro→login).
const KEY = 'referido_codigo'

// Guard a NIVEL DE SESIÓN DE PÁGINA (módulo): sobrevive remontajes del WebAppLayout, a diferencia de
// un useRef/state local que se reinicia al remontar. Evita llamadas duplicadas concurrentes si el layout
// se remonta ANTES de que llegue la respuesta del RPC. Se reinicia solo al recargar la página.
let intentoEnCurso = false
// Formato del código: base32 sin ambigüedad (sin 0/1/I/L/O), 8 chars — espejo del RPC generar_codigo_referido.
const RE_CODIGO = /^[2-9A-HJ-NP-Z]{8}$/

/** Valida/normaliza el ref. Devuelve el código en mayúsculas si matchea el formato, o null. */
export function sanitizarRef(raw: string | null | undefined): string | null {
  if (!raw) return null
  const up = raw.trim().toUpperCase()
  return RE_CODIGO.test(up) ? up : null
}

/**
 * Captura el ?ref de la URL en el primer aterrizaje (landing pública /planes, o login/registro).
 * - Solo guarda si el ref matchea el formato base32-8 (descarta basura/inyección).
 * - PRIMER TOQUE gana: no pisa un ref ya guardado.
 */
export function useCapturarReferido() {
  const [params] = useSearchParams()
  useEffect(() => {
    const ref = sanitizarRef(params.get('ref'))
    if (!ref) return
    try {
      if (!sessionStorage.getItem(KEY)) sessionStorage.setItem(KEY, ref)
    } catch {
      /* sessionStorage no disponible (modo privado estricto) → ignorar */
    }
  }, [params])
}

/**
 * Dispara la atribución best-effort cuando el paciente YA está logueado y su perfil cargó.
 * Se monta en el área privada (WebAppLayout). El RPC deriva el paciente de auth.uid(), por eso
 * va en LOGIN (la fila pacientes ya existe del registro), no en el registro.
 *
 * Limpieza:
 *  - Respuesta de negocio (registrado/ya_atribuido/ok:false motivo) → llega como DATA sin error → LIMPIAR (no reintentar).
 *  - error presente (red/infra o no_auth por race) → NO limpiar → reintentar en el próximo login.
 */
export function useAtribuirReferido(perfilCargado: boolean) {
  useEffect(() => {
    // Guard de módulo: como máximo UNA llamada en vuelo por sesión de página (sobrevive remontajes).
    if (!perfilCargado || intentoEnCurso) return

    let ref: string | null = null
    try { ref = sessionStorage.getItem(KEY) } catch { /* */ }
    if (!ref) return

    intentoEnCurso = true
    ;(async () => {
      try {
        const { data, error } = await supabase.rpc('registrar_mi_referido', { _codigo: ref })
        if (error) {
          // red/infra o no_auth → liberar el guard para reintentar en un login posterior (NO limpiar el código).
          intentoEnCurso = false
          return
        }
        // resultado de negocio (registrado/ya_atribuido/ok:false) → limpiar; el guard queda tomado (no refire).
        try { sessionStorage.removeItem(KEY) } catch { /* */ }
        if ((data as any)?.estado === 'registrado') {
          toast.success('¡Gracias por unirte a EzPayConnect!')
        }
      } catch {
        // throw inesperado (red) → liberar para reintentar.
        intentoEnCurso = false
      }
    })()
  }, [perfilCargado])
}
