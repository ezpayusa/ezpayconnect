import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Stethoscope } from 'lucide-react'
import type { MedicoResumen } from '@/proveedor/hooks/useMedicosDisponibles'

interface Props {
  medicos: MedicoResumen[]
  onSeleccionar: (medicoId: string) => void
}

// Lista de médicos del agendar del visitador (PWA /visitador, ancho máximo max-w-md).
export default function ListaMedicosAgendar({ medicos, onSeleccionar }: Props) {
  return (
    // Una sola columna: el PWA mide max-w-md y dos columnas dejaban la tarjeta en ~200 px, sin lugar para el texto.
    <div className="grid grid-cols-1 gap-3" data-testid="lista-medicos">
      {medicos.map((m) => (
        <Card
          key={m.id}
          className="cursor-pointer hover:border-[#1E5C8E] transition-colors"
          onClick={() => onSeleccionar(m.id)}
        >
          <CardContent className="p-4 flex items-center gap-3">
            <div className="flex items-center gap-3 min-w-0 flex-1" data-testid="medico-izq">
              <div className="w-10 h-10 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center flex-shrink-0">
                <Stethoscope className="h-5 w-5 text-[#1E5C8E]" />
              </div>
              <div className="min-w-0 flex-1" data-testid="medico-texto">
                <h3 className="font-semibold leading-tight break-words">{m.nombre_completo}</h3>
                <p className="text-sm text-muted-foreground truncate">{m.especialidad || 'Especialidad no indicada'}</p>
              </div>
            </div>
            <Button
              size="sm"
              variant="outline"
              className="flex-shrink-0"
              onClick={(e) => {
                e.stopPropagation()
                onSeleccionar(m.id)
              }}
            >
              Seleccionar
            </Button>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
