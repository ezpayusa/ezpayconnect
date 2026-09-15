import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import type { ExamenLiberable } from '@/lib/liberacionExamenes'

// Confirmación de "Liberar los N listos". Nombra CADA examen: liberar información de salud de varios
// resultados de un clic sin ver cuáles es exactamente lo que el gate existe para evitar.
// La lista que se muestra es la MISMA que se libera (la pantalla pasa el snapshot tomado al abrir).

interface Props {
  examenes: ExamenLiberable[] | null
  liberando: boolean
  onConfirmar: () => void
  onCancelar: () => void
}

export function ConfirmarLiberacionDialog({ examenes, liberando, onConfirmar, onCancelar }: Props) {
  const n = examenes?.length ?? 0
  return (
    <AlertDialog open={Boolean(examenes)} onOpenChange={(abierto) => { if (!abierto && !liberando) onCancelar() }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            ¿Liberar {n === 1 ? 'este resultado' : `estos ${n} resultados`} al paciente?
          </AlertDialogTitle>
          <AlertDialogDescription>
            El paciente {n === 1 ? 'lo va a ver' : 'los va a ver'} en su app y recibe una notificación por cada uno.
            Si preferís hablarlo antes, liberalos de a uno desde cada examen.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <ul className="max-h-60 space-y-1 overflow-y-auto rounded-md border bg-gray-50 p-3 text-sm" aria-label="Exámenes a liberar">
          {(examenes ?? []).map((ex) => (
            <li key={ex.id} className="flex justify-between gap-3">
              <span className="font-medium text-gray-800">{ex.tipo}</span>
              {ex.fecha_resultado && <span className="shrink-0 text-gray-500">Resultado: {ex.fecha_resultado}</span>}
            </li>
          ))}
        </ul>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={liberando}>Cancelar</AlertDialogCancel>
          <AlertDialogAction
            disabled={liberando}
            onClick={(e) => { e.preventDefault(); onConfirmar() }}
            className="bg-[#1E5C8E] hover:bg-[#164a72]"
          >
            {liberando ? 'Liberando…' : `Liberar ${n === 1 ? 'resultado' : `los ${n}`}`}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
