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
//
// H3b: «Cerrar Sesión» pasa por la misma guardia. El destino viene con una `accionPrevia` (el logout)
// que se ejecuta recién cuando se confirma la salida (o enseguida, si no hay guardia), antes de navegar.
import { createContext, useCallback, useContext, useEffect, useRef, type ReactNode, type MutableRefObject } from 'react'
import { useNavigate } from 'react-router-dom'

export type AccionPrevia = () => void | Promise<void>
export type GuardiaNavegacion = (destino: string, accionPrevia?: AccionPrevia) => void

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
export async function navegarConGuardia(
  guardia: GuardiaNavegacion | null | undefined,
  navigate: (destino: string) => void,
  destino: string,
  accionPrevia?: AccionPrevia,
) {
  if (guardia) {
    // Sin acción previa la guardia recibe solo el destino (contrato de H3, sin cambios).
    if (accionPrevia) guardia(destino, accionPrevia)
    else guardia(destino)
    return
  }
  if (accionPrevia) await accionPrevia()
  navigate(destino)
}

/** Devuelve navegarConGuardia(destino) atado a la guardia registrada y al router. */
export function useNavegarConGuardia() {
  const ref = useContext(GuardiaCtx)
  const navigate = useNavigate()
  return useCallback(
    (destino: string, accionPrevia?: AccionPrevia) => navegarConGuardia(ref?.current, navigate, destino, accionPrevia),
    [ref, navigate],
  )
}
