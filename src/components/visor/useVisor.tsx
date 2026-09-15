import { useCallback, useState } from 'react'
import VisorArchivos, { type ArchivoVisor } from './VisorArchivos'
import { MENSAJE_FALLA, descargarArchivo } from '@/lib/signedUrl'

// ############################################################################################
// useVisor — la ÚNICA forma de montar el visor en una pantalla
// ############################################################################################
//   const { abrir, visor } = useVisor()
//   <button onClick={() => abrir([archivoDeResultado(ex.archivo_url)])}>Ver archivo</button>
//   ...
//   {visor}
//
// Una pantalla no arma su propio <VisorArchivos>: lo pide acá. El test
// src/components/visor/visor.estructura.test.ts falla si una pantalla vuelve a abrir un resultado
// con openSignedUrl, y exige que las 5 lectoras monten `useVisor()` + `{visor}`.

export const BUCKET_RESULTADOS = 'resultados-examenes'

/** Un resultado de examen (examenes.archivo_url) como archivo del visor. */
export function archivoDeResultado(path: string, nombre?: string): ArchivoVisor {
  return { bucket: BUCKET_RESULTADOS, path, nombre }
}

/**
 * El "Descargar" que va AL LADO de "Ver archivo". Baja por el mismo camino que el visor (firma de
 * 60 s → blob → <a download>), así que el bearer tampoco toca la URL. Conserva el aviso que ya daba
 * openSignedUrl cuando falla, en vez de fallar en silencio.
 */
export async function descargarResultado(path: string | null): Promise<void> {
  const r = await descargarArchivo(BUCKET_RESULTADOS, path)
  if (r && 'motivo' in r) alert(MENSAJE_FALLA[r.motivo])
}

export function useVisor() {
  const [estado, setEstado] = useState<{ archivos: ArchivoVisor[]; indice: number } | null>(null)

  const abrir = useCallback((archivos: ArchivoVisor[], indice = 0) => {
    if (archivos.length === 0) return
    setEstado({ archivos, indice: Math.min(Math.max(indice, 0), archivos.length - 1) })
  }, [])

  const onIndice = useCallback((i: number) => setEstado((s) => (s ? { ...s, indice: i } : s)), [])
  const cerrar = useCallback(() => setEstado(null), [])

  const visor = estado ? (
    <VisorArchivos archivos={estado.archivos} indice={estado.indice} onIndice={onIndice} onCerrar={cerrar} />
  ) : null

  return { abrir, visor }
}
