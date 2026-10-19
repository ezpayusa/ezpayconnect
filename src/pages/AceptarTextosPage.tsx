import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Loader2, ShieldAlert } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/ui/button'
import type { TextoLegal } from '@/legal/catalogo'
import { aceptarTextos, mensajeErrorTextosLegales, obtenerPendientes } from '@/lib/textosLegales'
import { DECLARACION_MAYORIA_EDAD } from '@/components/legal/CasillaTextosLegales'

// GL-02: pantalla /aceptar-textos. El gate la usa cuando la cuenta tiene textos legales pendientes (versión vigente sin
// aceptar). Falla cerrado: si no se puede saber qué falta aceptar, no deja pasar (no hay "Más tarde"); la única salida
// sin aceptar es cerrar sesión. Al terminar vuelve a ?next=, solo si es una ruta interna (nextSeguro).
// No importa react-markdown: los textos se leen en sus páginas públicas, en otra pestaña.

const ORIGEN_PRUEBA = 'https://origen.invalid'

/** Devuelve raw solo si es una ruta interna de esta app; si no, '/'. Nunca deja salir a otro origen. */
export function nextSeguro(raw: string | null): string {
  if (!raw || !raw.startsWith('/')) return '/'
  if (raw.startsWith('//') || raw.startsWith('/\\')) return '/'
  // Barras invertidas, caracteres de control (los navegadores descartan \t y \n: '/\t/evil.com' = '//evil.com') y esquemas.
  if (raw.includes('\\') || /[\u0000-\u001f\u007f]/.test(raw) || raw.includes('://')) return '/'
  try {
    if (new URL(raw, ORIGEN_PRUEBA).origin !== ORIGEN_PRUEBA) return '/'
  } catch {
    return '/'
  }
  return raw
}

// Portal → login. Tiene que coincidir con el login al que manda cada *PrivateRoute (code-review #3): el repartidor
// vuelve a /farmacia/login (RepartidorPrivateRoute) y el visitador a /proveedor/login (VisitadorPrivateRoute).
const LOGIN_POR_PORTAL: [string, string][] = [
  ['/paciente', '/paciente/login'],
  ['/proveedor', '/proveedor/login'],
  ['/farmacia', '/farmacia/login'],
  ['/laboratorio', '/laboratorio/login'],
  ['/repartidor', '/farmacia/login'],
  ['/visitador', '/proveedor/login'],
]

