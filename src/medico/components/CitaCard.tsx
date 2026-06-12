import { useNavigate, useLocation } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import type { CitaConPaciente } from '@/medico/types/medico.types'
import {
  User,
  Clock,
  CalendarDays,
  Stethoscope,
  CheckCircle2,
  XCircle,
  Play,
  FileText,
  AlertTriangle,
  Loader2,
} from 'lucide-react'

interface CitaCardProps {
  cita: CitaConPaciente
  onConfirmar?: (cita: CitaConPaciente) => Promise<void>
  onRechazar?: (cita: CitaConPaciente) => Promise<void>
  onEnSala?: (cita: CitaConPaciente) => Promise<void>
  onCompletar?: (cita: CitaConPaciente) => Promise<void>
  accionEnProgreso?: string | null
}

export default function CitaCard({
  cita,
  onConfirmar,
  onRechazar,
  onEnSala,
  onCompletar,
  accionEnProgreso,
}: CitaCardProps) {
  const navigate = useNavigate()
  const location = useLocation()
  // Mantener la consulta dentro del panel del médico cuando se navega desde /medico
  const base = location.pathname.startsWith('/medico') ? '/medico' : ''

  const estadoConfig: Record<string, { label: string; color: string; border: string; icon: React.ElementType }> = {
    solicitada: { label: 'Solicitada', color: 'bg-slate-100 text-slate-700', border: 'border-slate-400', icon: AlertTriangle },
    agendada: { label: 'Agendada', color: 'bg-amber-100 text-amber-700', border: 'border-amber-400', icon: Clock },
    confirmada: { label: 'Confirmada', color: 'bg-blue-100 text-blue-700', border: 'border-blue-400', icon: CheckCircle2 },
    en_curso: { label: 'En curso', color: 'bg-purple-100 text-purple-700', border: 'border-purple-400', icon: Play },
    completada: { label: 'Completada', color: 'bg-green-100 text-green-700', border: 'border-green-400', icon: CheckCircle2 },
    cancelada: { label: 'Cancelada', color: 'bg-red-100 text-red-700', border: 'border-red-400', icon: XCircle },
    no_show: { label: 'No asistió', color: 'bg-red-200 text-red-800', border: 'border-red-600', icon: XCircle },
  }

  const config = estadoConfig[cita.estado] || estadoConfig.agendada
  const EstadoIcon = config.icon

  const pacienteNombre = cita.paciente
    ? `${cita.paciente.nombre} ${cita.paciente.apellido}`
    : `Paciente #${cita.paciente_id}`

  const isLoading = (action: string) => accionEnProgreso === `${action}-${cita.id}`

  return (
    <Card className={`border-l-4 ${config.border} transition-shadow hover:shadow-sm`}>
      <CardContent className="p-4">
        <div className="flex flex-col md:flex-row md:items-start gap-4">
          {/* Info principal */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap mb-2">
              <Badge className={config.color}>
                <EstadoIcon className="h-3 w-3 mr-1" />
                {config.label}
              </Badge>
              <Badge variant="outline" className="text-xs">
                <CalendarDays className="h-3 w-3 mr-1" />
                {new Date(cita.fecha).toLocaleDateString('es-GT', {
                  weekday: 'short', day: 'numeric', month: 'short',
                })}
              </Badge>
              <Badge variant="outline" className="text-xs">
                <Clock className="h-3 w-3 mr-1" />
                {cita.hora_inicio?.slice(0, 5)}
              </Badge>
            </div>

            <div className="flex items-center gap-2 mb-1">
              <User className="h-4 w-4 text-muted-foreground" />
              <span className="font-medium">{pacienteNombre}</span>
            </div>

            {cita.paciente?.telefono && (
              <p className="text-xs text-muted-foreground ml-6">
                Tel: {cita.paciente.telefono}
              </p>
            )}

            {cita.motivo && (
              <p className="text-sm text-muted-foreground mt-1 truncate">
                Motivo: {cita.motivo}
              </p>
            )}

            {cita.notas && (
              <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                Notas: {cita.notas}
              </p>
            )}
          </div>

          {/* Acciones */}
          <div className="flex flex-col gap-2 min-w-[140px]">
            {/* Confirmar / Rechazar */}
            {(cita.estado === 'solicitada' || cita.estado === 'agendada') && (
              <>
                <Button
                  size="sm"
                  className="w-full bg-green-600 hover:bg-green-700"
                  onClick={() => onConfirmar?.(cita)}
                  disabled={isLoading('confirmar')}
                >
                  {isLoading('confirmar') ? (
                    <Loader2 className="h-4 w-4 animate-spin mr-1" />
                  ) : (
                    <CheckCircle2 className="h-4 w-4 mr-1" />
                  )}
                  Confirmar
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full text-red-600 border-red-200 hover:bg-red-50"
                  onClick={() => onRechazar?.(cita)}
                  disabled={isLoading('rechazar')}
                >
                  {isLoading('rechazar') ? (
                    <Loader2 className="h-4 w-4 animate-spin mr-1" />
                  ) : (
                    <XCircle className="h-4 w-4 mr-1" />
                  )}
                  Rechazar
                </Button>
              </>
            )}

            {/* Confirmada → En sala */}
            {cita.estado === 'confirmada' && (
              <>
                <Button
                  size="sm"
                  className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
                  onClick={() => onEnSala?.(cita)}
                  disabled={isLoading('ensala')}
                >
                  {isLoading('ensala') ? (
                    <Loader2 className="h-4 w-4 animate-spin mr-1" />
                  ) : (
                    <Play className="h-4 w-4 mr-1" />
                  )}
                  En sala
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full text-red-600 border-red-200 hover:bg-red-50"
                  onClick={() => onRechazar?.(cita)}
                  disabled={isLoading('rechazar')}
                >
                  Cancelar
                </Button>
              </>
            )}

            {/* En curso → Continuar consulta */}
            {cita.estado === 'en_curso' && (
              <Button
                size="sm"
                className="w-full bg-purple-600 hover:bg-purple-700"
                onClick={() => navigate(`${base}/consulta/${cita.id}`)}
              >
                <Stethoscope className="h-4 w-4 mr-1" />
                Continuar consulta
              </Button>
            )}

            {/* Completada → Ver consulta */}
            {cita.estado === 'completada' && (
              <Button
                size="sm"
                variant="outline"
                className="w-full"
                onClick={() => navigate(`${base}/consulta/${cita.id}`)}
              >
                <FileText className="h-4 w-4 mr-1" />
                Ver consulta
              </Button>
            )}

            {/* Cancelada / No show */}
            {(cita.estado === 'cancelada' || cita.estado === 'no_show') && (
              <Badge variant="secondary" className="w-full justify-center">
                {cita.estado === 'cancelada' ? 'Cita cancelada' : 'No asistió'}
              </Badge>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
