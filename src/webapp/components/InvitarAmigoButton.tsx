import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { useReferido, buildReferidoLink } from '@/webapp/hooks/useReferido'
import { Check, Loader2, MoreHorizontal } from 'lucide-react'
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

// Glifo oficial de WhatsApp (lucide-react ya no incluye brand icons).
function WhatsAppIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden="true">
      <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51l-.57-.01c-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z"/>
    </svg>
  )
}

/**
 * Botón reusable "Invitá a un amigo" (lado referidor). Rinde DOS acciones:
 *  - CTA principal WhatsApp: link directo wa.me con mensaje+link en UN string encodeado
 *    (evita la combinación title/text/url separada que falla en silencio en algunos Android/WhatsApp).
 *  - "Más opciones": Web Share nativo (SMS/otras apps) con fallback a copiar al portapapeles.
 * Genera el código LAZY al primer clic (el RPC puede tardar la 1ra vez → estado loading).
 */
export default function InvitarAmigoButton({ className, variant = 'default', size = 'sm', label = 'Invitá a un amigo' }: Props) {
  const { generar, loading } = useReferido()
  const [copiado, setCopiado] = useState(false)

  // Genera el código y arma link + mensaje completo (mensaje + link). null si falla.
  const preparar = async (): Promise<{ texto: string } | null> => {
    const codigo = await generar()
    if (!codigo) {
      toast.error('No se pudo generar tu link de invitación')
      return null
    }
    return { texto: `${MENSAJE} ${buildReferidoLink(codigo)}` }
  }

  // CTA principal: WhatsApp directo.
  const handleWhatsApp = async () => {
    const p = await preparar()
    if (!p) return
    window.open(`https://wa.me/?text=${encodeURIComponent(p.texto)}`, '_blank', 'noopener')
  }

  // "Más opciones": Web Share nativo → fallback clipboard.
  const handleMasOpciones = async () => {
    const p = await preparar()
    if (!p) return

    if (typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      try {
        // Un solo `text` (mensaje+link juntos): más robusto que title/text/url separados.
        await navigator.share({ text: p.texto })
        return
      } catch (e: any) {
        if (e?.name === 'AbortError') return // usuario canceló → no caer al fallback
        console.error('[InvitarAmigo] navigator.share falló:', e) // diagnóstico a futuro
      }
    }

    // Fallback desktop/sin share: copiar mensaje completo + link.
    try {
      await navigator.clipboard.writeText(p.texto)
      setCopiado(true)
      toast.success('Mensaje de invitación copiado')
      setTimeout(() => setCopiado(false), 2000)
    } catch {
      toast.error('No se pudo copiar la invitación')
    }
  }

  return (
    <div className={cn('inline-flex items-center gap-2', className)}>
      {/* CTA WhatsApp: verde de marca (el className verde gana sobre el `variant` vía cn/twMerge). */}
      <Button
        variant={variant}
        size={size}
        className="bg-[#25D366] hover:bg-[#1EBE57] text-white border-transparent"
        onClick={handleWhatsApp}
        disabled={loading}
      >
        {loading ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <WhatsAppIcon className="h-4 w-4 mr-1" />}
        {label}
      </Button>

      {/* Más opciones: Web Share nativo / clipboard. */}
      <Button
        variant="ghost"
        size={size}
        className="px-2 text-muted-foreground"
        onClick={handleMasOpciones}
        disabled={loading}
        aria-label="Más opciones para compartir"
        title="Más opciones"
      >
        {copiado ? <Check className="h-4 w-4" /> : <MoreHorizontal className="h-4 w-4" />}
      </Button>
    </div>
  )
}