/** Login del portal al que pertenece el destino (review PR #56 H4/H6/H7): al cerrar sesión o sin sesión se vuelve ahí. */
export function loginPara(destino: string): string {
  // H7: la ruta sin query ni hash ('/paciente?tab=x' es del portal paciente).
  const ruta = destino.split(/[?#]/, 1)[0]
  for (const [portal, login] of LOGIN_POR_PORTAL) {
    if (ruta === portal || ruta.startsWith(portal + '/')) return login
  }
  return '/login'
}

type Estado = 'cargando' | 'falla' | 'lista'

export default function AceptarTextosPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const destino = nextSeguro(searchParams.get('next'))

  const [estado, setEstado] = useState<Estado>('cargando')
  const [pendientes, setPendientes] = useState<TextoLegal[]>([])
  const [marcados, setMarcados] = useState<Set<string>>(new Set())
  // D-4 (review PR #56 H3): con el consentimiento de salud pendiente, la declaración de mayoría de edad es obligatoria.
  // Es condición de UI, igual que en el alta: no viaja a la RPC.
  const [declara, setDeclara] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const vivo = useRef(true)

  const cargar = useCallback(async () => {
    setEstado('cargando')
    const r = await obtenerPendientes()
    if (!vivo.current) return
    if (!r.ok) {
      setEstado('falla')
      return
    }
    if (r.pendientes.length === 0) {
      navigate(destino, { replace: true })
      return
    }
    setPendientes(r.pendientes)
    setMarcados(new Set())
    setDeclara(false)
    setEstado('lista')
  }, [navigate, destino])

  useEffect(() => {
    vivo.current = true
    supabase.auth.getSession().then(({ data }) => {
      if (!vivo.current) return
      if (!data.session?.user) {
        navigate(loginPara(destino), { replace: true })
        return
      }
      void cargar()
    })
    return () => {
      vivo.current = false
    }
  }, [navigate, cargar, destino])

  const alternar = (codigo: string, checked: boolean) => {
    setMarcados((prev) => {
      const s = new Set(prev)
      if (checked) s.add(codigo)
      else s.delete(codigo)
      return s
    })
  }

  const todasMarcadas = pendientes.length > 0 && pendientes.every((t) => marcados.has(t.codigo))
  const pideDeclaracion = pendientes.some((t) => t.codigo === 'consentimiento_salud')
  const puedeAceptar = todasMarcadas && (!pideDeclaracion || declara)

  const aceptar = async () => {
    if (!puedeAceptar || enviando) return
    setEnviando(true)
    setError(null)
    const r = await aceptarTextos(
      pendientes.map((t) => ({ codigo: t.codigo, version: t.version })),
      'login',
    )
    if (!vivo.current) return
    setEnviando(false)
    if (!('error' in r)) {
      navigate(destino, { replace: true })
      return
    }
    setError(mensajeErrorTextosLegales(r.error))
    // LG003: la versión vigente cambió mientras la pantalla estaba abierta → recargar lo que hay que aceptar.
    if (r.error.code === 'LG003') void cargar()
  }

  const cerrarSesion = async () => {
    await supabase.auth.signOut()
    navigate(loginPara(destino), { replace: true })
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center px-4 py-8">
      <div className="w-full max-w-lg rounded-lg bg-white p-5 shadow-sm sm:p-8">
        {estado === 'cargando' && (
          <div className="flex justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-slate-400" aria-label="Cargando" />
          </div>
        )}

        {estado === 'falla' && (
          <div className="text-center">
            <ShieldAlert className="mx-auto h-12 w-12 text-[#1E5C8E] mb-3" />
            <h1 className="text-xl font-bold text-[#1a2a3a] mb-2">No pudimos verificar tus aceptaciones</h1>
            <p className="text-sm text-muted-foreground mb-6">
              Para seguir necesitamos confirmar qué textos legales tienes que aceptar. Inténtalo de nuevo en un momento.
            </p>
            <Button onClick={() => void cargar()} className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
              Reintentar
            </Button>
          </div>
        )}

        {estado === 'lista' && (
          <>
            <h1 className="text-xl font-bold text-[#1a2a3a] mb-2">Antes de continuar</h1>
            <p className="text-sm text-muted-foreground mb-5">
              Para seguir usando la plataforma necesitas leer y aceptar estos textos. Cada uno se abre en otra pestaña.
            </p>
            <ul className="space-y-3 mb-5">
              {pendientes.map((t) => {
                const idInput = `aceptar-${t.codigo}`
                return (
                  <li key={t.codigo} className="flex items-start gap-2">
                    <input
                      type="checkbox"
                      id={idInput}
                      checked={marcados.has(t.codigo)}
                      disabled={enviando}
                      onChange={(e) => alternar(t.codigo, e.target.checked)}
                      className="mt-0.5 h-4 w-4 shrink-0 accent-[#1E5C8E] disabled:cursor-not-allowed"
                    />
                    <label htmlFor={idInput} className="text-sm leading-snug text-[#1a2a3a]">
                      Leí y acepto{' '}
                      <a href={t.ruta} target="_blank" rel="noopener noreferrer" className="text-[#1E5C8E] underline">
                        {t.titulo}
                        <span className="sr-only"> (se abre en otra pestaña)</span>
                      </a>{' '}
                      (versión {t.version}).
                    </label>
                  </li>
                )
              })}
            </ul>
            {pideDeclaracion && (
              <div className="mb-5 flex items-start gap-2 border-t pt-4">
                <input
                  type="checkbox"
                  id="aceptar-declaracion-mayoria"
                  checked={declara}
                  disabled={enviando}
                  onChange={(e) => setDeclara(e.target.checked)}
                  className="mt-0.5 h-4 w-4 shrink-0 accent-[#1E5C8E] disabled:cursor-not-allowed"
                />
                <label htmlFor="aceptar-declaracion-mayoria" className="text-sm leading-snug text-[#1a2a3a]">
                  {DECLARACION_MAYORIA_EDAD}
                </label>
              </div>
            )}
            {error && (
              <p role="alert" className="mb-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
                {error}
              </p>
            )}
            <Button
              onClick={() => void aceptar()}
              disabled={!puedeAceptar || enviando}
              className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
            >
              {enviando && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              Aceptar y continuar
            </Button>
          </>
        )}

        <Button variant="outline" onClick={() => void cerrarSesion()} className="mt-3 w-full">
          Cerrar sesión
        </Button>
      </div>
    </div>
  )
}
