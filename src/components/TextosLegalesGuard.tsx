import { useEffect } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { obtenerPendientes } from '@/lib/textosLegales'

// GL-02: guard global de textos legales. Si la cuenta logueada tiene textos pendientes (versión vigente sin aceptar),
// la manda a /aceptar-textos?next=<donde estaba>. Falla cerrado: si no se puede verificar (red, RPC, catálogo del front
// desincronizado), también la manda ahí, y esa página re-verifica y muestra la pantalla de falla.
// El "0 pendientes" se recuerda en memoria por uid y solo durante la sesión, a propósito: una versión nueva se pide en
// el próximo login (nada en el almacenamiento del navegador). MustChangePasswordGuard tiene prioridad.
// Es un gate de UX: la barrera real es la base (aceptar_textos_legales / textos_legales_pendientes).

const RUTAS_EXENTAS = new Set([
  '/aceptar-textos',
  '/set-password',
  '/confirmar-receta',
  '/terminos',
  '/privacidad',
  '/consentimiento-salud',
  '/condiciones-profesionales',
])

/** Rutas donde el guard no actúa: la propia pantalla de aceptación, los textos públicos, logins y registros. */
export function esRutaExenta(pathname: string): boolean {
  if (RUTAS_EXENTAS.has(pathname)) return true
  if (pathname.startsWith('/planes-')) return true
  return pathname.split('/').some((s) => s === 'login' || s === 'registro' || s.startsWith('registro-'))
}

// uids que ya dieron "0 pendientes" en esta sesión de la pestaña.
const sinPendientes = new Set<string>()

/** Solo para tests. */
export function resetCacheTextosLegales() {
  sinPendientes.clear()
}

export default function TextosLegalesGuard() {
  const navigate = useNavigate()
  const { pathname, search } = useLocation()
  useEffect(() => {
    // Cada ejecución del effect es una ruta; al cambiar de ruta o desmontar, sus respuestas pendientes se descartan.
    let vigente = true
    let uidActual: string | null = null
    let enVuelo: string | null = null

    const check = (user: any) => {
      if (!vigente) return
      if (!user) {
        uidActual = null
        sinPendientes.clear()
        return
      }
      const uid: string = user.id
      uidActual = uid
      if (user.user_metadata?.must_change_password === true) return
      if (esRutaExenta(pathname)) return
      if (sinPendientes.has(uid)) return
      // getSession + INITIAL_SESSION (o un TOKEN_REFRESHED) no disparan una segunda RPC para el mismo uid y ruta.
      if (enVuelo === uid) return
      enVuelo = uid
      void (async () => {
        let ok = false
        let hayPendientes = true
        try {
          const r = await obtenerPendientes()
          ok = r.ok
          hayPendientes = !r.ok || r.pendientes.length > 0
        } catch {
          ok = false
        }
        if (enVuelo === uid) enVuelo = null
        if (!vigente || uidActual !== uid) return
        if (ok && !hayPendientes) {
          sinPendientes.add(uid)
          return
        }
        navigate(`/aceptar-textos?next=${encodeURIComponent(pathname + search)}`, { replace: true })
      })()
    }

    supabase.auth.getSession().then(({ data }) => check(data.session?.user ?? null))
    const sub = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_OUT') sinPendientes.clear()
      check(session?.user ?? null)
    })
    return () => { vigente = false; sub.data.subscription.unsubscribe() }
  }, [pathname, search, navigate])
  return null
}
