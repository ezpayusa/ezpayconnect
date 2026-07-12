import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { CheckCircle2, XCircle, AlertTriangle, Loader2 } from 'lucide-react'
import { PoweredBy } from '@/components/branding/PoweredBy'

// Página PÚBLICA (sin sesión): el paciente llega desde el link del email y confirma la
// recepción de su receta. Llama la edge pública confirmar-recepcion-receta (verify_jwt=false)
// por GET con ?token=. NO muestra PHI: solo un estado de agradecimiento/error.

const EDGE_URL = 'https://fqnsmvkxsuujahhmpzuk.supabase.co/functions/v1/confirmar-recepcion-receta'

type Estado = 'loading' | 'confirmada' | 'ya_confirmada' | 'token_invalido' | 'error'

export default function ConfirmarRecetaPage() {
  const [params] = useSearchParams()
  const token = params.get('token')
  const [estado, setEstado] = useState<Estado>('loading')
  const yaCorrio = useRef(false)

  useEffect(() => {
    // StrictMode monta 2 veces en dev: el guard evita disparar 2 confirmaciones.
    if (yaCorrio.current) return
    yaCorrio.current = true

    if (!token) { setEstado('token_invalido'); return }

    ;(async () => {
      try {
        const resp = await fetch(`${EDGE_URL}?token=${encodeURIComponent(token)}`)
        const data = await resp.json().catch(() => ({}))
        switch (data?.estado) {
          case 'confirmada':
          case 'sin_pais':        // gap de país = fallo interno nuestro, NO se muestra al paciente
            setEstado('confirmada'); break
          case 'ya_confirmada':
            setEstado('ya_confirmada'); break
          case 'token_invalido':
            setEstado('token_invalido'); break
          default:                // 'error', estado desconocido, o body no-JSON
            setEstado('error')
        }
      } catch {
        setEstado('error')        // fallo de red
      }
    })()
  }, [token])

  const vistas: Record<Exclude<Estado, 'loading'>, { icon: React.ReactNode; titulo: string; texto: string }> = {
    confirmada: {
      icon: <CheckCircle2 className="h-14 w-14 text-emerald-500" />,
      titulo: '¡Gracias!',
      texto: 'Confirmaste la recepción de tu receta.',
    },
    ya_confirmada: {
      icon: <CheckCircle2 className="h-14 w-14 text-emerald-500" />,
      titulo: 'Ya confirmada',
      texto: 'Ya habías confirmado la recepción de esta receta.',
    },
    token_invalido: {
      icon: <XCircle className="h-14 w-14 text-red-400" />,
      titulo: 'Enlace inválido',
      texto: 'Este enlace no es válido o expiró.',
    },
    error: {
      icon: <AlertTriangle className="h-14 w-14 text-amber-500" />,
      titulo: 'Algo salió mal',
      texto: 'Ocurrió un error. Intentá de nuevo más tarde.',
    },
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border p-8 text-center">
        {estado === 'loading' ? (
          <div className="flex flex-col items-center gap-4 py-6">
            <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
            <p className="text-sm text-slate-500">Confirmando tu recepción…</p>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-4">
            {vistas[estado].icon}
            <h1 className="text-xl font-bold text-[#1a2a3a]">{vistas[estado].titulo}</h1>
            <p className="text-sm text-slate-500">{vistas[estado].texto}</p>
          </div>
        )}
        <div className="mt-8 flex justify-center">
          <PoweredBy />
        </div>
      </div>
    </div>
  )
}
