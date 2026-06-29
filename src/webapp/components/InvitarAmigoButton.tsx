import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { useReferido, buildReferidoLink } from '@/webapp/hooks/useReferido'
import { Share2, Check, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

// Mensaje genérico (SIN PHI ni datos del paciente más allá del código en el link).
const MENSAJE = 'Te invito a EzPayConnect: gestioná tus citas, recetas y resultados médicos desde el celular. Conocela e instalala aquí:'

type ButtonVariant = 'default' | 'secondary' | 'outline' | 'ghost' | 'link'
type ButtonSize = 'default' | 'sm' | 'lg'

interface Props {
  className?: string
  variant?: ButtonVariant
  size?: ButtonSize
  label?: string
}

/**
 * Botón reusable "Invitá a un amigo" (lado referidor).
 * - Acción primaria: Web Share API si existe (móvil) → navigator.share.
 * - Fallback (desktop/sin share): copiar el link al portapapeles + feedback "Copiado".
 * - Genera el código LAZY al primer clic (el RPC puede tardar la 1ra vez → estado loading).
 * Sin PWA install prompt (diferido por branding).
 */
export default function InvitarAmigoButton({ className, variant = 'default', size = 'sm', label = 'Invitá a un amigo' }: Props) {
  const { generar, loading } = useReferido()
  const [copiado, setCopiado] = useState(false)

  const handleInvitar = async () => {
    const codigo = await generar()
    if (!codigo) {
      toast.error('No se pudo generar tu link de invitación')
      return
    }
    const link = buildReferidoLink(codigo)

    // Web Share API (mejora progresiva, típicamente móvil).
    if (typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      try {
        await navigator.share({ title: 'EzPayConnect', text: MENSAJE, url: link })
        return
      } catch (e: any) {
        // El usuario canceló el share → no hacer nada (no caer al fallback).
        if (e?.name === 'AbortError') return
        // Otro error de share → continuar al fallback de clipboard.
      }
    }

    // Fallback desktop: copiar al portapapeles.
    try {
      await navigator.clipboard.writeText(link)
      setCopiado(true)
      toast.success('Link de invitación copiado')
      setTimeout(() => setCopiado(false), 2000)
    } catch {
      toast.error('No se pudo copiar el link')
    }
  }

  return (
    <Button variant={variant} size={size} className={className} onClick={handleInvitar} disabled={loading}>
      {loading ? (
        <Loader2 className="h-4 w-4 mr-1 animate-spin" />
      ) : copiado ? (
        <Check className="h-4 w-4 mr-1" />
      ) : (
        <Share2 className="h-4 w-4 mr-1" />
      )}
      {copiado ? 'Copiado' : label}
    </Button>
  )
}
