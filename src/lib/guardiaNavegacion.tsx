// H3: guardia de navegación para el portal del médico.
//
// Una pantalla con cambios sin guardar (ConsultaPage) registra una guardia con useGuardiaNavegacion(fn);
// la barra lateral navega con navegarConGuardia(destino): si hay guardia, le pasa el destino (y la
// pantalla decide: abrir su diálogo o navegar); si no hay, navega normal. Sin provider (la consulta
// abierta fuera de /medico) todo es un no-op y se navega directo.
//
// Límites conocidos (no se resuelven acá):
//  - La app usa <BrowserRouter> (no un data router), así que useBlocker no está disponible y el
//    botón «Atrás» del navegador NO pasa por esta guardia.
//  - Al cerrar o recargar la pestaña solo queda el aviso nativo del navegador (beforeunload), cuyo
//    texto no se puede personalizar.
import { createContext, useCallback, useContext, useEffect, useRef, type ReactNode, type MutableRefObject } from 'react'
import { useNavigate } from 'react-router-dom'

export type GuardiaNavegacion = (destino: string) => void

const GuardiaCtx = createContext<MutableRefObject<GuardiaNavegacion | null> | null>(null)

export function GuardiaNavegacionProvider({ children }: { children: ReactNode }) {
  const ref = useRef<GuardiaNavegacion | null>(null)
  return <GuardiaCtx.Provider value={ref}>{children}</GuardiaCtx.Provider>
}

/** Registra `fn` como guardia mientras el componente esté montado; null la quita. */
export function useGuardiaNavegacion(fn: GuardiaNavegacion | null) {
  const ref = useContext(GuardiaCtx)
  useEffect(() => {
    if (!ref) return
    ref.current = fn
    return () => {
      if (ref.current === fn) ref.current = null
    }
  }, [ref, fn])
}

/** Decide entre la guardia y la navegación directa (puro, para el test). */
export function navegarConGuardia(
  guardia: GuardiaNavegacion | null | undefined,
  navigate: (destino: string) => void,
  destino: string,
) {
  if (guardia) guardia(destino)
  else navigate(destino)
}

/** Devuelve navegarConGuardia(destino) atado a la guardia registrada y al router. */
export function useNavegarConGuardia() {
  const ref = useContext(GuardiaCtx)
  const navigate = useNavigate()
  return useCallback(
    (destino: string) => navegarConGuardia(ref?.current, navigate, destino),
    [ref, navigate],
  )
}
